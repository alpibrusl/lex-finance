# Worked example: build a MiFID II RTS 22 transaction report (core
# subset) from a FIX ExecutionReport and serialize it to JSON.
#
# Run:  lex run examples/transaction_report.lex demo
#       lex run examples/transaction_report.lex demo_missing
#
# See the SCOPE & VERIFICATION note in src/reporting/mifid_rts22.lex:
# this is a core-subset scaffold, not a compliant report.

import "std.str" as str

import "lex-fix/src/v44/execution_report" as er

import "../src/reporting/mifid_rts22" as rts22

fn sample_execution() -> er.ExecutionReport {
  { exec_id: "EX-1", order_id: "OID-1", cl_ord_id: "ORD-1", exec_type: ExecFill(()), ord_status: StatusFilled(()), symbol: "MSFT", side: Buy(()), order_qty: "100", cum_qty: "100", leaves_qty: "0", avg_px: "125.50", last_px: "125.50", last_qty: "100", text: "" }
}

fn sample_instrument() -> rts22.Instrument {
  { isin: "US5949181045", mic: "XNAS" }
}

fn sample_context() -> rts22.ReportingContext {
  rts22.reporting_ctx("TXN-0001", "5493001KJTIIGC8Y1R12", "549300ABCDEF12345678", "2026-05-30", "2026-05-30T14:00:00.123456Z")
}

# Successful conversion → JSON string.
fn demo() -> Str {
  match rts22.from_execution(sample_execution(), sample_instrument(), sample_context()) {
    Ok(report) => rts22.to_json_report(report),
    Err(missing) => str.concat("missing fields: ", str.join(missing, ", ")),
  }
}

# Missing reference data → the typed list of missing required fields.
fn demo_missing() -> Str {
  let ctx := rts22.reporting_ctx("TXN-0002", "", "", "2026-05-30", "2026-05-30T14:00:00.123456Z")
  match rts22.from_execution(sample_execution(), sample_instrument(), ctx) {
    Ok(report) => rts22.to_json_report(report),
    Err(missing) => str.concat("missing fields: ", str.join(missing, ", ")),
  }
}

