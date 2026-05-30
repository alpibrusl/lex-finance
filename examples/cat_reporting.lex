# Worked example: generate FINRA CAT events across an order's lifecycle
# and serialize them to JSON (core subset — see the SCOPE note in
# src/reporting/finra_cat.lex).
#
# Run:  lex run examples/cat_reporting.lex demo_new
#       lex run examples/cat_reporting.lex demo_fill

import "../src/reporting/finra_cat" as cat

fn ctx() -> cat.OrderContext {
  { cat_order_id: "CAT-0001", firm_id: "FIRM01", symbol: "MSFT", side: "B", order_type: "LMT" }
}

# New-order event JSON (timestamp is a nanosecond JSON number).
fn demo_new() -> Str {
  cat.to_json_report(cat.from_lifecycle(ctx(), OnSubmit({ qty: 100, timestamp_ns: 1780000000123456789 })))
}

# Fill event JSON.
fn demo_fill() -> Str {
  cat.to_json_report(cat.from_lifecycle(ctx(), OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: 1780000000987654321 })))
}

