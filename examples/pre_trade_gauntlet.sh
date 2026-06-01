#!/usr/bin/env bash
# Theatrical demo — lex-finance: Five orders. Four walls. One paper trail.
# Usage:   bash examples/pre_trade_gauntlet.sh
#          asciinema rec examples/pre_trade_gauntlet.cast -c "bash examples/pre_trade_gauntlet.sh" --overwrite
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
# Newline around HR sequences (both single and double bar)
text = re.sub(r'(─{10,})', lambda m: '\n' + m.group(0) + '\n', raw)
text = re.sub(r'(═{10,})', lambda m: '\n' + m.group(0) + '\n', text)
# Newline before WALL and ORDER headings
text = re.sub(r'  (WALL \d)', r'\n  \1', text)
text = re.sub(r'  (ORDER \d)', r'\n  \1', text)
# Newline before step markers
text = re.sub(r'  (\[\d/\d\])', r'\n  \1', text)
# Separate adjacent JSON objects
text = re.sub(r'\}(\{)', r'}\n\1', text)
# Newlines before ORD- lines, → outcomes, entry_id, CAT lines
text = re.sub(r'(  ORD-)', r'\n\1', text)
text = re.sub(r'(  → )', r'\n\1', text)
text = re.sub(r'(  entry_id)', r'\n\1', text)
text = re.sub(r'(  CAT  )', r'\n\1', text)
text = re.sub(r'(  strategy:)', r'\n\1', text)
text = re.sub(r'(    NYSE)', r'\n\1', text)
text = re.sub(r'(    NASDAQ)', r'\n\1', text)
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
echo "  ${BOLD}lex-finance${RESET}  ·  Five orders. Four walls. One paper trail."
echo "  ${DIM}Every order blocked by a different typed gate — until one gets through.${RESET}"
echo
sleep 2

# ── The four walls ───────────────────────────────────────────────────────
hdr "Four walls between an AI agent and the exchange"
slow "  Wall 1  ${BOLD}Margin gate${RESET}      — Reg-T initial margin breach (lex-risk)"
slow "  Wall 2  ${BOLD}Risk limit${RESET}       — order qty ceiling exceeded (lex-trade)"
slow "  Wall 3  ${BOLD}FIX conformance${RESET}  — NYSE profile prohibits stop orders (lex-fix)"
slow "  Wall 4  ${BOLD}SOR availability${RESET} — DirectTo venue not in session list (lex-sor)"
echo
slow "  Order 5 clears all walls and generates a full paper trail:"
slow "  trail provenance · SOR routing · MiFID II RTS 22 · FINRA CAT"
echo
pause 1.2

# ── Type check ───────────────────────────────────────────────────────────
hdr "Type check — all effects declared before a byte runs"
cmd "lex check examples/pre_trade_gauntlet.lex"
pause 0.4
"$LEX" check examples/pre_trade_gauntlet.lex
echo "${GREEN}${BOLD}✓  ok${RESET}"
echo
pause 1.2

# ── Run ──────────────────────────────────────────────────────────────────
hdr "Five orders. Four walls. One paper trail."
slow "  Wall 1: 600 NVDA @ \$500 — notional \$300k, IM \$75k > \$50k cap — margin breach."
slow "  Wall 2: 5000 MSFT @ \$1  — passes margin (IM \$12.50) but qty 5000 > limit 1000."
slow "  Wall 3: Stop order → NYSE — NYSE eliminated stop orders in February 2016."
slow "  Wall 4: DirectTo(CBOE)   — CBOE not in the available venue list [NYSE, NASDAQ]."
slow "  Order 5: 100 MSFT @ \$125.50 — clears every gate, trail written, routes swept."
echo
pause 0.8

cmd "lex run --allow-effects fs_write,io,sql,time \\"
echo "        examples/pre_trade_gauntlet.lex main"
pause 0.5
"$LEX" run --allow-effects fs_write,io,sql,time \
  examples/pre_trade_gauntlet.lex main 2>&1 | fmt
echo
pause 1.5

# ── Summary ──────────────────────────────────────────────────────────────
hr
echo
echo "  ${BOLD}${GREEN}DONE${RESET}"
echo
echo "  Wall 1  margin gate:      ORD-NVDA  blocked — \$75k IM exceeds \$50k cap (lex-risk)."
echo "  Wall 2  risk limit:       ORD-BAD   blocked — qty 5000 exceeds max 1000 (lex-trade)."
echo "  Wall 3  FIX conformance:  ORD-STOP  blocked — NYSE profile: no_stop_orders (lex-fix)."
echo "  Wall 4  SOR routing:      ORD-DARK  blocked — venue CBOE not available (lex-sor)."
echo "  Order 5:                  ORD-001   accepted, trail entry_id is a SHA-256 content address."
echo "                            Sweep routed: 50 NYSE + 50 NASDAQ."
echo "                            MiFID II RTS 22 transaction report generated."
echo "                            FINRA CAT: MENO → MEOR → MEOR → MEOT with nanosecond timestamps."
echo
hr
echo
