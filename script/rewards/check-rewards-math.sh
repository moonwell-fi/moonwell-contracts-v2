#!/usr/bin/env bash
# check-rewards-math.sh — verify rewards-distribution MIP numbers balance.
#
# Usage:
#   check-rewards-math.sh                    # auto-detect from git diff main
#   check-rewards-math.sh <proposal-dir>     # explicit path or "mip-x51"
#
# Requires: bash, jq, awk. Optional: curl (worker cross-check, auto-skipped).
# Exits: 0 on all-pass, 1 on any fail, 2 on usage / config error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REWARDS_WORKER_URL="${REWARDS_WORKER_URL:-https://moonwell-reward-automation.moonwell.workers.dev}"

# --- formatting helpers ----------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; RED=""; YELLOW=""
fi

FAILED=0
pass() { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
fail() { printf "  ${RED}✗${RESET} %s\n" "$*"; FAILED=$((FAILED + 1)); }
warn() { printf "  ${YELLOW}⚠${RESET}  %s\n" "$*"; }
info() { printf "  ${DIM}·${RESET}  %s\n" "$*"; }

# --- numeric helpers (awk, double-precision; ~15-digit accuracy) -----------
# All values are wei (1e18-scaled). 15 digits = 6 decimal places of WELL — fine
# for ±10% / ±20-WELL tolerances.

awkf() { awk "$@"; }  # shorthand, keeps `set -e` happy if awk is aliased

# fmt_well <int-str> -> "1,234,567.89" (2 decimals, thousands separator)
fmt_well() {
  awkf -v v="$1" 'BEGIN {
    if (v < 0) { sign="-"; v=-v } else sign=""
    # round to 2-decimal WELL (1e16 units) to avoid frac-carry edge cases
    units = int(v / 1e16 + 0.5)
    whole = int(units / 100)
    frac  = units - whole * 100
    # thousands separators
    s = sprintf("%d", whole)
    out = ""
    n = length(s)
    for (i = 1; i <= n; i++) {
      out = out substr(s, i, 1)
      r = n - i
      if (r > 0 && r % 3 == 0) out = out ","
    }
    printf "%s%s.%02d WELL", sign, out, frac
  }'
}

# arg resolution ------------------------------------------------------------

PROPOSAL_DIR="${1:-}"

if [ -z "$PROPOSAL_DIR" ]; then
  # Auto-detect from git diff against main.
  DIRS=$(git -C "$REPO_ROOT" diff --name-only main -- 'proposals/mips/' 2>/dev/null \
    | awk -F/ '/^proposals\/mips\/mip-/ {print $1"/"$2"/"$3}' \
    | sort -u || true)
  if [ -z "$DIRS" ]; then
    echo "Usage: $0 <proposal-dir>" >&2
    echo "  e.g. $0 proposals/mips/mip-x51" >&2
    echo "  or   $0 mip-x51" >&2
    exit 2
  fi
  DIR_COUNT=$(printf "%s\n" "$DIRS" | wc -l | tr -d ' ')
  if [ "$DIR_COUNT" -gt 1 ]; then
    echo "Multiple changed proposal dirs detected:" >&2
    printf "  %s\n" $DIRS >&2
    echo "Pass one explicitly: $0 <dir>" >&2
    exit 2
  fi
  PROPOSAL_DIR="$DIRS"
fi

# bare-name shortcut
if [ ! -d "$PROPOSAL_DIR" ] && [ -d "$REPO_ROOT/proposals/mips/$PROPOSAL_DIR" ]; then
  PROPOSAL_DIR="proposals/mips/$PROPOSAL_DIR"
fi

