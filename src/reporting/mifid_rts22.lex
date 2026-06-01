# lex-finance — MiFID II RTS 22 transaction reporting (expanded subset)
#
# Builds a typed transaction report from a FIX ExecutionReport plus the
# reference data an ExecutionReport does not carry, and serializes to
# JSON and ISO 20022 XML.
#
# ┌─ SCOPE & VERIFICATION ───────────────────────────────────────────┐
# │ This module covers an expanded field subset enumerated in the     │
# │ tracking issue. RTS 22 (Commission Delegated Regulation (EU)       │
# │ 2017/590) defines ~65 fields. The full field list and the exact   │
# │ field names/codes have NOT been verified against the primary ESMA  │
# │ source. Do not treat this as a compliant report and do not close   │
# │ the issue until the mapping is reviewed against the regulation.    │
# └───────────────────────────────────────────────────────────────────┘
#
# Field provenance (which input feeds which report field):
#   transaction_ref_no  <- reporting context (firm-assigned, unique)
#   trading_venue       <- instrument.mic        (ISO 10383 MIC)
#   instrument_isin     <- instrument.isin       (ISO 6166 ISIN)
#   buyer_lei           <- reporting context     (ISO 17442 LEI)
#   seller_lei          <- reporting context     (ISO 17442 LEI)
#   price               <- ExecutionReport.last_px
#   quantity            <- ExecutionReport.last_qty
#   trade_date          <- reporting context     (UTC, YYYY-MM-DD)
#   trade_time          <- reporting context     (UTC, microsecond)
#   side                <- ExecutionReport.side   (BUYI / SELL)
#   trading_capacity    <- reporting context     (DEAL / AOTC / MTCH)
#   transaction_type    <- reporting context     (NEWT / CANC / CORR)
#   algo_id             <- reporting context     (optional algo identifier)
#   waiver_types        <- reporting context     (list of waiver codes)
#   otc_flags           <- reporting context     (list of OTC post-trade flags)
#
# An ExecutionReport carries neither counterparty LEIs nor an execution
# timestamp, so those arrive via `ReportingContext`. This is why the
# conversion takes a context argument beyond the issue's sketched
# (execution, instrument) signature.
#
# Monetary values are kept as wire-format strings (as ExecutionReport
# carries them); a lex-money Decimal typing is a follow-up, mirroring
# lex-trade's existing string-money convention.
#
# Effects: none.

import "std.str" as str

import "std.list" as list

import "lex-fix/src/v44/execution_report" as er

import "lex-fix/src/v44/enums" as en

# Instrument reference data (subset of an instrument master / FIRDS).
type Instrument = { isin :: Str, mic :: Str }

# ---- RTS 22 enum types --------------------------------------------------

# RTS 22 Field 29 — Trading capacity of the investment firm.
type TradingCapacity = Principal(Unit) | Agent(Unit) | RisklessPrincipal(Unit)

fn trading_capacity_code(c :: TradingCapacity) -> Str {
  match c {
    Principal(_) => "DEAL",
    Agent(_) => "AOTC",
    RisklessPrincipal(_) => "MTCH",
  }
}

# RTS 22 — Transaction type (new, cancel, correction).
type TransactionType = NewTransaction(Unit) | CancelTxn(Unit) | Correction(Unit)

fn transaction_type_code(t :: TransactionType) -> Str {
  match t {
    NewTransaction(_) => "NEWT",
    CancelTxn(_) => "CANC",
    Correction(_) => "CORR",
  }
}

# RTS 22 Field 58 — Waiver type applicable to the transaction.
type WaiverType = LiquidityWaiver(Unit) | NegotiatedTrade(Unit) | OrderManagement(Unit) | ReferencePriceTrade(Unit)

fn waiver_code(w :: WaiverType) -> Str {
  match w {
    LiquidityWaiver(_) => "LIQT",
    NegotiatedTrade(_) => "NLIQ",
    OrderManagement(_) => "OILQ",
    ReferencePriceTrade(_) => "RFPT",
  }
}

# RTS 22 Field 59 — OTC post-trade flag.
type OtcFlag = Benchmark(Unit) | Reference(Unit) | IlliquidInstrument(Unit)

fn otc_flag_code(f :: OtcFlag) -> Str {
  match f {
    Benchmark(_) => "BENC",
    Reference(_) => "RFPR",
    IlliquidInstrument(_) => "ILQD",
  }
}

# ---- Context and report types -------------------------------------------

# Data required by RTS 22 that an ExecutionReport does not carry.
# Fields trading_capacity, transaction_type, algo_id, waiver_types, and
# otc_flags were added in the expanded subset; use reporting_ctx for a
# constructor with defaults, or reporting_ctx_full for full control.
type ReportingContext = { transaction_ref_no :: Str, buyer_lei :: Str, seller_lei :: Str, trade_date :: Str, trade_time :: Str, trading_capacity :: TradingCapacity, transaction_type :: TransactionType, algo_id :: Option[Str], waiver_types :: List[WaiverType], otc_flags :: List[OtcFlag] }

