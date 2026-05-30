# SR 11-7 model-risk governance for trading-validation logic

How the Federal Reserve / OCC model-risk-management framework
(**SR 11-7** / OCC Bulletin 2011-12) maps onto lex's provenance and
attestation tooling, for AI-generated trading-validation logic such as
`lex-trade`'s `validation.validate`.

> **Scope & disclaimer.** The `lex` commands referenced here were
> verified against **lex 0.9.7**; the demonstrated session lives in
> [governance-workflow.md](./governance-workflow.md). The mapping to
> SR 11-7 is an *interpretive illustration* of how the tooling supports
> the guidance — it is not legal or compliance advice and has not been
> reviewed by a model-risk function. **Verify every requirement against
> the primary source** — Board of Governors of the Federal Reserve
> System / OCC, *Supervisory Guidance on Model Risk Management*,
> SR 11-7 (April 4, 2011) — before relying on it.

SR 11-7 frames model risk management around three elements: (1) robust
model **development, implementation, and use**; (2) sound model
**validation** with *effective challenge* by independent parties; and
(3) **governance, policies, and controls**, including a model inventory
and documentation. The sections below map each to a concrete lex
mechanism.

---

## 1. Model inventory

> *SR 11-7 expects firms to maintain a comprehensive inventory of models
> in use.*

Every top-level definition is a content-addressed stage. `lex hash`
enumerates the inventory with a stable id per function; `lex audit`
adds each function's signature and declared effects:

```
$ lex hash examples/governance/validation.lex
validate  canonical_ast=2f1560dd…  stage_id=6e81423b9830211a9110cd4bba0394bd6fadca5bbacb3a5d43bf5111d62c0cc4
$ lex audit examples/governance/validation.lex --json
{ "summary": { "pure": 1 },
  "hits": [ { "name": "validate",
              "signature": "fn validate(order :: Order, limit :: RiskLimit) -> Result[Order, Str]",
              "effects": [] } ] }
```

The `stage_id` is the inventory key: it is identical across formatting
or comment changes and changes precisely when the logic changes.

## 2. Documentation & conceptual soundness

> *Validation should evaluate conceptual soundness, with supporting
> documentation of model design and intended use.*

- The **canonical AST** in the store (`lex store get <stage_id>`) is an
  exact, machine-readable record of the model's logic — documentation
  that cannot drift from the implementation because it *is* the
  implementation.
- The **effect signature** is design documentation enforced by the type
  system: `validate` is pure (`effects: []`), so it cannot read a clock,
  hit the network, or touch the exchange. The `[exchange]` capability is
  granted only after validation passes — the pre-execution gate is a
  type-level constraint, not a convention (P2).
- **Worked examples** attached to a function (the `examples` attestation
  kind) document intended use with executable input→output pairs.

## 3. Independent validation & effective challenge

> *SR 11-7's core control is effective challenge: critical analysis by
> objective, independent parties.*

lex records validation as a typed **attestation graph** on each stage.
Publishing records an automated `TypeCheck`:

```
$ lex stage 6e81423b9830211a9110cd4bba0394bd6fadca5bbacb3a5d43bf5111d62c0cc4 --attestations --store ./store
1780156536  TypeCheck  passed  by=lex-store@0.9.7
```

The supported attestation kinds form a layered validation regime:

| Kind | SR 11-7 validation element |
|---|---|
| `type_check` | implementation correctness (contract/effect conformance) |
| `spec`       | conceptual soundness — a formal property checked with `lex spec check` |
| `sandbox_run`| outcomes analysis — behaviour observed on executed inputs |
| `examples`   | intended-use documentation, verified |
| `diff_body`  | reviewed, scoped change record |
| `effect_audit`| confirmation of the declared side-effect surface |

**Effective challenge is enforced, not merely encouraged.** Require an
independent attestation before any version can advance to production:

```
$ lex policy require-attestation type_check --store ./store
→ require attestation `type_check`
$ lex policy show --store ./store
# required attestations
type_check  when=always
```

Add `lex policy require-attestation spec` (and/or `sandbox_run`) to
demand formal and behavioural challenge, not just a type check. Use
`--when-effects exchange,io` to apply the strictest bar to code that
touches the market.

To keep the challenge *independent*, exclude a producer from being
trusted to author logic it would also approve:

```
$ lex policy block-producer "gpt-4o@external" --reason "not independently reviewed" --store ./store
→ blocked producer `gpt-4o@external`
```

## 4. Change control (development, implementation, use)

> *Model changes should follow a controlled process before production
> use.*

The Candidate → review → promote cycle is documented and demonstrated in
[governance-workflow.md §5](./governance-workflow.md#5-change-approval-candidate-branch--review--promote):

1. `lex branch create candidate` — stage the change off `main`.
2. `lex ast-diff [--json]` — the reviewer sees a *typed* change record
   (which decision nodes changed; whether the signature or effects
   changed) rather than a character diff.
3. Independent reviewer attests; the `require-attestation` gate refuses
   to advance `main` to a stage missing the required attestation.

Because advancement is gated, "the change was reviewed before it went
live" is an enforced invariant, not a process hope.

## 5. Ongoing monitoring & outcomes analysis

> *SR 11-7 expects ongoing monitoring and outcomes analysis (e.g.
> back-testing) once a model is in use.*

Two lex facilities support this:

- **Deterministic replay (P4).** Because `validate` is pure, any recorded
  decision can be re-executed from its inputs alone and must reproduce
  the original result:

  ```
  $ lex replay <run_id> examples/governance/validation.lex validate
  $ lex diff   <run_a> <run_b>     # first NodeId where two runs diverge
  ```

  A divergence between a recorded production decision and its replay is a
  non-determinism or version-skew defect — surfaced structurally.

- **Execution provenance via lex-trail.** Live validation decisions are
  intended to be logged to [lex-trail](https://github.com/alpibrusl/lex-trail)
  for monitoring and outcomes analysis. Per the
  [stack overview](../README.md), this integration is **pending**; this
  document will be updated with the concrete query interface once
  lex-trail is wired into `lex-trade`.

## 6. SR 11-7 mapping summary

| SR 11-7 element | lex mechanism | Command(s) |
|---|---|---|
| Model inventory | content-addressed stages | `lex hash`, `lex audit` |
| Documentation / conceptual soundness | canonical AST + effect signatures + examples | `lex store get`, `lex audit`, `examples` attestation |
| Independent validation / effective challenge | attestation graph + required-attestation gate + producer block-list | `lex stage --attestations`, `lex policy require-attestation`, `lex policy block-producer` |
| Governance & change control | branch + gated promotion + typed change records | `lex branch`, `lex policy`, `lex ast-diff` |
| Ongoing monitoring / outcomes analysis | deterministic replay + lex-trail (pending) | `lex replay`, `lex diff`, `lex trace` |

## Reproducing

All commands share the session in
[governance-workflow.md → Reproducing](./governance-workflow.md#reproducing),
run from the `lex-finance` root against
[`examples/governance/validation.lex`](../examples/governance/validation.lex).
The `lex spec check`, `lex replay`, `lex diff`, and `lex trace` commands
require, respectively, a Spec and recorded runs; their command forms are
taken from `lex --help` (lex 0.9.7).