# absolute
case "$PROPOSAL_DIR" in
  /*) ;;
  *) PROPOSAL_DIR="$REPO_ROOT/$PROPOSAL_DIR" ;;
esac

if [ ! -d "$PROPOSAL_DIR" ]; then
  echo "Error: not a directory: $PROPOSAL_DIR" >&2
  exit 2
fi

BASENAME=$(basename "$PROPOSAL_DIR")
MIPS_JSON="$REPO_ROOT/proposals/mips/mips.json"

# classify as rewards-distribution -----------------------------------------

IS_REWARDS_DIST=false

# Case 1: mips.json entry points at the RewardsDistribution template.
if [ -f "$MIPS_JSON" ] && jq -e \
  --arg bn "$BASENAME" \
  '.[] | select((.envpath // "") | contains($bn)) | select(.path == "RewardsDistribution.sol/RewardsDistributionTemplate.json")' \
  "$MIPS_JSON" >/dev/null 2>&1
then
  IS_REWARDS_DIST=true
fi

# Case 2: any .sol in the dir inherits RewardsDistributionTemplate.
if ! $IS_REWARDS_DIST; then
  for sol in "$PROPOSAL_DIR"/*.sol; do
    [ -f "$sol" ] || continue
    if grep -qE "is[[:space:]]+RewardsDistributionTemplate\b" "$sol"; then
      IS_REWARDS_DIST=true
      break
    fi
  done
fi

if ! $IS_REWARDS_DIST; then
  echo "[skip] $BASENAME is not a rewards-distribution proposal; nothing to check."
  exit 0
fi

# locate JSON + MD ---------------------------------------------------------

SH_FILE=$(find "$PROPOSAL_DIR" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | head -1)
JSON_PATH=""; MD_PATH=""
if [ -n "$SH_FILE" ]; then
  JSON_PATH=$(awk -F= '/^export MIP_REWARDS_PATH=/{print $2; exit}' "$SH_FILE" | tr -d '"')
  MD_PATH=$(awk   -F= '/^export DESCRIPTION_PATH=/{print $2; exit}' "$SH_FILE" | tr -d '"')
  case "$JSON_PATH" in /*) ;; *) [ -n "$JSON_PATH" ] && JSON_PATH="$REPO_ROOT/$JSON_PATH" ;; esac
  case "$MD_PATH"   in /*) ;; *) [ -n "$MD_PATH" ]   && MD_PATH="$REPO_ROOT/$MD_PATH" ;; esac
fi
# fallback
[ -z "$JSON_PATH" ] && JSON_PATH=$(find "$PROPOSAL_DIR" -maxdepth 1 -name "*.json" -type f | head -1)
[ -z "$MD_PATH"   ] && MD_PATH=$(find "$PROPOSAL_DIR" -maxdepth 1 -name "*.md"   -type f | head -1)

if [ ! -f "$JSON_PATH" ]; then
  echo "Error: rewards JSON not found for $BASENAME (looked for: $JSON_PATH)" >&2
  exit 2
fi

# header --------------------------------------------------------------------

printf "${BOLD}Auditing %s${RESET}\n" "$BASENAME"
printf "  JSON: %s\n" "${JSON_PATH#$REPO_ROOT/}"
printf "  MD:   %s\n" "${MD_PATH:+${MD_PATH#$REPO_ROOT/}}"
echo

# global values -------------------------------------------------------------

START=$(jq -r '.startTimeStamp // 0' "$JSON_PATH")
# automation worker misspells endTimeStamp on occasion; handle both.
END=$(jq -r '(.endTimeStamp // .endTimeSTamp // 0)' "$JSON_PATH")
DURATION=$(awkf -v s="$START" -v e="$END" 'BEGIN{printf "%d", e-s}')

if [ "$START" = "0" ] || [ "$END" = "0" ]; then
  echo "${RED}ERROR:${RESET} startTimeStamp / endTimeStamp missing in $JSON_PATH" >&2
  exit 1
fi

# portable date → ISO (macOS BSD date vs GNU date)
iso_date() {
  local ts="$1"
  date -u -r "$ts" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null \
    || date -u -d "@$ts" '+%Y-%m-%d %H:%M:%S UTC'
}

printf "Epoch: %s → %s (%d days %d hours)\n" \
  "$(iso_date "$START")" "$(iso_date "$END")" \
  $((DURATION / 86400)) $((DURATION % 86400 / 3600))
echo

# Check 6 (global): duration 27–29 days
printf "${BOLD}[global]${RESET} epoch duration\n"
if [ "$DURATION" -ge $((27 * 86400)) ] && [ "$DURATION" -le $((29 * 86400)) ]; then
  pass "duration ${DURATION}s is within [27, 29] days"
else
  fail "duration ${DURATION}s is outside [27, 29] days"
fi
echo

# per-chain checks ----------------------------------------------------------

CHAINS=$(jq -r 'keys[] | select(test("^[0-9]+$"))' "$JSON_PATH")

# Extract all Moonbeam → <chain D> bridge amounts once; used by per-chain inflow.
MOONBEAM_BRIDGES_JSON=$(jq -c '.["1284"].bridgeToRecipient // []' "$JSON_PATH")

for CHAIN in $CHAINS; do
  case "$CHAIN" in
    1284) NAME="Moonbeam" ;;
    8453) NAME="Base"     ;;
    10)   NAME="Optimism" ;;
    1)    NAME="Ethereum" ;;
    *)    NAME="chain-$CHAIN" ;;
  esac
  printf "${BOLD}[%s (%s)]${RESET}\n" "$NAME" "$CHAIN"

  # --- flow totals (wei) ---
  BRIDGE_IN=$(printf "%s" "$MOONBEAM_BRIDGES_JSON" \
    | jq -r --argjson c "$CHAIN" '.[]? | select(.network == $c) | .amount' \
    | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s}')
  [ "$CHAIN" = "1284" ] && BRIDGE_IN=0

  # withdrawWell(to=TEMPORAL_GOVERNOR) — funds that flow through TG.
  # withdrawWell(to=ECOSYSTEM_RESERVE_PROXY) — direct safety-module allocation,
  # bypasses TG (part of the safety-module budget, not TG's flow).
  WITHDRAW_TO_TG=$(jq -r --arg c "$CHAIN" \
    '.[$c].withdrawWell[]? | select(.to == "TEMPORAL_GOVERNOR") | .amount' \
    "$JSON_PATH" | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')

  WITHDRAW_TO_ECOSYSTEM=$(jq -r --arg c "$CHAIN" \
    '.[$c].withdrawWell[]? | select(.to == "ECOSYSTEM_RESERVE_PROXY") | .amount' \
    "$JSON_PATH" | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')

  TRANSFER_MRD=$(jq -r --arg c "$CHAIN" \
    '.[$c].transferFrom[]? | select(.to == "MRD_PROXY" and .token == "xWELL_PROXY") | .amount' \
    "$JSON_PATH" | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')

  TRANSFER_ECOSYSTEM=$(jq -r --arg c "$CHAIN" \
    '.[$c].transferFrom[]? | select(.to == "ECOSYSTEM_RESERVE_PROXY" and (.token == "xWELL_PROXY" or .token == "GOVTOKEN")) | .amount' \
    "$JSON_PATH" | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')

  MERKLE_TOTAL=$(jq -r --arg c "$CHAIN" '.[$c].merkleCampaigns[]?.amount // empty' "$JSON_PATH" \
    | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')

  # --- Check 1: flow conservation on TEMPORAL_GOVERNOR ---
  # (skipped for sending chain 1284 — Moonbeam has its own conservation)
  # TG receives: bridge + withdrawWell(to=TG)
  # TG sends:    transferFrom(from=TG, to=*) + merkleCampaign.amount (approved, pulled)
  if [ "$CHAIN" != "1284" ]; then
    INFLOW=$(awkf -v a="$BRIDGE_IN" -v b="$WITHDRAW_TO_TG" 'BEGIN{printf "%.0f", a+b}')
    OUTFLOW=$(awkf -v a="$TRANSFER_MRD" -v b="$TRANSFER_ECOSYSTEM" -v c="$MERKLE_TOTAL" 'BEGIN{printf "%.0f", a+b+c}')
    DIFF=$(awkf -v x="$INFLOW" -v y="$OUTFLOW" 'BEGIN{d=x-y; if (d<0) d=-d; printf "%.0f", d}')
    TOLERANCE="20000000000000000000"  # 20 WELL
    OK=$(awkf -v d="$DIFF" -v t="$TOLERANCE" 'BEGIN{print (d<=t) ? 1 : 0}')
    if [ "$OK" = "1" ]; then
      pass "TG flow conservation: inflow=$(fmt_well "$INFLOW")  outflow=$(fmt_well "$OUTFLOW")  (Δ=$(fmt_well "$DIFF"))"
    else
      fail "TG flow conservation: inflow=$(fmt_well "$INFLOW")  outflow=$(fmt_well "$OUTFLOW")  (Δ=$(fmt_well "$DIFF") > 20 WELL)"
    fi
  fi

  # --- Check 2: MRD budget = Σ speeds × duration (xWELL only) ---
  if [ "$TRANSFER_MRD" != "0" ] && [ -n "$TRANSFER_MRD" ]; then
    SPEEDS_SUM=$(jq -r --arg c "$CHAIN" '
      .[$c].setMRDSpeeds[]?
      | select(.emissionToken == "xWELL_PROXY")
      | ((if .newSupplySpeed >= 0 then .newSupplySpeed else 0 end)
       + (if .newBorrowSpeed >= 0 then .newBorrowSpeed else 0 end))
    ' "$JSON_PATH" 2>/dev/null | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')
    if [ -z "$SPEEDS_SUM" ] || [ "$SPEEDS_SUM" = "0" ]; then
      # Moonbeam uses setRewardSpeed (rewardType=0 only) instead.
      SPEEDS_SUM=$(jq -r --arg c "$CHAIN" '
        .[$c].setRewardSpeed[]?
        | select(.rewardType == 0)
        | ((if .newSupplySpeed >= 0 then .newSupplySpeed else 0 end)
         + (if .newBorrowSpeed >= 0 then .newBorrowSpeed else 0 end))
      ' "$JSON_PATH" 2>/dev/null | awkf 'BEGIN{s=0} {s+=$1} END{printf "%.0f", s+0}')
    fi
    EXPECTED=$(awkf -v s="$SPEEDS_SUM" -v d="$DURATION" 'BEGIN{printf "%.0f", s*d}')
    DIFF=$(awkf -v x="$EXPECTED" -v y="$TRANSFER_MRD" 'BEGIN{d=x-y; if (d<0) d=-d; printf "%.0f", d}')
    TOL=$(awkf -v y="$TRANSFER_MRD" 'BEGIN{printf "%.0f", y*0.10}')
    OK=$(awkf -v d="$DIFF" -v t="$TOL" 'BEGIN{print (d<=t) ? 1 : 0}')
    if [ "$OK" = "1" ]; then
      pass "MRD budget: speeds×duration=$(fmt_well "$EXPECTED")  vs  transferFrom=$(fmt_well "$TRANSFER_MRD")"
    else
      fail "MRD budget: speeds×duration=$(fmt_well "$EXPECTED")  vs  transferFrom=$(fmt_well "$TRANSFER_MRD")  (Δ=$(fmt_well "$DIFF") > 10%)"
    fi
  else
    info "no xWELL transferFrom → MRD_PROXY on this chain; skip MRD-budget check"
  fi

  # --- Check 3: Safety-module budget = stkWellEmissionsPerSecond × duration ---
  # Template (`_saveWithdrawWell` + `_saveTransferFroms`) sums transferFrom(to=ECOSYSTEM)
  # AND withdrawWell(to=ECOSYSTEM) into `ecosystemReserveProxyAmount` before asserting
  # against stkEPS × duration. Mirror that here.
  STK_EPS=$(jq -r --arg c "$CHAIN" '.[$c].stkWellEmissionsPerSecond // 0' "$JSON_PATH")
  ECOSYSTEM_TOTAL=$(awkf -v a="$TRANSFER_ECOSYSTEM" -v b="$WITHDRAW_TO_ECOSYSTEM" 'BEGIN{printf "%.0f", a+b}')
  if [ "$STK_EPS" != "0" ] && [ "$ECOSYSTEM_TOTAL" != "0" ]; then
    EXPECTED=$(awkf -v s="$STK_EPS" -v d="$DURATION" 'BEGIN{printf "%.0f", s*d}')
    DIFF=$(awkf -v x="$EXPECTED" -v y="$ECOSYSTEM_TOTAL" 'BEGIN{d=x-y; if (d<0) d=-d; printf "%.0f", d}')
    TOL=$(awkf -v y="$ECOSYSTEM_TOTAL" 'BEGIN{printf "%.0f", y*0.10}')
    OK=$(awkf -v d="$DIFF" -v t="$TOL" 'BEGIN{print (d<=t) ? 1 : 0}')
    LABEL="transferFrom+withdrawWell=$(fmt_well "$ECOSYSTEM_TOTAL")"
    if [ "$OK" = "1" ]; then
      pass "safety-module budget: stkEPS×duration=$(fmt_well "$EXPECTED")  vs  $LABEL"
    else
      fail "safety-module budget: stkEPS×duration=$(fmt_well "$EXPECTED")  vs  $LABEL  (Δ=$(fmt_well "$DIFF") > 10%)"
    fi
  elif [ "$CHAIN" != "8453" ]; then
    info "no stkWellEmissionsPerSecond → ECOSYSTEM_RESERVE flow on this chain; skip safety-module check"
  fi

  # --- Check 4: Moonbeam bridge fan-out matches pre-bridge transferFrom ---
  if [ "$CHAIN" = "1284" ]; then
    # For each bridgeToRecipient on Moonbeam, there must be a matching transferFrom
    # MGLIMMER_MULTISIG → MULTICHAIN_GOVERNOR_PROXY of equal amount (±1 WELL).
    BRIDGES=$(jq -c '.["1284"].bridgeToRecipient[]?' "$JSON_PATH")
    if [ -n "$BRIDGES" ]; then
      MISMATCH=0
      while IFS= read -r BRIDGE; do
        [ -z "$BRIDGE" ] && continue
        B_NET=$(echo "$BRIDGE" | jq -r '.network')
        B_AMT=$(echo "$BRIDGE" | jq -r '.amount' | awkf '{printf "%.0f", $1}')
        B_NATIVE=$(echo "$BRIDGE" | jq -r '.nativeValue // 0')
        # find matching transferFrom
        MATCH=$(jq -r --argjson amt "$B_AMT" '
          .["1284"].transferFrom[]?
          | select(.from == "MGLIMMER_MULTISIG" and .to == "MULTICHAIN_GOVERNOR_PROXY" and .token == "GOVTOKEN")
          | .amount
        ' "$JSON_PATH" | awkf -v amt="$B_AMT" 'BEGIN{best=1e30} {d=$1-amt; if (d<0) d=-d; if (d<best) best=d} END{printf "%.0f", best+0}')
        TOL="1000000000000000000"  # 1 WELL
        OK=$(awkf -v d="$MATCH" -v t="$TOL" 'BEGIN{print (d<=t) ? 1 : 0}')
        if [ "$OK" = "1" ]; then
          pass "bridge → chain $B_NET amount $(fmt_well "$B_AMT") matches pre-bridge transferFrom"
        else
          fail "bridge → chain $B_NET amount $(fmt_well "$B_AMT") has no matching transferFrom on Moonbeam (closest Δ=$(fmt_well "$MATCH"))"
          MISMATCH=1
        fi
        # nativeValue = 0 is a sim-breaker unless template pre-funds; informational.
        if [ "$B_NATIVE" = "0" ]; then
          warn "bridge → chain $B_NET has nativeValue:0 (template must pre-fund TEMPORAL_GOVERNOR, see CLAUDE.md)"
        fi
      done <<<"$BRIDGES"
      [ "$MISMATCH" = "0" ] || true
    fi
  fi

  # --- Check 5: data sanity ---
  # 5a: withdrawWell amounts > 0
  NEG_WITHDRAW=$(jq -r --arg c "$CHAIN" '.[$c].withdrawWell[]? | select(.amount <= 0) | "\(.to):\(.amount)"' "$JSON_PATH")
  if [ -n "$NEG_WITHDRAW" ]; then
    while IFS= read -r line; do
      fail "withdrawWell.amount must be > 0 (found: $line)"
    done <<<"$NEG_WITHDRAW"
  fi
  # 5b: multiRewarder.duration == 4 weeks
  BAD_MR=$(jq -r --arg c "$CHAIN" '.[$c].multiRewarder[]? | select(.duration != 2419200) | "\(.vault):\(.duration)"' "$JSON_PATH")
  if [ -n "$BAD_MR" ]; then
    while IFS= read -r line; do
      fail "multiRewarder.duration must be 2,419,200s / 4 weeks (found: $line)"
    done <<<"$BAD_MR"
  fi

  echo
done

# Optional Check 7: worker API cross-check --------------------------------
if command -v curl >/dev/null 2>&1; then
  URL="${REWARDS_WORKER_URL}/?type=json&timestamp=${START}"
  printf "${BOLD}[worker]${RESET} cross-check\n"
  if WORKER_JSON=$(curl -fsS --max-time 10 "$URL" 2>/dev/null); then
    WORKER_END=$(printf "%s" "$WORKER_JSON" | jq -r '(.endTimeStamp // .endTimeSTamp // 0)')
    if [ "$WORKER_END" = "$END" ]; then
      pass "worker endTimeStamp matches committed JSON ($END)"
    else
      warn "worker endTimeStamp=$WORKER_END, committed=$END (may be fine if automation regenerated between runs)"
    fi
  else
    info "worker API not reachable; skip (URL: $URL)"
  fi
  echo
fi

# summary ------------------------------------------------------------------

if [ "$FAILED" -eq 0 ]; then
  printf "${GREEN}${BOLD}All checks passed for %s${RESET}\n" "$BASENAME"
  exit 0
else
  printf "${RED}${BOLD}%d check(s) FAILED for %s${RESET}\n" "$FAILED" "$BASENAME"
  exit 1
fi
