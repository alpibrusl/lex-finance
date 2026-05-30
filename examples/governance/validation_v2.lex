# Candidate revision of validation.lex used to demonstrate AST-native
# change records (lex ast-diff). The only change is tightening the
# quantity ceiling from `>` to `>=` — a one-character edit that changes
# the decision boundary, exactly the kind of algorithmic-trading change
# MiFID II Article 17 expects a firm to record.
#
# Effects: none.

type Order = { symbol :: Str, qty :: Int, side :: Str }

type RiskLimit = { max_qty :: Int }

fn validate(order :: Order, limit :: RiskLimit) -> Result[Order, Str] {
  if order.qty <= 0 {
    Err("qty must be positive")
  } else {
    if order.qty >= limit.max_qty {
      Err("qty exceeds max")
    } else {
      Ok(order)
    }
  }
}

