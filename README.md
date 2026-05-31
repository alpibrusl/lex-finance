# lex-finance

Agent-native finance software stack for the [Lex language](https://github.com/alpibrusl/lex-lang).

## The central claim

An AI agent generating a trading order cannot reach the exchange transport without passing through a structurally-enforced pre-execution gate. This is not a convention or a runtime check — it is a type-level constraint. The `[exchange]` effect cannot be invoked without the capability; the capability is only granted after the order passes conformance validation and risk checks.

## Architecture

```
Agent emits Order
      │
      ▼
lex-trade / validation.validate
  ├── RiskLimit gates (qty, notional, symbol, side)       — pure, lex-trade
  ├── Position limits (net exposure, wash trade)          — [positions], lex-positions
  ├── Price tolerance (vs. reference price)               — [market_data], lex-marketdata
  ├── FIX conformance (lex-fix/conformance)               — pure, lex-fix
  │
  ├── Accepted(NewOrderSingle)
  │     ├── log to lex-trail                              — [io], execution provenance
  │     └── route to FIX session layer                   — [exchange], lex-fix
  │
  └── Rejected(List[RejectionReason])
        └── log to lex-trail + surface to agent
```

## Live demo — end-to-end

Three guarantees in a single `lex run`: typed rejection, trail provenance, regulatory reporting.

```sh
bash examples/demo.sh
```

```
ORD-BAD  5000 MSFT buy limit  → REJECTED  quantity 5000 exceeds limit of 1000
ORD-001  100 MSFT buy limit   → ACCEPTED
  entry_id  6f0abcc7767412af984485b356f3adcac187ae81a7e988e681c9e6bf54b610c1

MiFID II RTS 22:  {"transaction_ref_no":"TXN-0001","trading_venue":"XNAS",...}
FINRA CAT:  MENO → MEOR → MEOT  (nanosecond timestamps as JSON numbers)
```

## Packages

| Package | Status | Role |
|---|---|---|
| [lex-money](https://github.com/alpibrusl/lex-money) | ✓ live | Exact decimal arithmetic, ISO 4217 currencies |
| [lex-fix](https://github.com/alpibrusl/lex-fix) | ✓ live | FIX 4.4 typed protocol adapter, conformance |
| [lex-trade](https://github.com/alpibrusl/lex-trade) | ✓ live | Pre-trade validation, risk limits, order lifecycle |
| [lex-positions](https://github.com/alpibrusl/lex-positions) | ✓ live | WAAC position book, realized PnL |
| [lex-risk](https://github.com/alpibrusl/lex-risk) | ✓ live | Portfolio Greeks, notional, Reg-T margin |
| [lex-trail](https://github.com/alpibrusl/lex-trail) | ✓ live | Typed execution provenance, deterministic replay |
| lex-marketdata | planned | Market data effect, reference prices |

## Roadmap

See [GitHub Issues](https://github.com/alpibrusl/lex-finance/issues) organized by phase label.

## Design principles

Built on the [agent-native framework](https://github.com/alpibrusl/agent-native):
- **P2** — effects as types: "touches the market" is a gated capability
- **P3** — errors as values: every rejection has a typed reason
- **P4** — determinism: pure validation is replayable from inputs alone
- **P10** — provenance: logic provenance (lex-vcs) + execution provenance (lex-trail)
- **P12** — typed semantic change: algo changes recorded as operations, not text diffs

## Governance & compliance

How lex's provenance and attestation tooling supports regulatory record-keeping for trading-validation logic. Commands are verified against lex 0.9.7; the regulatory mappings are interpretive — verify against primary sources before relying on them.

- [docs/governance-workflow.md](docs/governance-workflow.md) — typed change records with lex-vcs, mapped to **MiFID II Article 17**.
- [docs/sr11-7-governance.md](docs/sr11-7-governance.md) — model-risk governance mapped to **SR 11-7**.

Both are reproducible from [`examples/governance/`](examples/governance/).

## Regulatory reporting (core subsets — not yet spec-verified)

Typed report builders + JSON serialization. These cover the **core field subsets** of their respective specs; the full field lists have **not** been verified against the primary sources, so they are scaffolding, not compliant reports.

- [`src/reporting/mifid_rts22.lex`](src/reporting/mifid_rts22.lex) — **MiFID II RTS 22** transaction report from a FIX `ExecutionReport` + reference data; `from_execution` returns a typed report or the list of missing required fields. Example: [`examples/transaction_report.lex`](examples/transaction_report.lex).
- [`src/reporting/finra_cat.lex`](src/reporting/finra_cat.lex) — **FINRA CAT** lifecycle events (`NewOrder`/`RouteOrder`/`Fill`/`Cancel`) with nanosecond-precision `Int` timestamps preserved as JSON numbers. Example: [`examples/cat_reporting.lex`](examples/cat_reporting.lex).
