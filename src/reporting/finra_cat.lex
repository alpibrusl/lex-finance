# lex-finance — FINRA CAT (Consolidated Audit Trail) event reporting
#                (core subset)
#
# Typed CAT lifecycle events and their FINRA-style JSON serialization.
#
# ┌─ SCOPE & VERIFICATION ───────────────────────────────────────────┐
# │ This module covers only the CORE event/field subset enumerated in │
# │ the tracking issue. The FINRA CAT NMS/Industry-Member technical    │
# │ specifications (catnmsplan.com) define many more event types and   │
# │ fields with precise names and formats, which have NOT been         │
# │ verified against the primary specification. Do not treat this as a │
# │ compliant CAT submission and do not close the issue until the      │
# │ field mapping is reviewed against the spec.                        │
# └───────────────────────────────────────────────────────────────────┘
#
# Timestamps are nanoseconds since the Unix epoch carried as `Int`
# (per the issue: Int, not Str) and serialized as a JSON number so the
# nanosecond precision is preserved exactly.
#
# `from_lifecycle` maps a local order-lifecycle event to its CAT event,
# demonstrating "every lifecycle transition produces a CAT event". It
# uses a self-contained input rather than importing lex-trade's
# Order/OrderEvent, to keep lex-finance free of lex-trade's transitive
# dependencies; wiring to lex-trade types is a follow-up.
#
# Effects: none.

import "std.str" as str

import "std.int" as int

# ---- CAT event records ------------------------------------------
type CatOrderEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, symbol :: Str, side :: Str, qty :: Int, order_type :: Str, timestamp_ns :: Int }

type CatRouteEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, route_dest :: Str, qty :: Int, timestamp_ns :: Int }

type CatFillEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, fill_qty :: Int, fill_price :: Str, timestamp_ns :: Int }

type CatCancelEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, cancel_qty :: Int, timestamp_ns :: Int }

type CatModifyEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, new_qty :: Int, new_price :: Str, timestamp_ns :: Int }

type CatExpireEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, reason :: Str, timestamp_ns :: Int }

type CatPartialFillEvent = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, fill_qty :: Int, fill_price :: Str, leaves_qty :: Int, timestamp_ns :: Int }

type CatEvent = NewOrder(CatOrderEvent) | RouteOrder(CatRouteEvent) | Fill(CatFillEvent) | Cancel(CatCancelEvent) | Modify(CatModifyEvent) | Expire(CatExpireEvent) | PartialFill(CatPartialFillEvent)

type OrderContext = { cat_order_id :: Str, firm_id :: Str, reporter_imid :: Str, symbol :: Str, side :: Str, order_type :: Str }

# A minimal order-lifecycle transition, payload records tagged per kind.
type Submitted = { qty :: Int, timestamp_ns :: Int }

type Routed = { route_dest :: Str, qty :: Int, timestamp_ns :: Int }

type Filled = { fill_qty :: Int, fill_price :: Str, timestamp_ns :: Int }

type Canceled = { cancel_qty :: Int, timestamp_ns :: Int }

type Modified = { new_qty :: Int, new_price :: Str, timestamp_ns :: Int }

type Expired = { reason :: Str, timestamp_ns :: Int }

type PartialFilled = { fill_qty :: Int, fill_price :: Str, leaves_qty :: Int, timestamp_ns :: Int }

type LifecycleEvent = OnSubmit(Submitted) | OnRoute(Routed) | OnFill(Filled) | OnCancel(Canceled) | OnModify(Modified) | OnExpire(Expired) | OnPartialFill(PartialFilled)

