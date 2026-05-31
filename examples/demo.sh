#!/usr/bin/env bash
# Theatrical demo — lex-finance: pre-trade gate, trail provenance, regulatory reporting
# Usage:   bash examples/demo.sh
#          asciinema rec examples/demo.cast -c "bash examples/demo.sh" --overwrite
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."
LEX="${LEX:-lex}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'
GREEN=$'\033[32m'; BLUE=$'\033[34m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'

slow() { echo "$@" | pv -qL 55; }
pause() { sleep "${1:-1.2}"; }
hr()  { printf '%s' "$DIM"; printf '─%.0s' {1..72}; printf '%s\n' "$RESET"; }
hdr() { echo; hr; echo "  ${BOLD}${CYAN}$*${RESET}"; hr; echo; }
cmd() { echo "${BOLD}${BLUE}\$${RESET}  $*"; pause 0.6; }

# Format the demo output: add newlines around HRs and before key patterns
# then pretty-print JSON blocks.
fmt() {
  python3 -c "
import sys, re, json
raw = sys.stdin.read().replace('null', '').strip()
# Newline around HR sequences
text = re.sub(r'(─{10,})', lambda m: '\n' + m.group(0) + '\n', raw)
# Newline before section headings
text = re.sub(r'  (\d+ —)', r'\n  \1', text)
# Separate adjacent JSON objects
text = re.sub(r'\}(\{)', r'}\n\1', text)
# Newlines before ORD- lines, → outcomes, and entry_id
text = re.sub(r'(  ORD-)', r'\n\1', text)
text = re.sub(r'(  → )', r'\n\1', text)
text = re.sub(r'(  entry_id)', r'\n\1', text)
# Pretty-print standalone JSON objects
out = []
for line in text.split('\n'):
    s = line.strip()
    if s.startswith('{') and s.endswith('}'):
        try:
            out.append(json.dumps(json.loads(s), indent=2))
            continue
        except Exception:
            pass
    out.append(line)
print('\n'.join(out))
"
}

clear
echo
echo "  ${BOLD}lex-finance${RESET}  ·  Typed finance infrastructure for AI agents"
echo "  ${DIM}Pre-trade gate · trail provenance · MiFID II RTS 22 · FINRA CAT${RESET}"
echo
sleep 2

# ── Stack ────────────────────────────────────────────────────────────────
hdr "Three guarantees — before a byte reaches the exchange"
slow "  An AI agent cannot reach the exchange transport without passing"
slow "  through a structurally-enforced pre-trade gate."
slow "  Every decision is immutably logged and deterministically replayable."
slow "  Every fill generates a typed regulatory report."
echo
pause 1.2

# ── Type check ───────────────────────────────────────────────────────────
hdr "Type check — all effects declared before a byte runs"
cmd "lex check examples/demo.lex"
pause 0.4
"$LEX" check examples/demo.lex
echo "${GREEN}${BOLD}✓  ok${RESET}"
echo
pause 1.2

# ── Run the demo ─────────────────────────────────────────────────────────
hdr "End to end — margin gate, pre-trade validation, trail, MiFID II, FINRA CAT"
slow "  Three orders. Two blocked by different gates. One accepted and logged."
slow "  ORD-MARGIN: margin breach — $75k initial margin exceeds the $50k cap."
slow "  ORD-BAD: passes margin, blocked by qty limit — 5000 exceeds max 1000."
slow "  ORD-001: passes both — entry_id written, RTS 22 report + CAT events generated."
echo
pause 0.8

cmd "lex run --allow-effects fs_write,io,sql,time \\"
echo "        examples/demo.lex main"
pause 0.5
"$LEX" run --allow-effects fs_write,io,sql,time \
  examples/demo.lex main 2>&1 | fmt
echo
pause 1.5

# ── Summary ─────────────────────────────────────────────────────────────
hr
echo
echo "  ${BOLD}${GREEN}DONE${RESET}"
echo
echo "  Margin gate: ORD-MARGIN blocked — \$75k IM exceeds \$50k cap (lex-risk)."
echo "  Pre-trade gate: ORD-BAD blocked — qty 5000 exceeds limit 1000 (lex-trade)."
echo "  Trail provenance: ORD-001 entry_id is a SHA-256 content address, not a row ID."
echo "  MiFID II RTS 22: typed report from FIX ExecutionReport + reference data."
echo "  FINRA CAT: MENO → MEOR → MEOT with nanosecond-precision timestamps."
echo
hr
echo
