#!/usr/bin/env bash
# record-signup.sh — record a sign-up for tracking + lead qualification, mirroring what
# console.qovery.com does, but tagged as a CLI/agent sign-up.
#
# It fires TWO things:
#   1. POST /admin/userSignUp  (Qovery's own signup record) via `qovery api` (CLI auth)
#   2. Cargo lead ingest -> HubSpot/CRM, with signup_source (only if a token is provided)
#
# Identity (first/last name, email) is read automatically from `qovery api account`.
# Qualification fields come from the Phase 1/3 interview and are passed as env vars.
#
# Usage:
#   COMPANY="Acme" USE_CASE="PR preview environments" USER_ROLE="CTO" \
#   TYPE_OF_USE=WORK WEBSITE="https://acme.com" SIGNUP_SOURCE="CLI" \
#   [QOVERY_CARGO_INGEST_TOKEN=...] \
#   bash record-signup.sh [--dry-run]
#
# --dry-run prints the exact payloads and does not send anything.
# SECURITY: never prints the Cargo token; skips the Cargo step if the token is unset.
set -euo pipefail

DRY="no"; [ "${1:-}" = "--dry-run" ] && DRY="yes"

command -v qovery >/dev/null 2>&1 || { echo "ERROR: qovery CLI not found."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found."; exit 2; }

# Qualification inputs (from the interview) — with sensible defaults
COMPANY="${COMPANY:-}"
USE_CASE="${USE_CASE:-}"
USER_ROLE="${USER_ROLE:-}"
TYPE_OF_USE="${TYPE_OF_USE:-WORK}"          # PERSONAL | SCHOOL | WORK
COMPANY_SIZE="${COMPANY_SIZE:-}"            # 1-10 | 11-50 | 51-200 | 201-500 | 500+
WEBSITE="${WEBSITE:-}"
PHONE="${PHONE:-}"
SIGNUP_SOURCE="${SIGNUP_SOURCE:-CLI}"       # tags agent/CLI signups distinctly from "Console"
[ -n "$USE_CASE" ] || { echo "ERROR: set USE_CASE (maps to qovery_usage)."; exit 2; }

# Identity from the authenticated account
ACC="$(qovery api account 2>/dev/null || true)"
if printf '%s' "$ACC" | jq -e . >/dev/null 2>&1; then
  FIRST="$(printf '%s' "$ACC" | jq -r '.first_name // ""')"
  LAST="$(printf '%s' "$ACC" | jq -r '.last_name // ""')"
  EMAIL="$(printf '%s' "$ACC" | jq -r '.communication_email // ""')"
elif [ "$DRY" = "yes" ]; then
  FIRST="Jane"; LAST="Doe"; EMAIL="jane@example.com"   # placeholders so --dry-run works unauthenticated
else
  echo "ERROR: could not read account (are you authenticated? run 'qovery auth --headless')."; exit 2
fi

# 1) Qovery signup record: POST /admin/userSignUp (no signup_source field, so the source
#    goes in current_step as a free-text marker)
SIGNUP_BODY="$(jq -n \
  --arg first_name "$FIRST" --arg last_name "$LAST" --arg user_email "$EMAIL" \
  --arg type_of_use "$TYPE_OF_USE" --arg qovery_usage "$USE_CASE" \
  --arg company_name "$COMPANY" --arg user_role "$USER_ROLE" \
  --arg company_size "$COMPANY_SIZE" --arg current_step "qovery-signup-skill:${SIGNUP_SOURCE}" \
  '{first_name:$first_name, last_name:$last_name, user_email:$user_email,
    type_of_use:$type_of_use, qovery_usage:$qovery_usage, current_step:$current_step}
   + (if $company_name != "" then {company_name:$company_name} else {} end)
   + (if $user_role   != "" then {user_role:$user_role}     else {} end)
   + (if $company_size != "" then {company_size:$company_size} else {} end)')"

# 2) Cargo -> HubSpot lead ingest (public model id from the console; token via env, never committed)
CARGO_MODEL="7e42e545-bdee-438b-b2dc-3799e95bf046"
CARGO_URL="https://api.getcargo.io/v1/models/${CARGO_MODEL}/records/ingest"
CARGO_BODY="$(jq -n \
  --arg email "$EMAIL" --arg first_name "$FIRST" --arg last_name "$LAST" \
  --arg company "$COMPANY" --arg job_title "$USER_ROLE" --arg phone "$PHONE" \
  --arg website "$WEBSITE" --arg signup_source "$SIGNUP_SOURCE" \
  '{email:$email, first_name:$first_name, last_name:$last_name, company:$company,
    job_title:$job_title, phone:$phone, website:$website, signup_source:$signup_source}')"

if [ "$DRY" = "yes" ]; then
  echo "# DRY RUN — nothing sent"
  echo "## POST /admin/userSignUp"; echo "$SIGNUP_BODY" | jq .
  echo "## Cargo ingest ($CARGO_URL?token=***)"; echo "$CARGO_BODY" | jq .
  [ -n "${QOVERY_CARGO_INGEST_TOKEN:-}" ] && echo "(Cargo token present — would send)" || echo "(no QOVERY_CARGO_INGEST_TOKEN — Cargo step would be SKIPPED)"
  exit 0
fi

# Send 1) via the CLI (uses stored auth, no token handling)
if printf '%s' "$SIGNUP_BODY" | qovery api admin/userSignUp --method POST --input - >/dev/null 2>&1; then
  echo "Recorded Qovery sign-up (POST /admin/userSignUp), source=${SIGNUP_SOURCE}."
else
  echo "WARN: POST /admin/userSignUp did not succeed (non-fatal)."
fi

# Send 2) only if the ingest token is provided
if [ -n "${QOVERY_CARGO_INGEST_TOKEN:-}" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${CARGO_URL}?token=${QOVERY_CARGO_INGEST_TOKEN}" \
    -H "Content-Type: application/json" -d "$CARGO_BODY")"
  case "$code" in
    2*) echo "Sent lead to HubSpot funnel via Cargo (signup_source=${SIGNUP_SOURCE}).";;
    *)  echo "WARN: Cargo ingest returned HTTP ${code} (non-fatal).";;
  esac
else
  echo "Cargo/HubSpot step skipped: set QOVERY_CARGO_INGEST_TOKEN to enable lead-funnel sync (never commit it)."
fi
