# Representative pre-trade validation logic for the governance docs.
#
# This is a self-contained stand-in for lex-trade's `validation.validate`
# so the commands in docs/governance-workflow.md and
# docs/sr11-7-governance.md are reproducible from the lex-finance root.
# It uses only Core types (no package dependencies).
#
# Effects: none — pure pre-execution gate.

type Order = { symbol :: Str, qty :: Int, side :: Str }

type RiskLimit = { max_qty :: Int }

fn validate(order :: Order, limit :: RiskLimit) -> Result[Order, Str] {
  if order.qty <= 0 {
    Err("qty must be positive")
  } else {
    if order.qty > limit.max_qty {
      Err("qty exceeds max")
    } else {
      Ok(order)
    }
  }
}

