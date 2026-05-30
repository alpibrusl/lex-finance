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

## Packages

| Package | Status | Role |
|---|---|---|
| [lex-money](https://github.com/alpibrusl/lex-money) | ✓ live | Exact decimal arithmetic, ISO 4217 currencies |
| [lex-fix](https://github.com/alpibrusl/lex-fix) | ✓ live | FIX 4.4 typed protocol adapter, conformance |
| [lex-trade](https://github.com/alpibrusl/lex-trade) | ✓ live | Pre-trade validation, risk limits, order lifecycle |
| lex-positions | planned | Stateful position book as `[positions]` effect |
| lex-marketdata | planned | Market data effect, reference prices |
| [lex-trail](https://github.com/alpibrusl/lex-trail) | exists | Typed execution provenance (integration pending) |
| [lex-lang / std.decimal](https://github.com/alpibrusl/lex-lang) | PR open | Exact decimal in Core (issue #574) |

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
