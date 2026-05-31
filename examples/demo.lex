# lex-finance demo — margin gate, pre-trade validation, trail provenance,
#                    regulatory reporting
#
# Four guarantees in a single run:
#   1. Margin gate: typed rejection before lex-trade validation even runs
#   2. Pre-trade gate: typed qty/symbol/conformance rejection
#   3. Trail provenance: every accepted order gets an immutable entry_id
#   4. Regulatory reporting: MiFID II RTS 22 + FINRA CAT from the same fill
#
# Run:
#   lex run --allow-effects fs_write,io,sql,time examples/demo.lex main

import "std.io" as io
import "std.str" as str
import "std.list" as list
import "std.int" as int

import "lex-money/src/decimal" as d

import "lex-trail/src/log" as trail_log

import "lex-trade/src/order" as order
import "lex-trade/src/limit" as limit
import "lex-trade/src/rejection" as rejection
import "lex-trade/src/validation_io" as vio

import "lex-fix/src/v44/execution_report" as er

import "../src/pre_trade" as pt
import "../src/reporting/mifid_rts22" as rts22
import "../src/reporting/finra_cat" as cat

# ---- Fixtures -------------------------------------------------------

fn lim() -> limit.RiskLimit {
  { max_order_qty: 1000, max_notional_str: "1000000.00", allowed_symbols: [], allowed_sides: ["buy", "sell"] }
}

fn price(c :: Int, e :: Int) -> d.Decimal {
  { coefficient: c, exponent: e }
}

fn tolerance() -> { max_deviation_bps :: Int } {
  { max_deviation_bps: 200 }
}

# ORD-MARGIN: 600 NVDA @ $500 → notional $300k → IM $75k > $50k cap → breach
fn margin_order() -> order.Order {
  order.order("ORD-MARGIN", "NVDA", OrderBuy(()), 600, LimitOrder("500.00"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

# ORD-BAD: 5000 MSFT @ $1 → IM $12.50 (passes margin) but qty 5000 > 1000 → lex-trade rejects
fn qty_order() -> order.Order {
  order.order("ORD-BAD", "MSFT", OrderBuy(()), 5000, LimitOrder("1.00"), "0", "ACC-MAIN", "TRADER-01", "20260530-10:00:00.000")
}

# ORD-001: 100 MSFT @ $125.50 → notional $12.5k → IM $3.1k → accepted
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
  rts22.reporting_ctx(txn_ref, "5493001KJTIIGC8Y1R12", "549300ABCDEF12345678", "2026-05-30", "2026-05-30T14:00:00.123456Z")
}

fn cat_ctx() -> cat.OrderContext {
  { cat_order_id: "CAT-0001", firm_id: "FIRM01", reporter_imid: "FIRM01", symbol: "MSFT", side: "B", order_type: "LMT" }
}

# ---- Helpers --------------------------------------------------------

fn section(title :: Str) -> [io] Unit {
  let hr := "──────────────────────────────────────────────"
  let __1 := io.print("")
  let __2 := io.print(hr)
  let __3 := io.print("  " + title)
  io.print(hr)
}

fn show_outcome(o :: order.Order, lar :: vio.LogAndRecord) -> [io] Unit {
  let label := "  " + o.id + "  " + int.to_str(o.quantity) + " " + o.symbol
  match lar.result {
    Rejected(vs) => {
      let reasons := list.map(vs, rejection.describe)
      let __1 := io.print(label)
      io.print("  → REJECTED  " + str.join(reasons, "; "))
    },
    Accepted(_) => {
      let __1 := io.print(label + "  → ACCEPTED")
      io.print("  entry_id  " + lar.entry_id)
    },
  }
}

# ---- Section 1: Combined gate (margin + pre-trade) ------------------

fn show_combined_gate(trail :: trail_log.Log) -> [io, sql, time] Unit {
  let __s := section("1 — Combined gate: margin → pre-trade validation → trail")

  # Margin breach: short-circuits before lex-trade validation runs
  let gate_nvda := pt.margin_gate(price(50000, -2))
  let lar1 := pt.validate_with_margin(margin_order(), lim(), gate_nvda, None, tolerance(), "ALGO01", "EXCH01", trail, "")
  let __1 := show_outcome(margin_order(), lar1)

  # Passes margin ($12.50 IM) but fails lex-trade qty limit (5000 > 1000)
  let gate_msft := pt.margin_gate(price(100, -2))
  let lar2 := pt.validate_with_margin(qty_order(), lim(), gate_msft, None, tolerance(), "ALGO01", "EXCH01", trail, "")
  let __2 := show_outcome(qty_order(), lar2)

  # Both checks pass: entry_id logged to trail
  let gate_good := pt.margin_gate(price(12550, -2))
  let lar3 := pt.validate_with_margin(good_order(), lim(), gate_good, None, tolerance(), "ALGO01", "EXCH01", trail, "validation.validate@0.9.7")
  show_outcome(good_order(), lar3)
}

# ---- Section 2: MiFID II RTS 22 report ------------------------------

fn show_mifid_report() -> [io] Unit {
  let __s := section("2 — MiFID II RTS 22 transaction report")
  match rts22.from_execution(mock_fill(good_order()), instrument(), reporting_ctx("TXN-0001")) {
    Err(missing) => io.print("  missing fields: " + str.join(missing, ", ")),
    Ok(report) => io.print(rts22.to_json_report(report)),
  }
}

# ---- Section 3: FINRA CAT events ------------------------------------

fn show_finra_cat() -> [io] Unit {
  let __s := section("3 — FINRA CAT events (core subset)")
  let ctx := cat_ctx()
  let new_ev    := cat.from_lifecycle(ctx, OnSubmit({ qty: 100, timestamp_ns: 1780000000123456789 }))
  let route_ev  := cat.from_lifecycle(ctx, OnRoute({ route_dest: "XNAS", qty: 100, timestamp_ns: 1780000000234567890 }))
  let fill_ev   := cat.from_lifecycle(ctx, OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: 1780000000987654321 }))
  let __1 := io.print(cat.to_json_report(new_ev))
  let __2 := io.print(cat.to_json_report(route_ev))
  io.print(cat.to_json_report(fill_ev))
}

# ---- main -----------------------------------------------------------

fn main() -> [io, sql, fs_write, time] Unit {
  let __hdr := io.print("  lex-finance — typed finance infrastructure for AI agents")

  match trail_log.open_memory() {
    Err(e) => io.print("  trail init failed: " + e),
    Ok(trail) => {
      let __1 := show_combined_gate(trail)
      ()
    },
  }

  let __2 := show_mifid_report()
  show_finra_cat()
}