# Convenience constructor — defaults trading_capacity to Principal, transaction_type
# to NewTransaction, algo_id to None, and empty waiver/OTC lists.
fn reporting_ctx(txn_ref :: Str, buyer_lei :: Str, seller_lei :: Str, trade_date :: Str, trade_time :: Str) -> ReportingContext {
  { transaction_ref_no: txn_ref, buyer_lei: buyer_lei, seller_lei: seller_lei, trade_date: trade_date, trade_time: trade_time, trading_capacity: Principal(()), transaction_type: NewTransaction(()), algo_id: None, waiver_types: [], otc_flags: [] }
}

# Full constructor — explicit control over all RTS 22 context fields.
fn reporting_ctx_full(txn_ref :: Str, buyer_lei :: Str, seller_lei :: Str, trade_date :: Str, trade_time :: Str, trading_capacity :: TradingCapacity, transaction_type :: TransactionType, algo_id :: Option[Str], waiver_types :: List[WaiverType], otc_flags :: List[OtcFlag]) -> ReportingContext {
  { transaction_ref_no: txn_ref, buyer_lei: buyer_lei, seller_lei: seller_lei, trade_date: trade_date, trade_time: trade_time, trading_capacity: trading_capacity, transaction_type: transaction_type, algo_id: algo_id, waiver_types: waiver_types, otc_flags: otc_flags }
}

# Core transaction report (legacy — kept for backward compatibility).
type TransactionReport = { transaction_ref_no :: Str, trading_venue :: Str, instrument_isin :: Str, buyer_lei :: Str, seller_lei :: Str, price :: Str, quantity :: Str, trade_date :: Str, trade_time :: Str, side :: Str }

# Expanded RTS 22 report including the new field subset.
type Rts22Report = { transaction_ref_no :: Str, trading_venue :: Str, instrument_isin :: Str, buyer_lei :: Str, seller_lei :: Str, price :: Str, quantity :: Str, trade_date :: Str, trade_time :: Str, side :: Str, trading_capacity :: Str, transaction_type :: Str, algo_id :: Option[Str], waiver_types :: List[Str], otc_flags :: List[Str] }

fn side_code(s :: en.Side) -> Str {
  match s {
    Buy(_) => "BUYI",
    Sell(_) => "SELL",
  }
}

# Accumulate the names of required fields that are empty.
fn check_present(value :: Str, field_name :: Str, missing :: List[Str]) -> List[Str] {
  if str.is_empty(value) {
    list.concat(missing, [field_name])
  } else {
    missing
  }
}

fn missing_fields(r :: TransactionReport) -> List[Str] {
  let m0 := check_present(r.transaction_ref_no, "transaction_ref_no", [])
  let m1 := check_present(r.trading_venue, "trading_venue", m0)
  let m2 := check_present(r.instrument_isin, "instrument_isin", m1)
  let m3 := check_present(r.buyer_lei, "buyer_lei", m2)
  let m4 := check_present(r.seller_lei, "seller_lei", m3)
  let m5 := check_present(r.price, "price", m4)
  let m6 := check_present(r.quantity, "quantity", m5)
  let m7 := check_present(r.trade_date, "trade_date", m6)
  let m8 := check_present(r.trade_time, "trade_time", m7)
  m8
}

fn missing_rts22_fields(r :: Rts22Report) -> List[Str] {
  let m0 := check_present(r.transaction_ref_no, "transaction_ref_no", [])
  let m1 := check_present(r.trading_venue, "trading_venue", m0)
  let m2 := check_present(r.instrument_isin, "instrument_isin", m1)
  let m3 := check_present(r.buyer_lei, "buyer_lei", m2)
  let m4 := check_present(r.seller_lei, "seller_lei", m3)
  let m5 := check_present(r.price, "price", m4)
  let m6 := check_present(r.quantity, "quantity", m5)
  let m7 := check_present(r.trade_date, "trade_date", m6)
  let m8 := check_present(r.trade_time, "trade_time", m7)
  m8
}

# Build a transaction report from an execution, its instrument reference
# data, and the reporting context. Returns the typed report, or the list
# of required fields that are missing.
fn from_execution(report :: er.ExecutionReport, instrument :: Instrument, ctx :: ReportingContext) -> Result[TransactionReport, List[Str]] {
  let tr := { transaction_ref_no: ctx.transaction_ref_no, trading_venue: instrument.mic, instrument_isin: instrument.isin, buyer_lei: ctx.buyer_lei, seller_lei: ctx.seller_lei, price: report.last_px, quantity: report.last_qty, trade_date: ctx.trade_date, trade_time: ctx.trade_time, side: side_code(report.side) }
  let missing := missing_fields(tr)
  if list.is_empty(missing) {
    Ok(tr)
  } else {
    Err(missing)
  }
}

