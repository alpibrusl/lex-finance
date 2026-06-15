# lex-finance — end-to-end integration test (issue #13)
#
# Exercises the full pre-trade → fill → position → reconstruction stack
# in a single test program. No real TCP, no live market data — all
# effects are local (in-memory SQLite).
#
# Flow:
#   1. Agent emits a typed Order
#   2. lex-trade validates against risk limits + FIX conformance
#      → logged to lex-trail + written to reconstruction store
#   3. Mock ExecutionReport (ExecFill) simulates an exchange fill
#   4. Fill updates the position book via lex-positions
#   5. Trade is reconstructed from the trail entry_id
#   6. replay(reconstruction) re-runs validate — result must match
#
# This test is the executable specification of the central claim:
# structural pre-execution gate, exact provenance, deterministic replay.
#
# Effects: [sql, fs_write, time]

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "std.sql" as sql

import "lex-trail/src/log" as trail_log

import "lex-trade/src/order" as order

import "lex-trade/src/limit" as limit

import "lex-trade/src/validation" as v

import "lex-trade/src/validation_io" as vio

import "lex-trade/src/reconstruct" as rc

import "lex-positions/src/position_store" as ps

import "lex-positions/src/fill_from_er" as ffe

import "lex-fix/src/v44/execution_report" as er

import "lex-fix/src/v44/enums" as en

import "lex-orm/src/connection" as orm_conn

fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn fail(why :: Str) -> Result[Unit, Str] {
  Err(why)
}

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    pass()
  } else {
    fail(label)
  }
}

# ---- Fixtures -------------------------------------------------------
fn agent_order() -> order.Order {
  order.order("ORD-LIFE-001", "MSFT", OrderBuy(()), 100, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

fn risk_limits() -> limit.RiskLimit {
  { max_order_qty: 1000, max_notional_str: "5000000.00", allowed_symbols: [], allowed_sides: ["buy", "sell"] }
}

fn mock_fill_report(o :: order.Order) -> er.ExecutionReport {
  { exec_id: "EXEC-001", order_id: o.id, cl_ord_id: o.id, exec_type: ExecFill(()), ord_status: StatusFilled(()), symbol: o.symbol, side: Buy(()), order_qty: int.to_str(o.quantity), cum_qty: int.to_str(o.quantity), leaves_qty: "0", avg_px: "125.50", last_px: "125.50", last_qty: int.to_str(o.quantity), text: "" }
}

# ---- Position update step ------------------------------------------
fn apply_fill_step(pos_db :: orm_conn.ConnDb, o :: order.Order, mock_er :: er.ExecutionReport) -> [sql] Result[Unit, Str] {
  let fills := ffe.fill_from_er(mock_er)
  let pos_key := { account: o.account, symbol: o.symbol }
  match list.head(fills) {
    None => fail("mock exec report produced no fills — check exec_type and last_qty"),
    Some(fill) => match ps.apply_and_store(pos_db, pos_key, fill) {
      Err(_) => fail("position update failed"),
      Ok(updated) => assert_true(updated.qty == 100, str.concat("expected qty=100 after buy fill, got=", int.to_str(updated.qty))),
    },
  }
}

# ---- Reconstruction + replay step ----------------------------------
fn replay_step(trail_db :: Db, entry_id :: Str) -> [sql] Result[Unit, Str] {
  match rc.reconstruct(trail_db, entry_id) {
    Err(e) => fail(str.concat("reconstruct failed: ", e)),
    Ok(rec) => {
      let replay_result := rc.replay(rec)
      let matched := rc.results_match(rec, replay_result)
      if not matched {
        fail("replay result does not match stored result — non-determinism detected")
      } else {
        if rec.result_tag == "Accepted" {
          pass()
        } else {
          fail(str.concat("expected Accepted in reconstruction, got: ", rec.result_tag))
        }
      }
    },
  }
}

# ---- Full lifecycle -------------------------------------------------
fn full_order_lifecycle_test() -> [sql, fs_write, time] Result[Unit, Str] {
  match trail_log.open_memory() {
    Err(e) => fail(str.concat("trail open failed: ", e)),
    Ok(trail) => match sql.open(":memory:") {
      Err(e) => fail(str.concat("pos db open failed: ", e.message)),
      Ok(pos_db) => {
        let pos_conn := { dialect: DbSqlite(()), handle: pos_db }
        match ps.init(pos_conn) {
          Err(_) => fail("position store init failed"),
          Ok(_) => {
            let o := agent_order()
            let lar := vio.validate_log_and_record(o, risk_limits(), None, { max_deviation_bps: 200 }, "ALGO01", "EXCH01", trail, "validation.validate@0.9.7")
            match lar.result {
              Rejected(_) => fail("order should be accepted by the pre-trade gate"),
              Accepted(_) => {
                if str.is_empty(lar.entry_id) {
                  fail("entry_id must be non-empty after successful trail append")
                } else {
                  match apply_fill_step(pos_conn, o, mock_fill_report(o)) {
                    Err(msg) => Err(msg),
                    Ok(_) => {
                      replay_step(trail.db, lar.entry_id)
                    },
                  }
                }
              },
            }
          },
        }
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Int {
  let results := [full_order_lifecycle_test()]
  list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

