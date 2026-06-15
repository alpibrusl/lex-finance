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
  rts22.reporting_ctx("TXN-1", "5493001KJTIIGC8Y1R12", "549300ABCDEF12345678", "2026-05-30", "2026-05-30T14:00:00.123456Z")
}

fn full_rts22_report() -> rts22.Rts22Report {
  match rts22.from_execution_full(buy_execution(), instrument(), full_context()) {
    Ok(r) => r,
    Err(_) => { transaction_ref_no: "ERR", trading_venue: "ERR", instrument_isin: "ERR", buyer_lei: "ERR", seller_lei: "ERR", price: "ERR", quantity: "ERR", trade_date: "ERR", trade_time: "ERR", side: "ERR", trading_capacity: "ERR", transaction_type: "ERR", algo_id: None, waiver_types: [], otc_flags: [], asset_class: "ERR", counterparty_sector: "ERR", decision_maker_lei: None, notional_currency: "ERR", order_kind: None, price_currency: "ERR", short_selling_flag: false },
  }
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
  let ctx := rts22.reporting_ctx("TXN-3", "", "", "2026-05-30", "2026-05-30T14:00:00.123456Z")
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

# ---- TradingCapacity --------------------------------------------
fn test_trading_capacity_principal() -> Result[Unit, Str] {
  assert_true(rts22.trading_capacity_code(Principal(())) == "DEAL", "Principal maps to DEAL")
}

fn test_trading_capacity_agent() -> Result[Unit, Str] {
  assert_true(rts22.trading_capacity_code(Agent(())) == "AOTC", "Agent maps to AOTC")
}

fn test_trading_capacity_riskless() -> Result[Unit, Str] {
  assert_true(rts22.trading_capacity_code(RisklessPrincipal(())) == "MTCH", "RisklessPrincipal maps to MTCH")
}

# ---- TransactionType --------------------------------------------
fn test_transaction_type_new() -> Result[Unit, Str] {
  assert_true(rts22.transaction_type_code(NewTransaction(())) == "NEWT", "NewTransaction maps to NEWT")
}

fn test_transaction_type_cancel() -> Result[Unit, Str] {
  assert_true(rts22.transaction_type_code(CancelTxn(())) == "CANC", "CancelTxn maps to CANC")
}

fn test_transaction_type_correction() -> Result[Unit, Str] {
  assert_true(rts22.transaction_type_code(Correction(())) == "CORR", "Correction maps to CORR")
}

# ---- WaiverType -------------------------------------------------
fn test_waiver_liquidity() -> Result[Unit, Str] {
  assert_true(rts22.waiver_code(LiquidityWaiver(())) == "LIQT", "LiquidityWaiver maps to LIQT")
}

fn test_waiver_negotiated() -> Result[Unit, Str] {
  assert_true(rts22.waiver_code(NegotiatedTrade(())) == "NLIQ", "NegotiatedTrade maps to NLIQ")
}

# ---- OtcFlag ----------------------------------------------------
fn test_otc_flag_benchmark() -> Result[Unit, Str] {
  assert_true(rts22.otc_flag_code(Benchmark(())) == "BENC", "Benchmark maps to BENC")
}

fn test_otc_flag_illiquid() -> Result[Unit, Str] {
  assert_true(rts22.otc_flag_code(IlliquidInstrument(())) == "ILQD", "IlliquidInstrument maps to ILQD")
}

# ---- reporting_ctx_full -----------------------------------------
fn test_reporting_ctx_full_fields() -> Result[Unit, Str] {
  let ctx := rts22.reporting_ctx_full("TXN-X", "LEI-A", "LEI-B", "2026-05-30", "14:00:00.000Z", RisklessPrincipal(()), Correction(()), Some("ALGO-42"), [LiquidityWaiver(())], [Benchmark(())], EquityCash(()), "EUR", "EUR", InvestmentFirm(()), Some(LimitRts(())), None, false)
  assert_true(ctx.transaction_ref_no == "TXN-X" and ctx.buyer_lei == "LEI-A" and ctx.algo_id == Some("ALGO-42"), "reporting_ctx_full round-trip")
}

# ---- ISO 20022 XML serialization --------------------------------
fn test_xml_contains_isin() -> Result[Unit, Str] {
  let xml := rts22.to_iso20022_xml(full_rts22_report())
  assert_true(str.contains(xml, "US5949181045"), "XML contains ISIN")
}

fn test_xml_contains_trading_capacity() -> Result[Unit, Str] {
  let xml := rts22.to_iso20022_xml(full_rts22_report())
  assert_true(str.contains(xml, "DEAL"), "XML contains trading capacity code DEAL")
}

fn test_xml_contains_transaction_type() -> Result[Unit, Str] {
  let xml := rts22.to_iso20022_xml(full_rts22_report())
  assert_true(str.contains(xml, "NEWT"), "XML contains transaction type code NEWT")
}

fn test_xml_is_wrapped_in_txrpt() -> Result[Unit, Str] {
  let xml := rts22.to_iso20022_xml(full_rts22_report())
  assert_true(str.contains(xml, "<TxRpt>"), "XML is wrapped in TxRpt element")
}

fn test_xml_contains_buyer_lei() -> Result[Unit, Str] {
  let xml := rts22.to_iso20022_xml(full_rts22_report())
  assert_true(str.contains(xml, "5493001KJTIIGC8Y1R12"), "XML contains buyer LEI")
}

fn test_xml_contains_mic() -> Result[Unit, Str] {
  let xml := rts22.to_iso20022_xml(full_rts22_report())
  assert_true(str.contains(xml, "<MIC>XNAS</MIC>"), "XML contains trading venue MIC")
}

fn suite() -> List[Result[Unit, Str]] {
  [test_from_execution_ok(), test_side_sell_maps(), test_missing_leis_reported(), test_missing_isin_reported(), test_json_contains_fields(), test_trading_capacity_principal(), test_trading_capacity_agent(), test_trading_capacity_riskless(), test_transaction_type_new(), test_transaction_type_cancel(), test_transaction_type_correction(), test_waiver_liquidity(), test_waiver_negotiated(), test_otc_flag_benchmark(), test_otc_flag_illiquid(), test_reporting_ctx_full_fields(), test_xml_contains_isin(), test_xml_contains_trading_capacity(), test_xml_contains_transaction_type(), test_xml_is_wrapped_in_txrpt(), test_xml_contains_buyer_lei(), test_xml_contains_mic()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

