# lex-finance demo — pre-trade gate, trail provenance, regulatory reporting
#
# Three guarantees in a single run:
#   1. Pre-trade gate: typed rejection before a byte reaches the exchange
#   2. Trail provenance: every decision gets an immutable, replayable entry_id
#   3. Regulatory reporting: MiFID II RTS 22 + FINRA CAT from the same fill
#
# Run:
#   lex run --allow-effects fs_write,io,sql,time examples/demo.lex main

import "std.io" as io
import "std.str" as str
import "std.list" as list
import "std.int" as int
import "std.sql" as sql

import "lex-trail/src/log" as trail_log

import "lex-trade/src/order" as order
import "lex-trade/src/limit" as limit
import "lex-trade/src/validation" as v
import "lex-trade/src/validation_io" as vio
import "lex-trade/src/rejection" as rejection

import "lex-fix/src/v44/execution_report" as er

import "../src/reporting/mifid_rts22" as rts22
import "../src/reporting/finra_cat" as cat

# ---- Fixtures -------------------------------------------------------

fn risk_limits() -> limit.RiskLimit {
  { max_order_qty: 1000, max_notional_str: "1000000.00", allowed_symbols: [], allowed_sides: ["buy", "sell"] }
}

fn oversized_order() -> order.Order {
  order.order("ORD-BAD", "MSFT", OrderBuy(()), 5000, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

fn good_order() -> order.Order {
  order.order("ORD-001", "MSFT", OrderBuy(()), 100, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

fn mock_fill(o :: order.Order) -> er.ExecutionReport {
  { exec_id: "EXEC-001", order_id: o.id, cl_ord_id: o.id, exec_type: ExecFill(()), ord_status: StatusFilled(()), symbol: o.symbol, side: Buy(()), order_qty: int.to_str(o.quantity), cum_qty: int.to_str(o.quantity), leaves_qty: "0", avg_px: "125.50", last_px: "125.50", last_qty: int.to_str(o.quantity), text: "" }
}

fn instrument() -> rts22.Instrument {
  { isin: "US5949181045", mic: "XNAS" }
}

fn reporting_ctx(txn_ref :: Str) -> rts22.ReportingContext {
  { transaction_ref_no: txn_ref, buyer_lei: "5493001KJTIIGC8Y1R12", seller_lei: "549300ABCDEF12345678", trade_date: "2026-05-30", trade_time: "2026-05-30T14:00:00.123456Z" }
}

fn cat_ctx() -> cat.OrderContext {
  { cat_order_id: "CAT-0001", firm_id: "FIRM01", symbol: "MSFT", side: "B", order_type: "LMT" }
}

# ---- Helpers --------------------------------------------------------

fn section(title :: Str) -> [io] Unit {
  let hr := "──────────────────────────────────────────────"
  let __1 := io.print("")
  let __2 := io.print(hr)
  let __3 := io.print("  " + title)
  io.print(hr)
}

fn print_rejection(o :: order.Order, violations :: List[rejection.RejectionReason]) -> [io] Unit {
  let label := "  " + o.id + "  " + int.to_str(o.quantity) + " " + o.symbol + " buy limit"
  let reasons := list.map(violations, rejection.describe)
  let __1 := io.print(label)
  io.print("  → REJECTED  " + str.join(reasons, "; "))
}

# ---- Section 1: Pre-trade gate (pure) -------------------------------

fn show_pre_trade_gate() -> [io] Unit {
  let __s := section("1 — Pre-trade gate")
  let lim := risk_limits()

  # Oversized order: 5000 shares, limit is 1000
  match v.validate(oversized_order(), lim, "ALGO01", "EXCH01") {
    Rejected(vs) => print_rejection(oversized_order(), vs),
    Accepted(_) => io.print("  ORD-BAD: unexpected acceptance"),
  }

  # Valid order: 100 shares, well within limits
  match v.validate(good_order(), lim, "ALGO01", "EXCH01") {
    Rejected(vs) => print_rejection(good_order(), vs),
    Accepted(_) => io.print("  ORD-001  100 MSFT buy limit $125.50  → ACCEPTED"),
  }
}

# ---- Section 2: Trail provenance (effectful) ------------------------

fn show_trail_provenance(trail :: trail_log.Log) -> [io, sql, time] Unit {
  let __s := section("2 — Trail provenance")
  let lim := risk_limits()
  let o := good_order()
  let lar := vio.validate_log_and_record(o, lim, None, { max_deviation_bps: 200 }, "ALGO01", "EXCH01", trail, "validation.validate@0.9.7")
  match lar.result {
    Rejected(_) => io.print("  unexpected rejection"),
    Accepted(_) => {
      let __1 := io.print("  ORD-001 validated and logged")
      io.print("  entry_id  " + lar.entry_id)
    },
  }
}

# ---- Section 3: MiFID II RTS 22 report ------------------------------

fn show_mifid_report() -> [io] Unit {
  let __s := section("3 — MiFID II RTS 22 transaction report")
  let exec_report := mock_fill(good_order())
  match rts22.from_execution(exec_report, instrument(), reporting_ctx("TXN-0001")) {
    Err(missing) => io.print("  missing fields: " + str.join(missing, ", ")),
    Ok(report) => io.print(rts22.to_json_report(report)),
  }
}

# ---- Section 4: FINRA CAT events ------------------------------------

fn show_finra_cat() -> [io] Unit {
  let __s := section("4 — FINRA CAT events (core subset)")
  let ctx := cat_ctx()
  let new_event := cat.from_lifecycle(ctx, OnSubmit({ qty: 100, timestamp_ns: 1780000000123456789 }))
  let route_event := cat.from_lifecycle(ctx, OnRoute({ route_dest: "XNAS", qty: 100, timestamp_ns: 1780000000234567890 }))
  let fill_event := cat.from_lifecycle(ctx, OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: 1780000000987654321 }))
  let __1 := io.print(cat.to_json_report(new_event))
  let __2 := io.print(cat.to_json_report(route_event))
  io.print(cat.to_json_report(fill_event))
}

# ---- main -----------------------------------------------------------

fn main() -> [io, sql, fs_write, time] Unit {
  let __hdr := io.print("  lex-finance — typed finance infrastructure for AI agents")

  let __gate := show_pre_trade_gate()

  match trail_log.open_memory() {
    Err(e) => io.print("  trail init failed: " + e),
    Ok(trail) => {
      let __prov := show_trail_provenance(trail)
      ()
    },
  }

  let __mifid := show_mifid_report()
  show_finra_cat()
}
