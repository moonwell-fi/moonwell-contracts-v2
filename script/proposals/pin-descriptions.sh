#!/usr/bin/env bash
# pin-descriptions.sh — pin in-development proposal descriptions to IPFS (Pinata)
# and record the resulting ipfs://<cid> in the matching mips.json entry's
# optional `descriptionUri` field. HybridProposalV2 then emits that URI as the
# `descriptionUri` argument to MultichainGovernorV2.propose() instead of the
# full markdown (smaller calldata; resolves off-chain).
#
# Usage:
#   pin-descriptions.sh [<changed.md> ...]   # explicit list (CI passes the diff)
#   pin-descriptions.sh                      # auto-detect from git diff vs BASE_REF
#
# Env:
#   PINATA_JWT   Pinata JWT bearer token (required unless PIN_DRY_RUN=1)
#   BASE_REF     base ref for auto-detect (default: main)
#   PIN_DRY_RUN  =1 to skip the network call and use a deterministic fake CID
#                (for local testing without credentials)
#
# Only entries with "id": 0 (not yet submitted on-chain) are processed — a
# submitted proposal's descriptionUri is already immutable on-chain.
#
# Idempotent: Pinata is content-addressed, so re-pinning unchanged markdown
# yields the same CID and produces no mips.json diff.
#
# Requires: bash, jq, curl. Exits: 0 ok, 1 on error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

MIPS_JSON="proposals/mips/mips.json"
BASE_REF="${BASE_REF:-main}"

log() { printf '%s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# strip a leading ./ so paths from git diff and from .sol/.sh literals compare
norm() { printf '%s' "${1#./}"; }

# resolve the description .md path for a mips.json entry (raw path + envpath)
resolve_md() {
  local rawpath="$1" envpath="$2"
  if [ -n "$envpath" ]; then
    # entry has a .sh — it exports DESCRIPTION_PATH=<the .md>
    ( set +u; . "$envpath" >/dev/null 2>&1; printf '%s' "${DESCRIPTION_PATH:-}" )
  else
    # concrete proposal — grep the vm.readFile("...md") literal from its .sol
    local contract="${rawpath%%/*}" solfile
    solfile="$(find proposals/mips -type f -name "$contract" 2>/dev/null | head -n1)"
    [ -n "$solfile" ] || return 0
    grep -oE 'vm\.readFile\("[^"]+\.md"\)' "$solfile" | head -n1 |
      sed -E 's/.*"([^"]+)".*/\1/'
  fi
}

# emit "<rawpath>\t<normalized md path>" for every id:0 entry that resolves
id0_entries() {
  jq -r '.[] | select(.id == 0) | [.path, (.envpath // .envPath // "")] | @tsv' \
    "$MIPS_JSON" |
  while IFS=$'\t' read -r rawpath envpath; do
    local md
    md="$(resolve_md "$rawpath" "$envpath")"
    [ -n "$md" ] && printf '%s\t%s\n' "$rawpath" "$(norm "$md")"
  done
}

# pin a file to Pinata, echo the CID
pin_md() {
  local md="$1"
  if [ "${PIN_DRY_RUN:-0}" = "1" ]; then
    local h
    if command -v sha256sum >/dev/null 2>&1; then
      h="$(printf '%s' "$md" | sha256sum | cut -c1-24)"
    else
      h="$(printf '%s' "$md" | shasum -a 256 | cut -c1-24)"
    fi
    printf 'bafkreidryrun%s' "$h"
    return 0
  fi
  : "${PINATA_JWT:?PINATA_JWT must be set (or use PIN_DRY_RUN=1)}"
  local resp cid
  resp="$(curl -fsS -X POST https://api.pinata.cloud/pinning/pinFileToIPFS \
    -H "Authorization: Bearer ${PINATA_JWT}" \
    -F "file=@${md}" \
    -F 'pinataOptions={"cidVersion":1}' \
    -F "pinataMetadata={\"name\":\"$(basename "$md")\"}")" ||
    { err "Pinata request failed for $md"; return 1; }
  cid="$(printf '%s' "$resp" | jq -r '.IpfsHash // empty')"
  [ -n "$cid" ] || { err "no IpfsHash in Pinata response for $md: $resp"; return 1; }
  printf '%s' "$cid"
}

# write descriptionUri into the entry identified by its raw path. Writes in
# place (truncate + rewrite) rather than mv so the file's existing mode is
# preserved (mips.json is tracked executable; avoid a spurious mode change).
write_uri() {
  local path_key="$1" uri="$2" tmp
  tmp="$(mktemp)"
  jq --indent 4 --arg p "$path_key" --arg uri "$uri" \
    'map(if .path == $p then . + {descriptionUri: $uri} else . end)' \
    "$MIPS_JSON" >"$tmp"
  cat "$tmp" >"$MIPS_JSON"
  rm -f "$tmp"
}

# ---- collect candidate changed .md files ----------------------------------
CANDIDATES=()
if [ "$#" -gt 0 ]; then
  CANDIDATES=("$@")
else
  while IFS= read -r f; do
    [ -n "$f" ] && CANDIDATES+=("$f")
  done < <(git diff --name-only --diff-filter=d "$BASE_REF" -- 'proposals/mips' |
    grep -E '\.md$' || true)
fi

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  log "No changed proposal markdown files; nothing to pin."
  exit 0
fi

# ---- pin each candidate that maps to an in-development entry ---------------
pinned=0
for c in "${CANDIDATES[@]}"; do
  cn="$(norm "$c")"
  case "$cn" in
    proposals/mips/*.md) ;;
    *) continue ;;
  esac
  [ -f "$cn" ] || { log "skip $cn (file not found)"; continue; }

  match=""
  while IFS=$'\t' read -r rawpath md; do
    if [ "$md" = "$cn" ]; then match="$rawpath"; break; fi
  done < <(id0_entries)

  if [ -z "$match" ]; then
    log "skip $cn (no in-development mips.json entry references it)"
    continue
  fi

  cid="$(pin_md "$cn")" || exit 1
  write_uri "$match" "ipfs://$cid"
  log "pinned $cn -> ipfs://$cid  (mips.json entry: $match)"
  pinned=$((pinned + 1))
done

log "Done. Updated descriptionUri for $pinned proposal(s)."
