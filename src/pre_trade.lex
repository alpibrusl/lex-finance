# lex-finance — combined margin + validation pre-trade gate
#
# Wires lex-risk's margin.pre_trade_check in front of lex-trade's
# vio.validate_log_and_record. A margin breach short-circuits as
# Rejected([MarginLimitBreached(reason)]) before the order is
# structurally validated or written to the trail.
#
# Callers:
#   - Pass `margin_gate(mark_price)` to enforce Reg-T margin.
#   - Pass `default_margin_gate()` (mark_price = None) to skip it —
#     identical to calling vio.validate_log_and_record directly.
#
# Effects: [sql, time]

import "lex-money/src/decimal" as d

import "lex-trade/src/order" as order
import "lex-trade/src/limit" as limit
import "lex-trade/src/validation" as v
import "lex-trade/src/validation_io" as vio
import "lex-trade/src/rejection" as rejection
import "lex-trade/src/price_check" as pc

import "lex-risk/src/margin" as margin

import "lex-trail/src/log" as trail_log

# ---- Types ----------------------------------------------------------

type MarginGate = {
  mark_price :: Option[d.Decimal],  # None = skip margin check
  config     :: margin.MarginConfig,
}

fn default_margin_gate() -> MarginGate {
  { mark_price: None, config: margin.default_margin_config() }
}

fn margin_gate(mark_price :: d.Decimal) -> MarginGate {
  { mark_price: Some(mark_price), config: margin.default_margin_config() }
}

fn margin_gate_with_config(mark_price :: d.Decimal, cfg :: margin.MarginConfig) -> MarginGate {
  { mark_price: Some(mark_price), config: cfg }
}

# ---- Gate -----------------------------------------------------------

fn margin_rejected(reason :: Str) -> vio.LogAndRecord {
  { result: Rejected([MarginLimitBreached(reason)]), entry_id: "" }
}

# Run margin check (if mark_price is Some), then delegate to the full
# lex-trade validation + trail logging pipeline.
fn validate_with_margin(
  o        :: order.Order,
  lim      :: limit.RiskLimit,
  gate     :: MarginGate,
  ref_price :: Option[d.Decimal],
  tolerance :: pc.PriceTolerance,
  sender   :: Str,
  target   :: Str,
  log      :: trail_log.Log,
  algo_sig_id :: Str,
) -> [sql, time] vio.LogAndRecord {
  match gate.mark_price {
    None => vio.validate_log_and_record(o, lim, ref_price, tolerance, sender, target, log, algo_sig_id),
    Some(mark) => match margin.pre_trade_check(o.quantity, mark, gate.config) {
      Err(reason) => margin_rejected(reason),
      Ok(_) => vio.validate_log_and_record(o, lim, ref_price, tolerance, sender, target, log, algo_sig_id),
    },
  }
}
