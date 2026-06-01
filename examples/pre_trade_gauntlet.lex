# lex-finance — killer demo
#
# Five orders. Four walls. One paper trail.
#
# Each order hits a different enforcement layer:
#   Wall 1 — Margin gate (lex-risk Reg-T)
#   Wall 2 — Risk limit (lex-trade qty ceiling)
#   Wall 3 — FIX conformance + venue profile (NYSE: no stop orders)
#   Wall 4 — SOR venue availability (DirectTo CBOE, only NYSE/NASDAQ available)
#   Order 5 — Passes all walls; trail + routing + MiFID II + FINRA CAT
#
# Run:
#   lex run --allow-effects fs_write,io,sql,time examples/killer_demo.lex main

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

import "lex-fix/src/venue" as vn
import "lex-fix/src/v44/new_order_single" as nos
import "lex-fix/src/v44/execution_report" as er
import "lex-fix/src/conformance" as conf

import "lex-sor/src/router" as router
import "lex-sor/src/strategy" as strategy
import "lex-sor/src/route" as sor_route

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

# Wall 1: 600 NVDA @ $500 → notional $300k → IM $75k > $50k cap → margin breach
fn order_nvda() -> order.Order {
  order.order("ORD-NVDA", "NVDA", OrderBuy(()), 600, LimitOrder("500.00"), "0", "ACC-MAIN", "TRADER-01", "20260601-09:30:00.000")
}

# Wall 2: 5000 MSFT @ $1 → passes margin but qty 5000 > limit 1000
fn order_bad_qty() -> order.Order {
  order.order("ORD-BAD", "MSFT", OrderBuy(()), 5000, LimitOrder("1.00"), "0", "ACC-MAIN", "TRADER-01", "20260601-09:30:00.000")
}

# Wall 3: Stop order routed to NYSE → venue profile blocks stop orders
fn order_stop_nyse() -> order.Order {
  order.order("ORD-STOP", "MSFT", OrderBuy(()), 100, StopOrder("126.00"), "0", "ACC-MAIN", "TRADER-01", "20260601-09:30:00.000")
}

