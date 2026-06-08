# lex-finance

The complete pre-trade enforcement pipeline for Lex, plus regulatory reporting scaffolding.

Assembles every layer of the stack — margin, position limits, price tolerance, FIX conformance, smart order routing — into a single typed entry point. An agent's order either clears all layers and gets a `NewOrderSingle` ready for the exchange, or receives a typed list of every reason it was rejected.

---

## The five walls

```
Agent Order
    │
    ▼
pre_trade.validate_with_margin
  ├── 1. Margin gate       lex-risk/margin.pre_trade_check
  ├── 2. Position limit    lex-positions/exposure.within_notional
  ├── 3. Price tolerance   lex-marketdata/mock.get_reference_price
  ├── 4. FIX conformance   lex-fix/conformance.validate_new_order
  └── 5. Venue check       lex-sor/router.route_order
      │
      ├── Accepted(NewOrderSingle)  →  exchange transport
      └── Rejected(List[RejectionReason])  →  agent
```

---

## Usage

```lex
import "lex-finance/src/pre_trade" as pre_trade

let gate := pre_trade.default_margin_gate()   # 25% Reg-T, $50M cap

match pre_trade.validate_with_margin(gate, order, limits, available_venues, db) {
  Accepted(nos) => # ready for exchange
  Rejected(reasons) => # every failure named
}
```

Run the gauntlet demo to see all five walls in action:

```sh
bash examples/pre_trade_gauntlet.sh
```

---

## Regulatory reporting

**Note: these are field scaffolding, not spec-verified compliant reports.** Full spec completion is tracked in [issue #16](https://github.com/alpibrusl/lex-finance/issues/16) (MiFID II RTS 22) and [issue #17](https://github.com/alpibrusl/lex-finance/issues/17) (FINRA CAT).

- **`src/reporting/mifid_rts22.lex`** — MiFID II RTS 22 transaction report builder from `ExecutionReport` + reference data. Core fields only; full field list not yet verified against primary text.
- **`src/reporting/finra_cat.lex`** — FINRA CAT lifecycle events (`NewOrder`/`RouteOrder`/`Fill`/`Cancel`) with nanosecond-precision timestamps.

The lex-trail integration means every report has cryptographic provenance — the hash chain is independently verifiable. Once the field coverage is completed, this is directly usable for regulatory submission.

---

## In the stack

```
lex-money · lex-fix · lex-positions · lex-risk · lex-trade · lex-sor · lex-marketdata
    ↓
lex-finance  ←  full pipeline integration
    ↓
lex-oms
```

---

## Install

```toml
[dependencies]
"lex-finance" = { git = "https://github.com/alpibrusl/lex-finance" }
```
