#!/usr/bin/env bash
# create-policy-token.sh — create a Qovery API Policy Token from a Rego file.
#
# Usage:
#   bash create-policy-token.sh <organizationId> <name> <policy.rego> [description] [expires_at]
#
# Authorizes creation with owner/admin credentials: an API token in $QOVERY_API_TOKEN (Token
# scheme) if set, otherwise the CLI's OIDC session (`qovery auth`, Bearer scheme).
# Writes the ONE-TIME secret token to a gitignored env file the caller controls and NEVER
# prints it. Prints only the non-secret id/name. Handles 400/403/409 with specific guidance.
#
# SECURITY: this script never echoes the token value. Do not add `echo`/`cat` of the token
# or of the output file. Refer to the token as *** everywhere.
set -euo pipefail

ORG_ID="${1:?usage: create-policy-token.sh <organizationId> <name> <policy.rego> [description] [expires_at]}"
NAME="${2:?missing token name}"
POLICY="${3:?missing policy.rego path}"
DESCRIPTION="${4:-}"
EXPIRES_AT="${5:-}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found."; exit 2; }
[ -f "$POLICY" ] || { echo "ERROR: policy file not found: $POLICY"; exit 2; }

# Admin credential: prefer an owner/admin API token (Token scheme); otherwise fall back to the
# CLI's OIDC session (Bearer scheme) — used inline so the value is never printed or persisted.
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Token ${QOVERY_API_TOKEN}")
elif command -v qovery >/dev/null 2>&1 && qovery auth token --print >/dev/null 2>&1; then
  AUTH=(-H "Authorization: Bearer $(qovery auth token --print)")
else
  echo "ERROR: no admin credential. Set QOVERY_API_TOKEN (owner/admin) or run 'qovery auth' first."; exit 2
fi

if grep -qE '^\s*package\s' "$POLICY"; then
  echo "ERROR: $POLICY contains a 'package' line — Qovery returns 400. Remove it and re-run."
  exit 2
fi

BYTES="$(wc -c < "$POLICY" | tr -d ' ')"
if [ "$BYTES" -gt 65536 ]; then
  echo "ERROR: policy is $BYTES bytes; the maximum is 65536."
  exit 2
fi

VERSION="$(cat _version.txt 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo unknown)"
UA="QoverySkill/qovery-policy-token (version:${VERSION}; https://github.com/Qovery/qovery-skills)"

# Build the JSON body with jq so the rego string is safely encoded (newlines/quotes).
BODY="$(jq -n \
  --arg name "$NAME" \
  --arg description "$DESCRIPTION" \
  --rawfile opa_policy "$POLICY" \
  --arg expires_at "$EXPIRES_AT" \
  '{name: $name, opa_policy: $opa_policy}
   + (if $description == "" then {} else {description: $description} end)
   + (if $expires_at  == "" then {} else {expires_at:  $expires_at}  end)')"

RESP="$(curl -s -w $'\n%{http_code}' -X POST \
  "https://api.qovery.com/organization/${ORG_ID}/policyApiToken" \
  "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  -H "User-Agent: ${UA}" \
  -d "$BODY")"

HTTP_CODE="$(printf '%s' "$RESP" | tail -n1)"
PAYLOAD="$(printf '%s' "$RESP" | sed '$d')"   # everything except the last line (never printed on success)

case "$HTTP_CODE" in
  2*)
    ID="$(printf '%s' "$PAYLOAD" | jq -r '.id')"
    OUT_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.name')"
    OUT_FILE="${POLICY_TOKEN_ENV_FILE:-.qovery-policy-token.env}"
    # Write the secret to a caller-controlled file WITHOUT printing it.
    umask 077
    printf 'POLICY_TOKEN=%s\n' "$(printf '%s' "$PAYLOAD" | jq -r '.token')" > "$OUT_FILE"
    # Best-effort: keep the secret out of git.
    if [ -d .git ] && ! grep -qxF "$OUT_FILE" .gitignore 2>/dev/null; then
      printf '%s\n' "$OUT_FILE" >> .gitignore
    fi
    echo "Created policy token '${OUT_NAME}' (id: ${ID})."
    echo "Secret written to ${OUT_FILE} (chmod 600, gitignored) — value is ***, never printed."
    echo "For live verification (Phase 5):  set -a; . ${OUT_FILE}; set +a"
    echo "Store it in your secret manager now — Qovery cannot show it again."
    ;;
  400) echo "ERROR 400: policy is empty, oversized, declares a 'package', or does not compile."; echo "Re-run opa-preflight.sh and remove any package line."; exit 1 ;;
  403) echo "ERROR 403: the caller is not an org Owner or Admin. Use an owner/admin API token to create policy tokens."; exit 1 ;;
  409) echo "ERROR 409: a policy token named '${NAME}' already exists. Choose a different name or revoke the existing one."; exit 1 ;;
  *)   echo "ERROR ${HTTP_CODE}: unexpected response creating the policy token."; exit 1 ;;
esac