# Wall 4: DirectTo CBOE but only NYSE/NASDAQ in available list
fn order_dark() -> order.Order {
  order.order("ORD-DARK", "MSFT", OrderBuy(()), 100, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260601-09:30:00.000")
}

# Order 5: Passes everything
fn order_good() -> order.Order {
  order.order("ORD-001", "MSFT", OrderBuy(()), 100, LimitOrder("125.50"), "0", "ACC-MAIN", "TRADER-01", "20260601-09:30:00.000")
}

fn mock_fill(o :: order.Order) -> er.ExecutionReport {
  { exec_id: "EXEC-001", order_id: o.id, cl_ord_id: o.id, exec_type: ExecFill(()), ord_status: StatusFilled(()), symbol: o.symbol, side: Buy(()), order_qty: int.to_str(o.quantity), cum_qty: int.to_str(o.quantity), leaves_qty: "0", avg_px: "125.50", last_px: "125.50", last_qty: int.to_str(o.quantity), text: "" }
}

# ---- Helpers --------------------------------------------------------

fn section(n :: Int, title :: Str) -> [io] Unit {
  let hr := "──────────────────────────────────────────────────────────────────"
  let __1 := io.print("")
  let __2 := io.print(hr)
  let __3 := io.print("  WALL " + int.to_str(n) + " — " + title)
  io.print(hr)
}

fn section_accepted() -> [io] Unit {
  let hr := "══════════════════════════════════════════════════════════════════"
  let __1 := io.print("")
  let __2 := io.print(hr)
  let __3 := io.print("  ORDER 5 — ACCEPTED: trail · routing · MiFID II · FINRA CAT")
  io.print(hr)
}

fn tick() -> [io] Unit {
  io.print("  ✓")
}

fn cross() -> [io] Unit {
  io.print("  ✗")
}

# ---- Wall 1: Margin gate -------------------------------------------

fn show_wall_margin(trail :: trail_log.Log) -> [io, sql, time] Unit {
  let __s := section(1, "Margin gate — Reg-T initial margin")
  let gate := pt.margin_gate(price(50000, -2))
  let lar := pt.validate_with_margin(order_nvda(), lim(), gate, None, { max_deviation_bps: 200 }, "ALGO01", "EXCH01", trail, "")
  match lar.result {
    Accepted(_) => {
      let __c := tick()
      io.print("  ORD-NVDA: unexpectedly accepted")
    },
    Rejected(vs) => {
      let __c := cross()
      let reasons := list.map(vs, rejection.describe)
      let __r := io.print("  ORD-NVDA  600 NVDA @ $500.00")
      io.print("  → REJECTED  " + str.join(reasons, "; "))
    },
  }
}

# ---- Wall 2: Risk limit (qty ceiling) ------------------------------

fn show_wall_risk(trail :: trail_log.Log) -> [io, sql, time] Unit {
  let __s := section(2, "Risk limit — qty ceiling (lex-trade)")
  let gate := pt.margin_gate(price(100, -2))
  let lar := pt.validate_with_margin(order_bad_qty(), lim(), gate, None, { max_deviation_bps: 200 }, "ALGO01", "EXCH01", trail, "")
  match lar.result {
    Accepted(_) => {
      let __c := tick()
      io.print("  ORD-BAD: unexpectedly accepted")
    },
    Rejected(vs) => {
      let __c := cross()
      let reasons := list.map(vs, rejection.describe)
      let __r := io.print("  ORD-BAD  5000 MSFT @ $1.00")
      io.print("  → REJECTED  " + str.join(reasons, "; "))
    },
  }
}

# ---- Wall 3: FIX conformance + venue profile -----------------------

fn show_wall_fix() -> [io] Unit {
  let __s := section(3, "FIX conformance — NYSE profile: no_stop_orders")
  let fix_msg := nos.to_fix_message(
    nos.new_order("ORD-STOP", "MSFT", Buy(()), 100, Stop(()), None, Day(()), "20260601-09:30:00.000", "ALGO01", "EXCH01", None),
    1
  )
  let nyse_profile := vn.venue_profile(Nyse(()))
  match conf.validate_new_order_venue(fix_msg, nyse_profile) {
    Ok(_) => {
      let __c := tick()
      io.print("  ORD-STOP: unexpectedly passed")
    },
    Err(errors) => {
      let __c := cross()
      let __r := io.print("  ORD-STOP  100 MSFT  Stop order → NYSE")
      let descs := conf.describe_errors(errors)
      io.print("  → REJECTED  " + str.join(descs, "; "))
    },
  }
}

# ---- Wall 4: SOR venue unavailability ------------------------------

fn show_wall_sor() -> [io] Unit {
  let __s := section(4, "SOR — venue unavailable (DirectTo CBOE, only NYSE/NASDAQ)")
  let available := [Nyse(()), Nasdaq(())]
  match router.route_order(order_dark(), DirectTo(Cboe(())), available) {
    Ok(_) => {
      let __c := tick()
      io.print("  ORD-DARK: unexpectedly routed")
    },
    Err(reason) => {
      let __c := cross()
      let __r := io.print("  ORD-DARK  100 MSFT @ $125.50  DirectTo(CBOE)")
      io.print("  → REJECTED  " + reason)
    },
  }
}

# ---- Order 5: All walls cleared ------------------------------------

fn show_route(r :: sor_route.Route) -> [io] Unit {
  io.print("    " + vn.venue_to_str(r.venue) + "  " + int.to_str(r.quantity) + " shares")
}

fn show_routes(rs :: List[sor_route.Route]) -> [io] Unit {
  match list.head(rs) {
    None => (),
    Some(r) => {
      let __1 := show_route(r)
      show_routes(list.tail(rs))
    },
  }
}

fn show_accepted(trail :: trail_log.Log) -> [io, sql, time] Unit {
  let __s := section_accepted()

  # Step 1: Pre-trade gate (margin + risk)
  let __hdr1 := io.print("")
  let __hdr2 := io.print("  [1/4] Pre-trade gate")
  let gate := pt.default_margin_gate()
  let lar := pt.validate_with_margin(order_good(), lim(), gate, None, { max_deviation_bps: 200 }, "ALGO01", "EXCH01", trail, "validation.validate@0.9.7")
  let __outcome := match lar.result {
    Rejected(vs) => {
      let reasons := list.map(vs, rejection.describe)
      io.print("  → REJECTED  " + str.join(reasons, "; "))
    },
    Accepted(_) => {
      let __c := tick()
      let __r := io.print("  ORD-001  100 MSFT @ $125.50  → ACCEPTED")
      io.print("  entry_id  " + lar.entry_id)
    },
  }

  # Step 2: Smart order routing
  let __hdr3 := io.print("")
  let __hdr4 := io.print("  [2/4] Smart order routing — Sweep([NYSE, NASDAQ])")
  let available := [Nyse(()), Nasdaq(())]
  let __routing := match router.route_order(order_good(), Sweep([Nyse(()), Nasdaq(())]), available) {
    Err(reason) => io.print("  routing failed: " + reason),
    Ok(decision) => {
      let __c := tick()
      let __r := io.print("  strategy: " + decision.strategy_used)
      show_routes(decision.routes)
    },
  }

  # Step 3: MiFID II RTS 22
  let __hdr5 := io.print("")
  let __hdr6 := io.print("  [3/4] MiFID II RTS 22 — transaction report (RTS 22 fields)")
  let fill := mock_fill(order_good())
  let instr := { isin: "US5949181045", mic: "XNAS" }
  let rts_ctx := rts22.reporting_ctx("TXN-0001", "5493001KJTIIGC8Y1R12", "549300ABCDEF12345678", "2026-06-01", "2026-06-01T09:30:00.123456Z")
  let __mifid := match rts22.from_execution(fill, instr, rts_ctx) {
    Err(missing) => io.print("  missing fields: " + str.join(missing, ", ")),
    Ok(report) => {
      let __c := tick()
      let json := rts22.to_json_report(report)
      let preview := if str.len(json) > 200 {
        str.slice(json, 0, 200) + "..."
      } else {
        json
      }
      io.print("  " + preview)
    },
  }

  # Step 4: FINRA CAT events
  let __hdr7 := io.print("")
  let __hdr8 := io.print("  [4/4] FINRA CAT — lifecycle events")
  let cat_ctx := { cat_order_id: "CAT-0001", firm_id: "FIRM01", reporter_imid: "FIRM01", symbol: "MSFT", side: "B", order_type: "LMT" }
  let ev1 := cat.from_lifecycle(cat_ctx, OnSubmit({ qty: 100, timestamp_ns: 1780000000123456789 }))
  let ev2 := cat.from_lifecycle(cat_ctx, OnRoute({ route_dest: "XNYS", qty: 50, timestamp_ns: 1780000000234567890 }))
  let ev3 := cat.from_lifecycle(cat_ctx, OnRoute({ route_dest: "XNAS", qty: 50, timestamp_ns: 1780000000345678901 }))
  let ev4 := cat.from_lifecycle(cat_ctx, OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: 1780000000987654321 }))
  let __c2 := tick()
  let __e1 := io.print("  CAT  " + cat.event_type(ev1) + "  (NewOrder)")
  let __e2 := io.print("  CAT  " + cat.event_type(ev2) + "  (RouteOrder → XNYS)")
  let __e3 := io.print("  CAT  " + cat.event_type(ev3) + "  (RouteOrder → XNAS)")
  io.print("  CAT  " + cat.event_type(ev4) + "  (Fill @ 125.50)")
}

# ---- main -----------------------------------------------------------

fn main() -> [io, sql, fs_write, time] Unit {
  let __hdr1 := io.print("  lex-finance  ·  Five orders. Four walls. One paper trail.")
  let __hdr2 := io.print("")
  let __hdr3 := io.print("  Wall 1  margin gate         — Reg-T initial margin breach")
  let __hdr4 := io.print("  Wall 2  risk limit          — qty ceiling exceeded")
  let __hdr5 := io.print("  Wall 3  FIX conformance     — NYSE prohibits stop orders")
  let __hdr6 := io.print("  Wall 4  SOR availability    — venue not in session list")
  let __hdr7 := io.print("  Order 5 passes all walls    — trail + routing + MiFID II + FINRA CAT")
  let __hdr8 := io.print("")
  match trail_log.open_memory() {
    Err(e) => io.print("  trail init failed: " + e),
    Ok(trail) => {
      let __1 := show_wall_margin(trail)
      let __2 := show_wall_risk(trail)
      let __3 := show_wall_fix()
      let __4 := show_wall_sor()
      show_accepted(trail)
    },
  }
}