# Build an expanded Rts22Report from an execution, instrument, and full context.
fn from_execution_full(report :: er.ExecutionReport, instrument :: Instrument, ctx :: ReportingContext) -> Result[Rts22Report, List[Str]] {
  let waiver_codes := list.map(ctx.waiver_types, waiver_code)
  let otc_codes := list.map(ctx.otc_flags, otc_flag_code)
  let tr := { transaction_ref_no: ctx.transaction_ref_no, trading_venue: instrument.mic, instrument_isin: instrument.isin, buyer_lei: ctx.buyer_lei, seller_lei: ctx.seller_lei, price: report.last_px, quantity: report.last_qty, trade_date: ctx.trade_date, trade_time: ctx.trade_time, side: side_code(report.side), trading_capacity: trading_capacity_code(ctx.trading_capacity), transaction_type: transaction_type_code(ctx.transaction_type), algo_id: ctx.algo_id, waiver_types: waiver_codes, otc_flags: otc_codes }
  let missing := missing_rts22_fields(tr)
  if list.is_empty(missing) {
    Ok(tr)
  } else {
    Err(missing)
  }
}

# ---- Serialization ----------------------------------------------
fn json_field(key :: Str, value :: Str) -> Str {
  str.concat("\"", str.concat(key, str.concat("\":\"", str.concat(value, "\""))))
}

# JSON equivalent of the RTS 22 record (the regulation's submission
# format is ISO 20022 XML; see to_iso20022_xml below).
fn to_json_report(r :: TransactionReport) -> Str {
  let fields := [json_field("transaction_ref_no", r.transaction_ref_no), json_field("trading_venue", r.trading_venue), json_field("instrument_isin", r.instrument_isin), json_field("buyer_lei", r.buyer_lei), json_field("seller_lei", r.seller_lei), json_field("price", r.price), json_field("quantity", r.quantity), json_field("trade_date", r.trade_date), json_field("trade_time", r.trade_time), json_field("side", r.side)]
  str.concat("{", str.concat(str.join(fields, ","), "}"))
}

# JSON serializer for the expanded Rts22Report.
fn to_json_rts22(r :: Rts22Report) -> Str {
  let algo := match r.algo_id {
    None => json_field("algo_id", ""),
    Some(id) => json_field("algo_id", id),
  }
  let fields := [json_field("transaction_ref_no", r.transaction_ref_no), json_field("trading_venue", r.trading_venue), json_field("instrument_isin", r.instrument_isin), json_field("buyer_lei", r.buyer_lei), json_field("seller_lei", r.seller_lei), json_field("price", r.price), json_field("quantity", r.quantity), json_field("trade_date", r.trade_date), json_field("trade_time", r.trade_time), json_field("side", r.side), json_field("trading_capacity", r.trading_capacity), json_field("transaction_type", r.transaction_type), algo]
  str.concat("{", str.concat(str.join(fields, ","), "}"))
}

# ---- ISO 20022 XML serialization --------------------------------

# Wrap content in an XML element: <tag>content</tag>.
fn xml_tag(tag :: Str, content :: Str) -> Str {
  str.concat("<", str.concat(tag, str.concat(">", str.concat(content, str.concat("</", str.concat(tag, ">"))))))
}

# Serialize an Rts22Report to an ISO 20022-style XML fragment.
# The outer element is <TxRpt> per the ESMA RTS 22 schema conventions.
fn to_iso20022_xml(report :: Rts22Report) -> Str {
  let ref_elem := xml_tag("TxRptRef", xml_tag("Id", report.transaction_ref_no))
  let ntty_elem := xml_tag("NttyRsplblForRpt", xml_tag("LEI", report.buyer_lei))
  let buyr_elem := xml_tag("Buyr", xml_tag("LEI", report.buyer_lei))
  let sellr_elem := xml_tag("Sellr", xml_tag("LEI", report.seller_lei))
  let trade_dt_elem := xml_tag("TradDt", report.trade_date)
  let trade_tm_elem := xml_tag("TradTm", report.trade_time)
  let instrm_elem := xml_tag("FinInstrm", str.concat(xml_tag("ISIN", report.instrument_isin), xml_tag("MIC", report.trading_venue)))
  let qty_elem := xml_tag("Qty", report.quantity)
  let pric_elem := xml_tag("Pric", report.price)
  let cpcty_elem := xml_tag("TradgCpcty", report.trading_capacity)
  let txtp_elem := xml_tag("TxTp", report.transaction_type)
  let body := str.concat(ref_elem, str.concat(ntty_elem, str.concat(buyr_elem, str.concat(sellr_elem, str.concat(trade_dt_elem, str.concat(trade_tm_elem, str.concat(instrm_elem, str.concat(qty_elem, str.concat(pric_elem, str.concat(cpcty_elem, txtp_elem))))))))))
  xml_tag("TxRpt", body)
}
