# lex-finance — MiFID II RTS 22 transaction reporting (core subset)
#
# Builds a typed transaction report from a FIX ExecutionReport plus the
# reference data an ExecutionReport does not carry, and serializes it to
# JSON.
#
# ┌─ SCOPE & VERIFICATION ───────────────────────────────────────────┐
# │ This module covers only the CORE field subset enumerated in the   │
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

# Data required by RTS 22 that an ExecutionReport does not carry.
type ReportingContext = { transaction_ref_no :: Str, buyer_lei :: Str, seller_lei :: Str, trade_date :: Str, trade_time :: Str }

type TransactionReport = { transaction_ref_no :: Str, trading_venue :: Str, instrument_isin :: Str, buyer_lei :: Str, seller_lei :: Str, price :: Str, quantity :: Str, trade_date :: Str, trade_time :: Str, side :: Str }

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

# ---- Serialization ----------------------------------------------
fn json_field(key :: Str, value :: Str) -> Str {
  str.concat("\"", str.concat(key, str.concat("\":\"", str.concat(value, "\""))))
}

# JSON equivalent of the RTS 22 record (the regulation's submission
# format is ISO 20022 XML; an XML serializer is a follow-up).
fn to_json_report(r :: TransactionReport) -> Str {
  let fields := [json_field("transaction_ref_no", r.transaction_ref_no), json_field("trading_venue", r.trading_venue), json_field("instrument_isin", r.instrument_isin), json_field("buyer_lei", r.buyer_lei), json_field("seller_lei", r.seller_lei), json_field("price", r.price), json_field("quantity", r.quantity), json_field("trade_date", r.trade_date), json_field("trade_time", r.trade_time), json_field("side", r.side)]
  str.concat("{", str.concat(str.join(fields, ","), "}"))
}

