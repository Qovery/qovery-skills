#!/usr/bin/env bash
# opa-preflight.sh — locally verify a Qovery policy against an allow/deny test matrix.
#
# Usage: bash opa-preflight.sh <policy.rego> <test-matrix.json>
#
# For each case in the matrix it runs `opa eval` and compares the `allow` decision to the
# expected boolean, then prints a pass/fail table. Exits non-zero if any case fails.
#
# Requires: opa (1.19 recommended, the version Qovery runs) and jq.
# The submitted policy must NOT contain a `package` line; this script adds a temporary one
# to a scratch copy so OPA can address the rule — it never modifies your original file.
set -euo pipefail

POLICY="${1:?usage: opa-preflight.sh <policy.rego> <test-matrix.json>}"
MATRIX="${2:?usage: opa-preflight.sh <policy.rego> <test-matrix.json>}"

command -v opa >/dev/null 2>&1 || { echo "ERROR: opa not found. Install OPA 1.19 (see phase3-local-testing.md) or skip to live verify."; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not found."; exit 2; }
[ -f "$POLICY" ] || { echo "ERROR: policy file not found: $POLICY"; exit 2; }
[ -f "$MATRIX" ] || { echo "ERROR: matrix file not found: $MATRIX"; exit 2; }

if grep -qE '^\s*package\s' "$POLICY"; then
  echo "ERROR: $POLICY contains a 'package' line. Qovery rejects that on create (400). Remove it."
  exit 2
fi

SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT
SCRATCH_POLICY="$SCRATCH_DIR/policy.rego"
{ printf 'package qovery.policy\n\n'; cat "$POLICY"; } > "$SCRATCH_POLICY"

# Compile check (same class of error the API returns as 400)
if ! opa check "$SCRATCH_POLICY"; then
  echo "ERROR: policy failed 'opa check' — fix the compile error above before creating a token."
  exit 1
fi

N="$(jq '.cases | length' "$MATRIX" 2>/dev/null || true)"
[[ "$N" =~ ^[0-9]+$ ]] || { echo "ERROR: $MATRIX is not valid JSON or has no .cases array."; exit 2; }
[ "$N" -gt 0 ] || { echo "ERROR: matrix has no cases."; exit 2; }

printf '\n%-45s %-8s %-8s %s\n' "CASE" "EXPECT" "ACTUAL" "RESULT"
printf '%-45s %-8s %-8s %s\n' "$(printf '%.0s-' {1..45})" "------" "------" "------"

pass=0; fail=0
for i in $(seq 0 $((N-1))); do
  name="$(jq -r ".cases[$i].name" "$MATRIX")"
  expect="$(jq -r ".cases[$i].expect" "$MATRIX")"
  jq ".cases[$i].input" "$MATRIX" > "$SCRATCH_DIR/input.json"

  # --format raw prints the raw value (true/false), or empty when undefined (treated as false/deny)
  actual="$(opa eval -d "$SCRATCH_POLICY" -i "$SCRATCH_DIR/input.json" --format raw 'data.qovery.policy.allow' 2>/dev/null || true)"
  [ -n "$actual" ] || actual="false"

  if [ "$actual" = "$expect" ]; then
    result="PASS"; pass=$((pass+1))
  else
    result="FAIL"; fail=$((fail+1))
  fi
  printf '%-45s %-8s %-8s %s\n' "$name" "$expect" "$actual" "$result"
done

echo
echo "$pass/$N passed$([ "$fail" -gt 0 ] && echo ", $fail FAILED")"
[ "$fail" -eq 0 ] || { echo "Policy is NOT ready — fix the failing rules (phase2) and re-run before creating a token."; exit 1; }
echo "All cases green. Confirm the policy with the user, then proceed to Phase 4 (create)."
