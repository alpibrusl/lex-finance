# Algo governance workflow: typed change records with lex-vcs

How lex's content-addressed store and attestation graph record every
change to trading-validation logic as a **typed operation** — not a text
diff — and gate which versions may reach production.

> **Scope & disclaimer.** The `lex` commands and their output in this
> document were verified against **lex 0.9.7** (see
> [Reproducing](#reproducing) for the exact session). The mapping to
> **MiFID II Article 17** and **Commission Delegated Regulation (EU)
> 2017/589 (RTS 6)** is an *interpretive illustration* of how the tooling
> supports record-keeping obligations — it is not legal advice and has
> not been certified by counsel. Verify every regulatory claim against
> the primary text before relying on it.

All commands below run from the `lex-finance` repository root against the
self-contained example
[`examples/governance/validation.lex`](../examples/governance/validation.lex),
a representative stand-in for `lex-trade`'s `validation.validate`.

---

## 1. Why this matters for MiFID II Article 17

MiFID II Article 17 (and RTS 6) require an investment firm engaged in
algorithmic trading to keep records that let it — and its regulator —
reconstruct **what** its trading algorithms did and **how they changed
over time**. A text `git diff` answers "which characters changed"; a
regulator asks "which *decision* changed, and was the change reviewed
before it went live?"

lex records logic provenance structurally:

- Every top-level definition is a **content-addressed stage** — a
  `stage_id` derived from its canonical AST. Identical logic has an
  identical id regardless of formatting or comments.
- Changes are **typed operations** (`Replace` a `BinOp`, edit a match
  arm, add/remove an effect) over the AST, surfaced by `lex ast-diff`.
- Every stage carries an **attestation graph** (type-check, spec,
  sandbox-run, …) recording who validated what.
- Branch advancement is **gated by policy** so an unreviewed change
  cannot become the active version.

## 2. Baseline: publish the current logic

`lex hash` shows the content-addressed identity of each definition —
this *is* the model inventory (§3):

```
$ lex hash examples/governance/validation.lex
Order      canonical_ast=31337e01…  stage_id=6957ecf99e2564279109eebeed2e37efe7982b5c566111bec79791bf8499b636
RiskLimit  canonical_ast=85f8f775…  stage_id=980add30e38f3de07629d0c70b81cfabb99ceb70a5a1e8d22387bc13172a385a
validate   canonical_ast=2f1560dd…  stage_id=6e81423b9830211a9110cd4bba0394bd6fadca5bbacb3a5d43bf5111d62c0cc4
```

Publishing writes each stage to the store as a `Draft` and records a
baseline **TypeCheck** attestation automatically:

```
$ lex publish --store ./store examples/governance/validation.lex
$ lex stage 6e81423b9830211a9110cd4bba0394bd6fadca5bbacb3a5d43bf5111d62c0cc4 --attestations --store ./store
1780156536  TypeCheck  passed  by=lex-store@0.9.7
```

The `validate` `stage_id` (`6e81423b…`) is the stable handle for this
exact version of the logic. It changes if and only if the canonical AST
changes.

## 3. Model inventory

Two complementary views of "every function that constitutes the model":

```
$ lex hash examples/governance/validation.lex        # id + canonical AST hash per definition
$ lex audit examples/governance/validation.lex --json # signatures + declared effects
```

`lex audit --json` returns, for each function, its signature and effect
set — the evidence that `validate` is **pure** (no `[exchange]`,
`[io]`, …), which is the basis of the deterministic-replay claim (P4):

```json
{
  "summary": { "pure": 1 },
  "hits": [
    {
      "name": "validate",
      "signature": "fn validate(order :: Order, limit :: RiskLimit) -> Result[Order, Str]",
      "effects": [],
      "matched": ["all"]
    }
  ]
}
```

## 4. Typed semantic change records (the Article 17 centrepiece)

Suppose risk tightens the quantity ceiling from `>` to `>=`
([`validation_v2.lex`](../examples/governance/validation_v2.lex)). A text
diff shows a one-character change. `lex ast-diff` shows *which decision
nodes* changed:

```
$ lex ast-diff examples/governance/validation.lex examples/governance/validation_v2.lex
~ modified fn validate(order :: Order, limit :: RiskLimit) -> Result[Order, Str]
             @ body.scrutinee: BinOp edited
             @ body.arms[0]: Constructor edited
             @ body.arms[1].scrutinee: BinOp edited
             @ body.arms[1].arms[0]: Constructor edited
             @ body.arms[1].arms[1]: Constructor edited
```

`--json` produces a machine-readable change record suitable for a
regulatory submission — note `signature_changed` and `effect_changes`,
which let a reviewer instantly see whether an edit altered the contract
or the side-effect surface:

```json
{
  "modified": [
    {
      "name": "validate",
      "signature_changed": false,
      "effect_changes": { "added": [], "removed": [] },
      "body_patches": [
        { "op": "Replace", "node_path": "body.scrutinee", "from_kind": "BinOp", "to_kind": "BinOp" },
        { "op": "Replace", "node_path": "body.arms[1].scrutinee", "from_kind": "BinOp", "to_kind": "BinOp" }
      ]
    }
  ]
}
```

This is the P12 principle — *typed semantic change* — and the concrete
artifact Article 17 record-keeping needs: a precise, replayable
description of how an algorithm's behaviour changed.

## 5. Change approval: Candidate branch → review → promote

A change is staged on a branch and cannot reach `main` until it satisfies
the required attestations. Create a candidate branch off `main`:

```
$ lex branch create candidate --store ./store
→ created branch `candidate` from `main`
$ lex branch list --store ./store
  candidate
* main
```

Require a `type_check` attestation before any branch advance — the
positive gate that enforces "no unreviewed logic in production":

```
$ lex policy require-attestation type_check --store ./store
→ require attestation `type_check`
$ lex policy show --store ./store
# blocked producers
(none)

# required attestations
type_check  when=always
```

Available attestation kinds: `type_check`, `spec`, `sandbox_run`,
`examples`, `diff_body`, `effect_audit`. Requiring `spec` or
`sandbox_run` in addition raises the bar for independent validation (see
[SR 11-7 governance](./sr11-7-governance.md)). Restrict a requirement to
effectful code with `--when-effects exchange,io`.

The candidate is published to its branch, attested, reviewed, and only
then promoted by advancing `main` to the reviewed stage. Because the gate
is `when=always`, a stage lacking the required attestation is refused.

## 6. Producer trust: blocking unreviewed sources

The negative gate records *which producer* may contribute logic. Block an
agent/tool whose output has not been independently reviewed:

```
$ lex policy block-producer "gpt-4o@external" --reason "not independently reviewed" --store ./store
→ blocked producer `gpt-4o@external`
$ lex policy show --store ./store
# blocked producers
gpt-4o@external  since=1780156491  reason=not independently reviewed

# required attestations
type_check  when=always
```

Use `lex policy unblock-producer <name>` once a producer's output has
passed independent review. The blocked/allowed list is the auditable
record of the firm's "who is trusted to author trading logic" decision.

## 7. Audit export

A machine-readable change log for a regulator combines three commands:

```
$ lex store list --store ./store                 # every stage id in the store
$ lex store get  --store ./store <stage_id>       # the full canonical AST of one version (JSON)
$ lex attest filter --store ./store               # the attestation graph
1780156536  type_check  passed  6e81423b9830211a…  by=lex-store@0.9.7
```

`lex attest filter` accepts `--kind`, `--result`, and `--since` to scope
the export to a reporting window, e.g.
`lex attest filter --kind type_check --result passed --since <ts>`.

## 8. MiFID II Article 17 mapping

| Article 17 / RTS 6 expectation | lex mechanism | Command |
|---|---|---|
| Records of algorithmic trading strategies | content-addressed stages | `lex hash`, `lex publish`, `lex store get` |
| Records of *changes* to those strategies | typed operations over the AST | `lex ast-diff [--json]` |
| Evidence the strategy was tested/validated | attestation graph | `lex stage … --attestations`, `lex attest filter` |
| Change control before deployment | branch + required-attestation gate | `lex branch`, `lex policy require-attestation` |
| Controls over who authors strategies | producer block-list | `lex policy block-producer` |

## Reproducing

```
git clone https://github.com/alpibrusl/lex-finance && cd lex-finance
# lex 0.9.7 toolchain on PATH
lex check --strict examples/governance/validation.lex
lex hash               examples/governance/validation.lex
lex publish --store ./store examples/governance/validation.lex
lex ast-diff           examples/governance/validation.lex examples/governance/validation_v2.lex
```

Stage ids are deterministic functions of the canonical AST, so the
`stage_id` values above are reproducible byte-for-byte from these files.
Attestation timestamps (the leading integer) are wall-clock and will
differ per run.

## A note on command names

Earlier drafts of this workflow referred to `lex vcs log`, `lex blame`,
and `lex attest <file>`. The shipping CLI exposes these capabilities
through `lex hash` / `lex store` (provenance), `lex ast-diff` (typed
change records), `lex stage --attestations` / `lex attest filter` (the
attestation graph), and `lex branch` / `lex policy` (change control). The
commands in this document are the verified, current spelling.
