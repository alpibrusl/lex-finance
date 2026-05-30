# tests for src/reporting/mifid_rts22.lex

import "std.list" as list

import "std.str" as str

import "lex-fix/src/v44/execution_report" as er

import "../src/reporting/mifid_rts22" as rts22

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

fn buy_execution() -> er.ExecutionReport {
  { exec_id: "EX-1", order_id: "OID-1", cl_ord_id: "ORD-1", exec_type: ExecFill(()), ord_status: StatusFilled(()), symbol: "MSFT", side: Buy(()), order_qty: "100", cum_qty: "100", leaves_qty: "0", avg_px: "125.50", last_px: "125.50", last_qty: "100", text: "" }
}

fn sell_execution() -> er.ExecutionReport {
  { exec_id: "EX-2", order_id: "OID-2", cl_ord_id: "ORD-2", exec_type: ExecFill(()), ord_status: StatusFilled(()), symbol: "MSFT", side: Sell(()), order_qty: "100", cum_qty: "100", leaves_qty: "0", avg_px: "125.50", last_px: "126.00", last_qty: "100", text: "" }
}

fn instrument() -> rts22.Instrument {
  { isin: "US5949181045", mic: "XNAS" }
}

fn full_context() -> rts22.ReportingContext {
  { transaction_ref_no: "TXN-1", buyer_lei: "5493001KJTIIGC8Y1R12", seller_lei: "549300ABCDEF12345678", trade_date: "2026-05-30", trade_time: "2026-05-30T14:00:00.123456Z" }
}

# ---- from_execution --------------------------------------------
fn test_from_execution_ok() -> Result[Unit, Str] {
  match rts22.from_execution(buy_execution(), instrument(), full_context()) {
    Err(_) => fail("complete inputs should produce a report"),
    Ok(r) => assert_true(r.price == "125.50" and r.quantity == "100" and r.instrument_isin == "US5949181045" and r.trading_venue == "XNAS" and r.side == "BUYI", "report fields mapped"),
  }
}

fn test_side_sell_maps() -> Result[Unit, Str] {
  match rts22.from_execution(sell_execution(), instrument(), full_context()) {
    Err(_) => fail("complete inputs should produce a report"),
    Ok(r) => assert_true(r.side == "SELL" and r.price == "126.00", "sell side + last price"),
  }
}

fn test_missing_leis_reported() -> Result[Unit, Str] {
  let ctx := { transaction_ref_no: "TXN-3", buyer_lei: "", seller_lei: "", trade_date: "2026-05-30", trade_time: "2026-05-30T14:00:00.123456Z" }
  match rts22.from_execution(buy_execution(), instrument(), ctx) {
    Ok(_) => fail("missing LEIs should produce errors"),
    Err(missing) => assert_true(list.len(missing) == 2, "both LEIs reported missing"),
  }
}

fn test_missing_isin_reported() -> Result[Unit, Str] {
  let inst := { isin: "", mic: "XNAS" }
  match rts22.from_execution(buy_execution(), inst, full_context()) {
    Ok(_) => fail("missing ISIN should produce an error"),
    Err(missing) => assert_true(list.len(missing) > 0, "missing ISIN reported"),
  }
}

# ---- to_json_report --------------------------------------------
fn test_json_contains_fields() -> Result[Unit, Str] {
  match rts22.from_execution(buy_execution(), instrument(), full_context()) {
    Err(_) => fail("expected a report"),
    Ok(r) => {
      let j := rts22.to_json_report(r)
      assert_true(str.contains(j, "\"instrument_isin\":\"US5949181045\"") and str.contains(j, "\"side\":\"BUYI\"") and str.contains(j, "\"price\":\"125.50\""), "json carries mapped fields")
    },
  }
}

fn suite() -> List[Result[Unit, Str]] {
  [test_from_execution_ok(), test_side_sell_maps(), test_missing_leis_reported(), test_missing_isin_reported(), test_json_contains_fields()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

