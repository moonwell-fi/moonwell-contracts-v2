#!/usr/bin/env bash
#
# Wormhole Executor offchain quote — used for the Moonbeam-source router path
# (Moonbeam has no on-chain quoter; Base/Optimism/Ethereum use bridgeCost(uint16)).
#
# Usage:
#   ./script/wormhole-executor-quote.sh [SRC_WH_CHAIN] [DST_WH_CHAIN] [GAS_LIMIT]
#
# Defaults quote both x57 pre-staging routes: Moonbeam -> Base and Moonbeam -> Optimism.
#
# Wormhole chain IDs (NOT EVM chain IDs):
#   Ethereum=2  Moonbeam=16  Optimism=24  Base=30
#
# The signedQuote expires 3600s (1h) after issuance — fine for an immediate
# multisig bridge, too short to embed in a ~5-day governance proposal.

set -euo pipefail

ENDPOINT="https://executor.labsapis.com/v0/quote"   # testnet: executor-testnet.labsapis.com

quote() {
  local src="$1" dst="$2" gas="$3"
  # relayInstructions = encodePacked(uint8 type=1, uint128 gasLimit, uint128 msgValue=0)
  local ri
  ri=$(python3 -c "print('0x'+bytes([1]).hex()+($gas).to_bytes(16,'big').hex()+(0).to_bytes(16,'big').hex())")

  echo "=== srcChain=$src dstChain=$dst gasLimit=$gas ==="
  echo "relayInstructions: $ri"

  local resp
  resp=$(curl -sS --max-time 15 -X POST "$ENDPOINT" \
    -H 'Content-Type: application/json' \
    -d "{\"srcChain\":$src,\"dstChain\":$dst,\"relayInstructions\":\"$ri\"}")
  echo "$resp"

  python3 - "$resp" <<'PY'
import json, sys, datetime
try:
    q = json.loads(sys.argv[1])
    sq = q["signedQuote"][2:]
    exp = int(sq[120:136], 16)  # expiryTime: bytes 60..68 of signedQuote
    when = datetime.datetime.fromtimestamp(exp, datetime.timezone.utc)
    print(f"estimatedCost: {q['estimatedCost']} wei")
    print(f"expiryTime   : {exp} -> {when} UTC")
except (json.JSONDecodeError, KeyError):
    print("(no signedQuote in response)")
PY
  echo
}

SRC="${1:-16}"
if [[ -n "${2:-}" ]]; then
  quote "$SRC" "$2" "${3:-500000}"
else
  GAS="${3:-500000}"
  quote 16 30 "$GAS"   # Moonbeam -> Base
  quote 16 24 "$GAS"   # Moonbeam -> Optimism
fi
