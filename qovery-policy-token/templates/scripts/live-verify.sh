#!/usr/bin/env bash
# live-verify.sh — verify a live Qovery policy token against the test matrix.
#
# Usage:
#   set -a; . .qovery-policy-token.env; set +a      # loads $POLICY_TOKEN (the policy token secret)
#   bash live-verify.sh <test-matrix.json> [--run-destructive]
#
# Safe by design:
#   * DENY cases (expect=false) are sent for real — Qovery blocks them at auth (401) BEFORE the
#     request reaches the endpoint, so nothing executes. We assert HTTP 401.
#   * ALLOW + non-destructive cases (GET/HEAD) are sent and asserted 2xx.
#   * ALLOW + destructive cases are SKIPPED (already proven statically by opa-preflight.sh) unless
#     --run-destructive is passed AND you accept they will actually execute.
#
# Requires: $POLICY_TOKEN (the policy token, NOT the admin token) and jq.
# SECURITY: this script never prints $POLICY_TOKEN.
set -euo pipefail

MATRIX="${1:?usage: live-verify.sh <test-matrix.json> [--run-destructive]}"
RUN_DESTRUCTIVE="no"
[ "${2:-}" = "--run-destructive" ] && RUN_DESTRUCTIVE="yes"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found."; exit 2; }
[ -f "$MATRIX" ] || { echo "ERROR: matrix not found: $MATRIX"; exit 2; }
[ -n "${POLICY_TOKEN:-}" ] || { echo "ERROR: POLICY_TOKEN not set. Source the env file written by create-policy-token.sh first."; exit 2; }

VERSION="$(cat _version.txt 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo unknown)"
UA="QoverySkill/qovery-policy-token (version:${VERSION}; https://github.com/Qovery/qovery-skills)"
BASE="https://api.qovery.com"

send() { # method path body -> prints http_code
  local method="$1" path="$2" body="$3"
  if [ "$body" = "null" ] || [ -z "$body" ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$method" "${BASE}${path}" \
      -H "Authorization: Token ${POLICY_TOKEN}" -H "User-Agent: ${UA}"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$method" "${BASE}${path}" \
      -H "Authorization: Token ${POLICY_TOKEN}" -H "Content-Type: application/json" \
      -H "User-Agent: ${UA}" -d "$body"
  fi
}

N="$(jq '.cases | length' "$MATRIX")"
printf '\n%-38s %-18s %-8s %-8s %s\n' "CASE" "KIND" "EXPECT" "STATUS" "RESULT"
printf '%-38s %-18s %-8s %-8s %s\n' "$(printf '%.0s-' {1..38})" "----" "------" "------" "------"

pass=0; fail=0; skipped=0
for i in $(seq 0 $((N-1))); do
  name="$(jq -r ".cases[$i].name" "$MATRIX")"
  expect="$(jq -r ".cases[$i].expect" "$MATRIX")"
  method="$(jq -r ".cases[$i].live.method" "$MATRIX")"
  path="$(jq -r ".cases[$i].live.path" "$MATRIX")"
  destructive="$(jq -r ".cases[$i].live.destructive // false" "$MATRIX")"
  body="$(jq -c ".cases[$i].live.body // null" "$MATRIX")"

  if [ "$expect" = "true" ] && [ "$destructive" = "true" ]; then
    if [ "$RUN_DESTRUCTIVE" = "yes" ]; then
      code="$(send "$method" "$path" "$body")"
      if [[ "$code" =~ ^2 ]]; then result="PASS"; pass=$((pass+1)); else result="FAIL"; fail=$((fail+1)); fi
      printf '%-38s %-18s %-8s %-8s %s\n' "$name" "allow/destructive" "2xx" "$code" "$result"
    else
      printf '%-38s %-18s %-8s %-8s %s\n' "$name" "allow/destructive" "—" "—" "SKIPPED (verified statically)"
      skipped=$((skipped+1))
    fi
    continue
  fi

  code="$(send "$method" "$path" "$body")"
  if [ "$expect" = "false" ]; then
    # deny: must be blocked at auth (401), never executed
    if [ "$code" = "401" ]; then result="PASS"; pass=$((pass+1)); else result="FAIL"; fail=$((fail+1)); fi
    printf '%-38s %-18s %-8s %-8s %s\n' "$name" "deny" "401" "$code" "$result"
  else
    # allow + non-destructive read
    if [[ "$code" =~ ^2 ]]; then result="PASS"; pass=$((pass+1)); else result="FAIL"; fail=$((fail+1)); fi
    printf '%-38s %-18s %-8s %-8s %s\n' "$name" "allow/read" "2xx" "$code" "$result"
  fi
done

echo
echo "${pass} passed, ${fail} FAILED, ${skipped} skipped (destructive allow — verified statically in Phase 3)"
if [ "$fail" -gt 0 ]; then
  echo "A deny case that did not return 401 means the policy is too permissive; an allow/read that was not 2xx means it is too restrictive."
  echo "Treat this token as unusable: revoke it (Phase 6), fix the policy (Phase 2), and recreate."
  exit 1
fi
echo "Live behavior matches the matrix. Proceed to Phase 6 (deliver + lifecycle)."
