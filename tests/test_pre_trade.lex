# Tests for pre_trade — margin gate wired in front of lex-trade validation.
#
# Covers:
#   1. Margin breach → Rejected([MarginLimitBreached]) before trail write
#   2. Margin pass + valid order → Accepted, trail entry_id non-empty
#   3. Margin gate skipped (None) → delegates to normal validation path
#   4. Margin pass + invalid order → Rejected by lex-trade (not margin)
#
# Effects: [sql, fs_write, time]

import "std.list" as list

import "std.str" as str

import "lex-money/src/decimal" as d

import "lex-trail/src/log" as trail_log

import "lex-trade/src/order" as order

import "lex-trade/src/limit" as limit

import "lex-trade/src/rejection" as rejection

import "../src/pre_trade" as pt

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
fn lim() -> limit.RiskLimit {
  { max_order_qty: 1000, max_notional_str: "1000000.00", allowed_symbols: [], allowed_sides: ["buy", "sell"] }
}

fn valid_order() -> order.Order {
  order.order("ORD-001", "MSFT", OrderBuy(()), 100, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

fn oversized_order() -> order.Order {
  order.order("ORD-BAD", "MSFT", OrderBuy(()), 5000, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

fn price(c :: Int, e :: Int) -> d.Decimal {
  { coefficient: c, exponent: e }
}

fn tolerance() -> { max_deviation_bps :: Int } {
  { max_deviation_bps: 200 }
}

# ---- Tests ----------------------------------------------------------
# A 600-share order at $500 → notional $300k → IM $75k > $50k cap → breach
fn test_margin_breach_rejects_before_trail() -> [sql, fs_write, time] Result[Unit, Str] {
  match trail_log.open_memory() {
    Err(e) => fail("trail open: " + e),
    Ok(log) => {
      let gate := pt.margin_gate(price(50000, -2))
      let o := order.order("ORD-X", "NVDA", OrderBuy(()), 600, LimitOrder("500.00"), "0", "ACC-1", "T1", "20260530-10:00:00.000")
      let lar := pt.validate_with_margin(o, lim(), gate, None, tolerance(), "ALGO01", "EXCH01", log, "")
      match lar.result {
        Accepted(_) => fail("expected margin breach rejection"),
        Rejected(vs) => {
          let is_margin := list.fold(vs, false, fn (acc :: Bool, r :: rejection.RejectionReason) -> Bool {
            match r {
              MarginLimitBreached(_) => true,
              _ => acc,
            }
          })
          match assert_true(is_margin, "rejection reason is MarginLimitBreached") {
            Err(e) => Err(e),
            Ok(_) => assert_true(str.is_empty(lar.entry_id), "entry_id empty on margin breach"),
          }
        },
      }
    },
  }
}

# A 200-share order at $400 → notional $80k → IM $20k < $50k cap → passes
fn test_margin_pass_proceeds_to_validation() -> [sql, fs_write, time] Result[Unit, Str] {
  match trail_log.open_memory() {
    Err(e) => fail("trail open: " + e),
    Ok(log) => {
      let gate := pt.margin_gate(price(40000, -2))
      let lar := pt.validate_with_margin(valid_order(), lim(), gate, None, tolerance(), "ALGO01", "EXCH01", log, "")
      match lar.result {
        Rejected(vs) => fail("expected acceptance, got: " + str.join(list.map(vs, rejection.describe), "; ")),
        Accepted(_) => assert_true(not str.is_empty(lar.entry_id), "entry_id non-empty on acceptance"),
      }
    },
  }
}

# default_margin_gate (mark_price = None) skips the check — valid order accepted
fn test_default_gate_skips_margin_check() -> [sql, fs_write, time] Result[Unit, Str] {
  match trail_log.open_memory() {
    Err(e) => fail("trail open: " + e),
    Ok(log) => {
      let gate := pt.default_margin_gate()
      let lar := pt.validate_with_margin(valid_order(), lim(), gate, None, tolerance(), "ALGO01", "EXCH01", log, "")
      match lar.result {
        Rejected(vs) => fail("expected acceptance without margin check, got: " + str.join(list.map(vs, rejection.describe), "; ")),
        Accepted(_) => pass(),
      }
    },
  }
}

# Margin passes but the order is over the qty limit → lex-trade rejects it
fn test_margin_pass_then_qty_rejection() -> [sql, fs_write, time] Result[Unit, Str] {
  match trail_log.open_memory() {
    Err(e) => fail("trail open: " + e),
    Ok(log) => {
      let gate := pt.margin_gate(price(100, -2))
      let lar := pt.validate_with_margin(oversized_order(), lim(), gate, None, tolerance(), "ALGO01", "EXCH01", log, "")
      match lar.result {
        Accepted(_) => fail("expected qty rejection after margin pass"),
        Rejected(vs) => {
          let is_qty := list.fold(vs, false, fn (acc :: Bool, r :: rejection.RejectionReason) -> Bool {
            match r {
              ExceedsMaxQty(_) => true,
              _ => acc,
            }
          })
          assert_true(is_qty, "rejection reason is ExceedsMaxQty, not margin")
        },
      }
    },
  }
}

# ---- Suite ----------------------------------------------------------
fn suite() -> [sql, fs_write, time] List[Result[Unit, Str]] {
  [test_margin_breach_rejects_before_trail(), test_margin_pass_proceeds_to_validation(), test_default_gate_skips_margin_check(), test_margin_pass_then_qty_rejection()]
}

fn run_all() -> [sql, fs_write, time] Int {
  list.fold(suite(), 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