fn from_lifecycle(ctx :: OrderContext, event :: LifecycleEvent) -> CatEvent {
  match event {
    OnSubmit(s) => NewOrder({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, symbol: ctx.symbol, side: ctx.side, qty: s.qty, order_type: ctx.order_type, timestamp_ns: s.timestamp_ns }),
    OnRoute(r) => RouteOrder({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, route_dest: r.route_dest, qty: r.qty, timestamp_ns: r.timestamp_ns }),
    OnFill(f) => Fill({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, fill_qty: f.fill_qty, fill_price: f.fill_price, timestamp_ns: f.timestamp_ns }),
    OnCancel(c) => Cancel({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, cancel_qty: c.cancel_qty, timestamp_ns: c.timestamp_ns }),
    OnModify(m) => Modify({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, new_qty: m.new_qty, new_price: m.new_price, timestamp_ns: m.timestamp_ns }),
    OnExpire(x) => Expire({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, reason: x.reason, timestamp_ns: x.timestamp_ns }),
    OnPartialFill(p) => PartialFill({ cat_order_id: ctx.cat_order_id, firm_id: ctx.firm_id, reporter_imid: ctx.reporter_imid, fill_qty: p.fill_qty, fill_price: p.fill_price, leaves_qty: p.leaves_qty, timestamp_ns: p.timestamp_ns }),
  }
}

fn event_type(e :: CatEvent) -> Str {
  match e {
    NewOrder(_) => "MENO",
    RouteOrder(_) => "MEOR",
    Fill(_) => "MEOT",
    Cancel(_) => "MEOC",
    Modify(_) => "MEOD",
    Expire(_) => "MEOE",
    PartialFill(_) => "MEOT",
  }
}

# ---- JSON serialization -----------------------------------------
fn jstr(key :: Str, value :: Str) -> Str {
  str.concat("\"", str.concat(key, str.concat("\":\"", str.concat(value, "\""))))
}

# A numeric JSON field — used for qty and the nanosecond timestamp so
# precision is not lost to string quoting.
fn jnum(key :: Str, value :: Int) -> Str {
  str.concat("\"", str.concat(key, str.concat("\":", int.to_str(value))))
}

fn wrap(fields :: Str) -> Str {
  str.concat("{", str.concat(fields, "}"))
}

# FINRA-style JSON for a CAT event. `eventType` carries the (illustrative)
# CAT event-type code; `timestamp_ns` is a JSON number in nanoseconds.
# `reporterIMID` is the Industry Member ID required by the CAT NMS Plan.
fn to_json_report(e :: CatEvent) -> Str {
  match e {
    NewOrder(o) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", o.cat_order_id), jstr("firmID", o.firm_id), jstr("reporterIMID", o.reporter_imid), jstr("symbol", o.symbol), jstr("side", o.side), jnum("qty", o.qty), jstr("orderType", o.order_type), jnum("timestampNS", o.timestamp_ns)], ",")),
    RouteOrder(r) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", r.cat_order_id), jstr("firmID", r.firm_id), jstr("reporterIMID", r.reporter_imid), jstr("routeDest", r.route_dest), jnum("qty", r.qty), jnum("timestampNS", r.timestamp_ns)], ",")),
    Fill(f) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", f.cat_order_id), jstr("firmID", f.firm_id), jstr("reporterIMID", f.reporter_imid), jnum("fillQty", f.fill_qty), jstr("fillPrice", f.fill_price), jnum("timestampNS", f.timestamp_ns)], ",")),
    Cancel(c) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", c.cat_order_id), jstr("firmID", c.firm_id), jstr("reporterIMID", c.reporter_imid), jnum("cancelQty", c.cancel_qty), jnum("timestampNS", c.timestamp_ns)], ",")),
    Modify(m) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", m.cat_order_id), jstr("firmID", m.firm_id), jstr("reporterIMID", m.reporter_imid), jnum("newQty", m.new_qty), jstr("newPrice", m.new_price), jnum("timestampNS", m.timestamp_ns)], ",")),
    Expire(x) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", x.cat_order_id), jstr("firmID", x.firm_id), jstr("reporterIMID", x.reporter_imid), jstr("reason", x.reason), jnum("timestampNS", x.timestamp_ns)], ",")),
    PartialFill(p) => wrap(str.join([jstr("eventType", event_type(e)), jstr("catOrderID", p.cat_order_id), jstr("firmID", p.firm_id), jstr("reporterIMID", p.reporter_imid), jnum("fillQty", p.fill_qty), jstr("fillPrice", p.fill_price), jnum("leavesQty", p.leaves_qty), jnum("timestampNS", p.timestamp_ns)], ",")),
  }
}

