#!/usr/bin/env bash
#
# dependency-surface.sh — enumerate the third-party vendor surface from variable and
# secret KEY names, per environment.
#
# Reads key names only. It never reads a variable value and never reads a secret
# (Qovery does not return secret values at all).
#
# Usage:  ./dependency-surface.sh <snapshotDir>
#
# Output is a starting point for the dependency map, not the map itself: a prefix is
# a hint, not a vendor. Confirm each one against the service inventory and the
# published sub-processor list before putting it in a customer document.

set -uo pipefail
DIR="${1:-.}"
[ -d "$DIR/raw/env" ] || { echo "ERROR: $DIR/raw/env not found" >&2; exit 1; }

# Qovery-injected and framework-local prefixes are not third-party vendors.
NOISE='^(QOVERY|VITE|NEXT|NODE|PORT|LOG|ENVIRONMENT|API|RAW|ADMIN|INTERNAL|DASHBOARD|PATIENT|STAGING|DATABASE|DB|REDIS|SECRET|JWT|AGENT|MCP|TS)$'

# An unreadable endpoint must never render as "no vendors" — that reads like a clean result.
UNREADABLE=""
for d in "$DIR"/raw/env/*/; do
  # With no environments the glob stays literal and every check below would report four
  # missing endpoints, marking a valid empty snapshot incomplete.
  [ -d "$d" ] || continue
  for f in environment.json variables.json secret-keys.json services.json; do
    [ -f "$d/$f" ] || { UNREADABLE="${UNREADABLE}$(basename "$d")/$f (missing)\n"; continue; }
    jq -e '._unreadable // false' "$d/$f" >/dev/null 2>&1 && \
      UNREADABLE="${UNREADABLE}$(basename "$d")/$f (status $(jq -r '._status // "?"' "$d/$f"))\n"
  done
done
if [ -n "$UNREADABLE" ]; then
  echo "!!! UNREADABLE INPUTS — the surface below is INCOMPLETE. Report these as UNKNOWN,"
  echo "!!! not as an absence of dependencies:"
  # One record per line: a status string contains a space, so word-splitting an
  # unquoted expansion would break each diagnostic across several lines.
  printf '%b' "$UNREADABLE" | while IFS= read -r u; do [ -n "$u" ] && echo "      $u"; done
  echo
fi

echo "=== vendor prefixes per environment (key names only) ==="
for d in "$DIR"/raw/env/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/environment.json" ] || continue
  jq -e '._unreadable // false' "$d/environment.json" >/dev/null 2>&1 && continue
  E=$(jq -r '.name // "?"' "$d/environment.json")
  { jq -r '.results[]?.key' "$d/variables.json" 2>/dev/null
    jq -r '.results[]?.key' "$d/secret-keys.json" 2>/dev/null; } \
    | sed -E 's/^(VITE|NEXT_PUBLIC)_//' \
    | sed -E 's/_.*$//' \
    | grep -vE "$NOISE" \
    | sort -u | tr '\n' ' ' | sed "s|^|$E: |"
  echo
done

echo
echo "=== vendors holding a SECRET, by environment ==="
echo "(a vendor with a secret in a non-production environment is a vendor that"
echo " non-production can reach — this is the privilege-asymmetry question)"
for d in "$DIR"/raw/env/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/secret-keys.json" ] || continue
  E=$(jq -r .name "$d/environment.json")
  N=$(jq -r '[.results[]?]|length' "$d/secret-keys.json")
  V=$({ jq -r '.results[]?.key' "$d/secret-keys.json"; } \
        | sed -E 's/^(VITE|NEXT_PUBLIC)_//' | sed -E 's/_.*$//' \
        | grep -vE "$NOISE" | sort -u | wc -l | tr -d ' ')
  printf '  %-24s %3s secrets across ~%s vendor prefixes\n' "$E" "$N" "$V"
done

echo
echo "=== in-cluster third-party workloads (Helm / container services) ==="
for d in "$DIR"/raw/env/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/services.json" ] || continue
  E=$(jq -r .name "$d/environment.json")
  jq -r --arg e "$E" '.results[]? | select(.service_type=="HELM" or .service_type=="CONTAINER")
    | [$e, .service_type, .name] | @tsv' "$d/services.json"
done | { command -v column >/dev/null 2>&1 && column -t -s$'\t' || cat; }
