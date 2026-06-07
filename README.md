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
  ├── Price tolerance (vs. reference price)               — pure, lex-marketdata/mock
  ├── FIX conformance (lex-fix/conformance)               — pure, lex-fix
  │
  ├── Accepted(NewOrderSingle)
  │     ├── log to lex-trail                              — [io], execution provenance
  │     └── route to FIX session layer                   — [exchange], lex-fix
  │
  └── Rejected(List[RejectionReason])
        └── log to lex-trail + surface to agent
```

## Live demo — pre-trade gauntlet

Five orders. Four typed enforcement walls. One paper trail.

[![asciicast](https://asciinema.org/a/HVTVgllKPlkhuSzC.svg)](https://asciinema.org/a/HVTVgllKPlkhuSzC)

```sh
bash examples/pre_trade_gauntlet.sh
```

Five orders run through every layer of the stack in sequence:

| Order | Wall | Blocked by |
|---|---|---|
| ORD-NVDA 600@$500 | Margin gate | Reg-T IM $75k exceeds $50k cap |
| ORD-BAD 5000@$1 | Risk limit | qty 5000 exceeds max 1000 |
| ORD-STOP Stop→NYSE | FIX conformance | NYSE profile: `no_stop_orders` |
| ORD-DARK DirectTo(CBOE) | SOR | CBOE not in available venue list |
| ORD-001 100@$125.50 | **Accepted** | SHA-256 trail · NYSE+NASDAQ sweep · MiFID II XML · FINRA CAT |

## Packages

| Package | Status | Role |
|---|---|---|
| [lex-money](https://github.com/alpibrusl/lex-money) | ✓ live | Exact decimal arithmetic, ISO 4217 currencies |
| [lex-fix](https://github.com/alpibrusl/lex-fix) | ✓ live | FIX 4.4 typed protocol adapter, conformance |
| [lex-trade](https://github.com/alpibrusl/lex-trade) | ✓ live | Pre-trade validation, risk limits, order lifecycle |
| [lex-positions](https://github.com/alpibrusl/lex-positions) | ✓ live | WAAC position book, realized PnL |
| [lex-risk](https://github.com/alpibrusl/lex-risk) | ✓ live | Portfolio Greeks, notional, Reg-T margin |
| [lex-trail](https://github.com/alpibrusl/lex-trail) | ✓ live | Typed execution provenance, deterministic replay |
| [lex-sor](https://github.com/alpibrusl/lex-sor) | ✓ live | Smart order routing — BestPrice, MinCost, Sweep, DirectTo |
| [lex-marketdata](https://github.com/alpibrusl/lex-marketdata) | ✓ live | Quote types, reference data, mock feed for simulation |

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
