# tests for src/reporting/finra_cat.lex

import "std.list" as list

import "std.str" as str

import "../src/reporting/finra_cat" as cat

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

fn ctx() -> cat.OrderContext {
  { cat_order_id: "CAT-1", firm_id: "FIRM01", reporter_imid: "FIRM01", symbol: "MSFT", side: "B", order_type: "LMT" }
}

# A nanosecond timestamp large enough to lose precision if stringified
# carelessly or coerced to float.
fn ns() -> Int {
  1780000000123456789
}

# ---- lifecycle → CAT event mapping ------------------------------
fn test_submit_maps_to_new_order() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnSubmit({ qty: 100, timestamp_ns: ns() }))
  match e {
    NewOrder(o) => assert_true(o.qty == 100 and o.symbol == "MSFT" and o.timestamp_ns == ns(), "new order fields + ns timestamp"),
    RouteOrder(_) => fail("expected NewOrder"),
    Fill(_) => fail("expected NewOrder"),
    Cancel(_) => fail("expected NewOrder"),
    Modify(_) => fail("expected NewOrder"),
    Expire(_) => fail("expected NewOrder"),
    PartialFill(_) => fail("expected NewOrder"),
  }
}

fn test_route_maps_to_route_order() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnRoute({ route_dest: "XNAS", qty: 60, timestamp_ns: ns() }))
  match e {
    RouteOrder(r) => assert_true(r.route_dest == "XNAS" and r.qty == 60, "route fields"),
    NewOrder(_) => fail("expected RouteOrder"),
    Fill(_) => fail("expected RouteOrder"),
    Cancel(_) => fail("expected RouteOrder"),
    Modify(_) => fail("expected RouteOrder"),
    Expire(_) => fail("expected RouteOrder"),
    PartialFill(_) => fail("expected RouteOrder"),
  }
}

fn test_fill_maps_to_fill() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: ns() }))
  match e {
    Fill(f) => assert_true(f.fill_qty == 100 and f.fill_price == "125.50", "fill fields"),
    NewOrder(_) => fail("expected Fill"),
    RouteOrder(_) => fail("expected Fill"),
    Cancel(_) => fail("expected Fill"),
    Modify(_) => fail("expected Fill"),
    Expire(_) => fail("expected Fill"),
    PartialFill(_) => fail("expected Fill"),
  }
}

fn test_cancel_maps_to_cancel() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnCancel({ cancel_qty: 40, timestamp_ns: ns() }))
  match e {
    Cancel(c) => assert_true(c.cancel_qty == 40, "cancel fields"),
    NewOrder(_) => fail("expected Cancel"),
    RouteOrder(_) => fail("expected Cancel"),
    Fill(_) => fail("expected Cancel"),
    Modify(_) => fail("expected Cancel"),
    Expire(_) => fail("expected Cancel"),
    PartialFill(_) => fail("expected Cancel"),
  }
}

# ---- JSON serialization -----------------------------------------
# The nanosecond timestamp must serialize as an unquoted JSON number,
# preserving all 19 digits.
fn test_json_preserves_ns_precision() -> Result[Unit, Str] {
  let j := cat.to_json_report(cat.from_lifecycle(ctx(), OnSubmit({ qty: 100, timestamp_ns: ns() })))
  assert_true(str.contains(j, "\"timestampNS\":1780000000123456789") and str.contains(j, "\"qty\":100"), "ns timestamp + qty are JSON numbers")
}

fn test_json_has_event_type() -> Result[Unit, Str] {
  let j := cat.to_json_report(cat.from_lifecycle(ctx(), OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: ns() })))
  assert_true(str.contains(j, "\"eventType\":\"MEOT\"") and str.contains(j, "\"fillPrice\":\"125.50\""), "fill event json")
}

# ---- event_type codes -------------------------------------------
fn test_meno_event_type() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnSubmit({ qty: 100, timestamp_ns: ns() }))
  assert_true(cat.event_type(e) == "MENO", "OnSubmit → MENO")
}

fn test_meor_event_type() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnRoute({ route_dest: "XNAS", qty: 100, timestamp_ns: ns() }))
  assert_true(cat.event_type(e) == "MEOR", "OnRoute → MEOR")
}

fn test_meot_event_type() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnFill({ fill_qty: 100, fill_price: "125.50", timestamp_ns: ns() }))
  assert_true(cat.event_type(e) == "MEOT", "OnFill → MEOT")
}

fn test_meod_event_type() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnModify({ new_qty: 80, new_price: "124.00", timestamp_ns: ns() }))
  assert_true(cat.event_type(e) == "MEOD", "OnModify → MEOD")
}

fn test_meoe_event_type() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnExpire({ reason: "expired", timestamp_ns: ns() }))
  assert_true(cat.event_type(e) == "MEOE", "OnExpire → MEOE")
}

fn test_partial_fill_event_type() -> Result[Unit, Str] {
  let e := cat.from_lifecycle(ctx(), OnPartialFill({ fill_qty: 40, fill_price: "125.50", leaves_qty: 60, timestamp_ns: ns() }))
  assert_true(cat.event_type(e) == "MEOT", "OnPartialFill → MEOT")
}

# ---- reporter_imid in JSON output -------------------------------
fn test_reporter_imid_in_json() -> Result[Unit, Str] {
  let j := cat.to_json_report(cat.from_lifecycle(ctx(), OnSubmit({ qty: 100, timestamp_ns: ns() })))
  assert_true(str.contains(j, "\"reporterIMID\":\"FIRM01\""), "reporterIMID appears in JSON")
}

# ---- new event JSON content -------------------------------------
fn test_meod_new_price_in_json() -> Result[Unit, Str] {
  let j := cat.to_json_report(cat.from_lifecycle(ctx(), OnModify({ new_qty: 80, new_price: "124.00", timestamp_ns: ns() })))
  assert_true(str.contains(j, "\"eventType\":\"MEOD\"") and str.contains(j, "\"newPrice\":\"124.00\""), "MEOD JSON contains new_price")
}

fn test_meoe_reason_in_json() -> Result[Unit, Str] {
  let j := cat.to_json_report(cat.from_lifecycle(ctx(), OnExpire({ reason: "customer_cancel", timestamp_ns: ns() })))
  assert_true(str.contains(j, "\"eventType\":\"MEOE\"") and str.contains(j, "\"reason\":\"customer_cancel\""), "MEOE JSON contains reason")
}

fn test_partial_fill_leaves_qty_in_json() -> Result[Unit, Str] {
  let j := cat.to_json_report(cat.from_lifecycle(ctx(), OnPartialFill({ fill_qty: 40, fill_price: "125.50", leaves_qty: 60, timestamp_ns: ns() })))
  assert_true(str.contains(j, "\"eventType\":\"MEOT\"") and str.contains(j, "\"leavesQty\":60"), "partial fill JSON contains leavesQty")
}

fn suite() -> List[Result[Unit, Str]] {
  [test_submit_maps_to_new_order(), test_route_maps_to_route_order(), test_fill_maps_to_fill(), test_cancel_maps_to_cancel(), test_json_preserves_ns_precision(), test_json_has_event_type(), test_meno_event_type(), test_meor_event_type(), test_meot_event_type(), test_meod_event_type(), test_meoe_event_type(), test_partial_fill_event_type(), test_reporter_imid_in_json(), test_meod_new_price_in_json(), test_meoe_reason_in_json(), test_partial_fill_leaves_qty_in_json()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

