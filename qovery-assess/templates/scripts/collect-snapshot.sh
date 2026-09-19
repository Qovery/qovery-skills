#!/usr/bin/env bash
#
# collect-snapshot.sh — read-only Qovery organization snapshot collector.
#
# Issues GET requests ONLY. It never creates, updates, deletes, deploys, stops,
# or restarts anything. It never fetches master credentials or a kubeconfig.
#
# Two payloads carry live credentials and are handled specially rather than skipped:
#   * /organization/{orgId}/inviteMember returns an `invitation_link`, which anyone can
#     use to accept the invitation. It is stripped IN THE STREAM (api_get_stripped).
#   * /organization/{orgId}/credentials returns `access_key_id`. It is kept — the check
#     needs the credential TYPE — but SC-24 forbids copying the key ID into the report.
#
# /environment/{envId}/deploymentBuildUsageReport is deliberately NOT collected: it is a
# POST, and it publishes a publicly accessible Grafana snapshot. Never add it.
#
# Usage:
#   ./collect-snapshot.sh <organizationId> [outputDir]
#
# Environment knobs:
#   DEPLOY_LOG_RUNS=3     deployment executions per environment to pull logs for
#   WITH_RUNTIME_LOGS=1   also pull per-service runtime logs (slower; set 0 to skip)
#
# Log and event bodies are REDACTED in the stream, before anything is written — see
# redact_log() and api_get_redacted().
#
# SCOPE OF THAT GUARANTEE — read this before repeating it in a report.
# It covers log and event bodies. It does NOT cover environment variables: the snapshot
# stores `variables.json` verbatim, values included, and it has to. Detecting a credential
# pasted into a plain variable (VS-01), classifying a URL as internal or third-party (VS-05)
# and finding the same credential in two environments (VS-09) all require the value.
# Qovery returns values only for NON-SECRET variables — a secret's value is never returned
# by the API — so the snapshot contains exactly what any member with read access already
# sees, and a credential in there is itself the finding.
#
# Consequences, which are not optional:
#   * The snapshot directory is customer configuration. Treat it as sensitive.
#   * Never commit it, never attach it to a ticket, delete it when the assessment is done.
#   * In the report, scope the claim: "log and event bodies were redacted at collection
#     time". Do NOT write "no secret value was written to disk" — for variables that is
#     not true, and the whole document's credibility rests on statements like that holding.
#
# Auth (in order of preference):
#   1. $QOVERY_API_TOKEN          -> Authorization: Token <value>
#   2. qovery CLI (authenticated) -> Authorization: Bearer $(qovery auth token --print)
#
# Token values are used inline and never printed.

set -uo pipefail

ORG_ID="${1:-}"
OUT_DIR="${2:-./qovery-assessment}"
API="https://api.qovery.com"
DEPLOY_LOG_RUNS="${DEPLOY_LOG_RUNS:-3}"
WITH_RUNTIME_LOGS="${WITH_RUNTIME_LOGS:-1}"

if [ -z "$ORG_ID" ]; then
  echo "Usage: $0 <organizationId> [outputDir]" >&2
  exit 1
fi

for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required" >&2; exit 1; }
done

SKILLS_VERSION="$(cat _version.txt 2>/dev/null || echo unknown)"
UA="QoverySkill/qovery-assess (version:${SKILLS_VERSION}; https://github.com/Qovery/qovery-skills)"

RAW="$OUT_DIR/raw"
LOG="$OUT_DIR/collect.log"

# A second run into the same directory must not inherit the first one's resources. These
# three subtrees are keyed by resource ID and fully re-derived on every run, so a deleted
# environment or service would otherwise survive here and be read by every later phase,
# which globs raw/env/*/ and raw/service/*/. Clear them rather than merging.
rm -rf "$RAW/env" "$RAW/service" "$RAW/cluster"
mkdir -p "$RAW" "$RAW/cluster" "$RAW/env" "$RAW/service" "$RAW/default"
: > "$LOG"

# --- auth -------------------------------------------------------------------
AUTH_MODE=""
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  AUTH_MODE="token"
elif command -v qovery >/dev/null 2>&1 && qovery auth token --print >/dev/null 2>&1; then
  AUTH_MODE="cli"
else
  echo "ERROR: no credentials. Set QOVERY_API_TOKEN or run 'qovery auth'." >&2
  exit 1
fi

# CLI tokens are short-lived, so they are cached here and refreshed periodically
# rather than shelling out to the CLI on every request (which costs ~2s per call and
# makes a large organization take hours). The value stays inside this script: it is
# never echoed, logged, or written to a file.
AUTH_HEADER=""
AUTH_TS=0
AUTH_TTL=300   # seconds before the cached CLI token is refreshed

refresh_auth() {
  local now
  now=$(date +%s)
  if [ "$AUTH_MODE" = "token" ]; then
    [ -n "$AUTH_HEADER" ] && return 0
    AUTH_HEADER="Authorization: Token ${QOVERY_API_TOKEN}"
  else
    if [ -z "$AUTH_HEADER" ] || [ $((now - AUTH_TS)) -ge "$AUTH_TTL" ]; then
      # The CLI states its own scheme. An OAuth login yields token_type "Bearer"; an
      # opaque API token does not, and hardcoding Bearer around it fails every request.
      # --json is piped straight into jq so only that one field is ever extracted.
      local scheme
      scheme=$(qovery auth token --json 2>/dev/null | jq -r '.token_type // "Bearer"')
      [ -z "$scheme" ] || [ "$scheme" = "null" ] && scheme="Bearer"
      AUTH_HEADER="Authorization: ${scheme} $(qovery auth token --print 2>/dev/null)"
      AUTH_TS=$now
    fi
  fi
}

# api_get <path> <destination-file>
# Always GET. Writes the body on 2xx, records the status otherwise.
api_get() {
  local path="$1" dest="$2" code tmp
  tmp="$(mktemp)"
  refresh_auth
  code=$(curl -sS -o "$tmp" -w '%{http_code}' -X GET \
    --connect-timeout 10 --max-time 60 --retry 2 --retry-connrefused \
    -H "$AUTH_HEADER" \
    -H "User-Agent: $UA" "${API}${path}" 2>>"$LOG")
  [ -z "$code" ] && code=0

  mkdir -p "$(dirname "$dest")"
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    if jq -e . "$tmp" >/dev/null 2>&1; then
      jq '.' "$tmp" > "$dest"
    else
      cp "$tmp" "$dest"
    fi
    printf 'OK    %s %s\n' "$code" "$path" >> "$LOG"
  else
    printf '{"_unreadable":true,"_status":%s,"_path":"%s"}\n' "$code" "$path" > "$dest"
    printf 'MISS  %s %s\n' "$code" "$path" >> "$LOG"
  fi
  rm -f "$tmp"
}

# Logs can contain credentials. Every log body is redacted AS IT IS WRITTEN, so no secret
# value ever lands on disk or in the agent's context. The markers left behind are what the
# LG-06 check counts — detection and redaction in a single pass.
redact_log() {
  # A PEM block spans lines, so the body and END marker must go too — replacing only the
  # BEGIN marker leaves the key material in the snapshot. This range runs first.
  sed -E '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\
<<REDACTED:private-key>>' \
  | sed -E \
    -e 's/(AKIA|ASIA)[0-9A-Z]{16}/<<REDACTED:aws-access-key-id>>/g' \
    -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/<<REDACTED:jwt>>/g' \
    -e 's/(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/<<REDACTED:github-token>>/g' \
    -e 's#(postgres|postgresql|mysql|mongodb\+srv|mongodb|redis|amqp|amqps)://[^:@/[:space:]]+:[^@[:space:]]+@#\1://<<REDACTED:dsn-credentials>>@#g' \
    -e 's/(^|[^A-Za-z])([Bb]earer|[Bb]asic)[[:space:]]+[A-Za-z0-9._~+/=-]{16,}/\1\2 <<REDACTED:bearer>>/g' \
    -e 's/(^|[^A-Za-z])([Bb]earer|[Tt]oken|[Aa]uthorization)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9._~+/=-]{16,}/\1\2 <<REDACTED:bearer>>/g' \
    -e 's/(xox[abprs]-[A-Za-z0-9-]{10,})/<<REDACTED:slack-token>>/g' \
    -e 's/(sk-[A-Za-z0-9]{20,})/<<REDACTED:api-key>>/g' \
    -e 's/(arn:aws[a-z-]*:secretsmanager:[^[:space:]"]*)/<<ARN:secretsmanager>>/g' \
    -e 's/(([Pp]assword|[Pp]asswd|[Ss]ecret|[Aa]pi_?key)[[:space:]]*[:=][[:space:]]*)[^[:space:],;"'"'"']{6,}/\1<<REDACTED:inline-credential>>/g' \
    -e 's/(\\?"([Pp]assword|[Pp]asswd|[Ss]ecret|[Aa]pi_?[Kk]ey|[Aa]ccess_?[Kk]ey|[Pp]rivate_?[Kk]ey|[Tt]oken|[Aa]uthorization)\\?"[[:space:]]*:[[:space:]]*\\?")[^"\\]{6,}/\1<<REDACTED:inline-credential>>/g'
}

# The rule above matters more than it looks. The unquoted rule before it excludes `"` from
# the value, so it matches `password=hunter2` and NOT `"password": "hunter2"` — and every
# payload this filter guards is JSON. The `\\?"` prefix also covers the escaped form,
# because the event stream embeds a serialized JSON document inside a JSON string field.

# redact_events — redact_log, plus every `value` field.
# The audit event `change` payload carries variable values keyed by a SEPARATE `key` field,
# so no key-name rule can reach them: {"key":"DB_PASSWORD","value":"<the credential>"}.
# The OP checks read event_type, origin, target_name and triggered_by, never `value`, so
# blanking it costs the assessment nothing and closes the only path by which a credential
# could reach disk from this endpoint.
redact_events() {
  redact_log \
  | sed -E -e 's/(\\?"value\\?"[[:space:]]*:[[:space:]]*\\?")[^"\\]+/\1<<REDACTED:variable-value>>/g'
}

# api_get_redacted <path> <dest> [filter-fn] — like api_get, but the body is redacted IN
# THE STREAM. The filter defaults to redact_log; the events endpoint passes redact_events.
# The raw body must never reach a file: a temp file holding an unredacted credential, even
# for a moment, is exactly the boundary this skill promises not to cross. Response headers
# go to their own file (they carry the status, never the body), so nothing is lost.
api_get_redacted() {
  local path="$1" dest="$2" filter="${3:-redact_log}" code hdr
  hdr="$(mktemp)"
  refresh_auth
  mkdir -p "$(dirname "$dest")"
  curl -sS -D "$hdr" -X GET \
    --connect-timeout 10 --max-time 120 --retry 2 --retry-connrefused \
    -H "$AUTH_HEADER" \
    -H "User-Agent: $UA" "${API}${path}" 2>>"$LOG" \
    | "$filter" > "$dest"
  code=$(awk 'toupper($1) ~ /^HTTP/ {c=$2} END {print c+0}' "$hdr" 2>/dev/null)
  [ -z "$code" ] && code=0
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    printf 'OK    %s %s\n' "$code" "$path" >> "$LOG"
  else
    printf '{"_unreadable":true,"_status":%s,"_path":"%s"}\n' "$code" "$path" > "$dest"
    printf 'MISS  %s %s\n' "$code" "$path" >> "$LOG"
  fi
  rm -f "$hdr"
}

# api_get_stripped <path> <dest> <jq-filter>
# Like api_get, but the body passes through a jq filter IN THE STREAM. Used where the
# payload carries a field that must never reach disk — an invitation link is a usable
# credential, so it is removed before the file is written, not after.
api_get_stripped() {
  local path="$1" dest="$2" filter="$3" code hdr
  hdr="$(mktemp)"
  refresh_auth
  mkdir -p "$(dirname "$dest")"
  curl -sS -D "$hdr" -X GET \
    --connect-timeout 10 --max-time 60 --retry 2 --retry-connrefused \
    -H "$AUTH_HEADER" \
    -H "User-Agent: $UA" "${API}${path}" 2>>"$LOG" \
    | jq "$filter" > "$dest" 2>/dev/null
  code=$(awk 'toupper($1) ~ /^HTTP/ {c=$2} END {print c+0}' "$hdr" 2>/dev/null)
  [ -z "$code" ] && code=0
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    printf 'OK    %s %s\n' "$code" "$path" >> "$LOG"
  else
    printf '{"_unreadable":true,"_status":%s,"_path":"%s"}\n' "$code" "$path" > "$dest"
    printf 'MISS  %s %s\n' "$code" "$path" >> "$LOG"
  fi
  rm -f "$hdr"
}

# has_git_source <serviceId> <services.json>
# The webhook and commit endpoints return 400 for a service with no git source (a
# container from a registry, a database). A git source always carries both `branch`
# and `url`, wherever it sits in the payload.
has_git_source() {
  jq -e --arg id "$1" '.results[]? | select(.id == $id)
      | [.. | objects | select(has("branch") and has("url"))] | length > 0' \
    "$2" >/dev/null 2>&1
}

say() { printf '  %s\n' "$1"; }

echo "Collecting read-only snapshot for organization $ORG_ID"
echo "Output: $OUT_DIR"
echo ""

# --- organization -----------------------------------------------------------
say "organization, identity & access"
api_get "/organization/${ORG_ID}"                          "$RAW/organization.json"
api_get "/organization/${ORG_ID}/member"                   "$RAW/members.json"
api_get "/organization/${ORG_ID}/customRole"               "$RAW/custom-roles.json"
api_get "/organization/${ORG_ID}/availableRole"            "$RAW/available-roles.json"
api_get "/organization/${ORG_ID}/apiToken"                 "$RAW/api-tokens.json"
api_get "/organization/${ORG_ID}/policyApiToken"           "$RAW/policy-tokens.json"
api_get "/organization/${ORG_ID}/enterpriseconnection"     "$RAW/sso.json"
api_get "/organization/${ORG_ID}/credentials"              "$RAW/cloud-credentials.json"
# invitation_link is a usable credential: removed in the stream, never written.
api_get_stripped "/organization/${ORG_ID}/inviteMember"    "$RAW/pending-invitations.json" \
  'if type == "object" then (.results? |= (map(del(.invitation_link)))) else . end'

say "integrations, alerting & metadata"
api_get "/organization/${ORG_ID}/webhook"                  "$RAW/webhooks.json"
api_get "/organization/${ORG_ID}/alert-receivers"          "$RAW/alert-receivers.json"
api_get "/organization/${ORG_ID}/alert-rules"              "$RAW/alert-rules.json"
api_get "/organization/${ORG_ID}/containerRegistry"        "$RAW/container-registries.json"
api_get "/organization/${ORG_ID}/helmRepository"           "$RAW/helm-repositories.json"
api_get "/organization/${ORG_ID}/gitToken"                 "$RAW/git-tokens.json"
api_get "/organization/${ORG_ID}/annotationsGroups"        "$RAW/annotations-groups.json"
api_get "/organization/${ORG_ID}/labelsGroups"             "$RAW/labels-groups.json"
api_get "/organization/${ORG_ID}/currentCost"              "$RAW/current-cost.json"

say "inventory"
api_get "/organization/${ORG_ID}/project"                  "$RAW/projects.json"
api_get "/organization/${ORG_ID}/environments"             "$RAW/environments.json"
api_get "/organization/${ORG_ID}/services"                 "$RAW/services.json"

say "platform defaults (baseline for drift detection)"
api_get "/defaultApplicationAdvancedSettings"              "$RAW/default/application-advanced-settings.json"
api_get "/defaultClusterAdvancedSettings"                  "$RAW/default/cluster-advanced-settings.json"
api_get "/defaultContainerAdvancedSettings"                "$RAW/default/container-advanced-settings.json"
api_get "/defaultJobAdvancedSettings"                      "$RAW/default/job-advanced-settings.json"
api_get "/defaultHelmAdvancedSettings"                     "$RAW/default/helm-advanced-settings.json"
api_get "/defaultTerraformAdvancedSettings"                "$RAW/default/terraform-advanced-settings.json"

say "audit events (change origin, shell access, role changes)"
# Paged: the API returns newest first. Five pages of 100 is enough to characterise
# how changes are made without pulling the entire history.
EV_TOKEN=""
: > "$RAW/events.ndjson"
for page in 1 2 3 4 5; do
  # NOTE: this endpoint returns `.events[]`, not the `.results[]` every other list uses.
  # The `change` field embeds full variable payloads INCLUDING VALUES, so the page is
  # redacted before anything is written.
  if [ -z "$EV_TOKEN" ]; then
    api_get_redacted "/organization/${ORG_ID}/events?pageSize=100" "$RAW/.events-page.json" redact_events
  else
    api_get_redacted "/organization/${ORG_ID}/events?pageSize=100&continueToken=${EV_TOKEN}" "$RAW/.events-page.json" redact_events
  fi
  jq -c '(.events // .results // [])[]?' "$RAW/.events-page.json" >> "$RAW/events.ndjson" 2>/dev/null
  EV_TOKEN=$(jq -r '.links.next // empty' "$RAW/.events-page.json" 2>/dev/null | sed -n 's/.*continueToken=\([^&]*\).*/\1/p')
  [ -z "$EV_TOKEN" ] && break
done
rm -f "$RAW/.events-page.json"
say "  $(wc -l < "$RAW/events.ndjson" | tr -d ' ') events collected"

# --- clusters ---------------------------------------------------------------
say "clusters"
api_get "/organization/${ORG_ID}/cluster"                  "$RAW/clusters.json"
api_get "/organization/${ORG_ID}/cluster/status"           "$RAW/cluster-status.json"

CLUSTER_IDS=$(jq -r '.results[]?.id // empty' "$RAW/clusters.json" 2>/dev/null)
for cid in $CLUSTER_IDS; do
  say "  cluster $cid"
  api_get "/organization/${ORG_ID}/cluster/${cid}/advancedSettings"    "$RAW/cluster/$cid/advanced-settings.json"
  api_get "/organization/${ORG_ID}/cluster/${cid}/routingTable"        "$RAW/cluster/$cid/routing-table.json"
  api_get "/organization/${ORG_ID}/cluster/${cid}/cloudProviderInfo"   "$RAW/cluster/$cid/cloud-provider-info.json"
  api_get "/organization/${ORG_ID}/cluster/${cid}/deploymentHistoryV2" "$RAW/cluster/$cid/deployment-history.json"
  api_get "/clusters/${cid}/analysis"                                  "$RAW/cluster/$cid/analyses.json"
done

# --- projects & environments ------------------------------------------------
say "projects"
PROJECT_IDS=$(jq -r '.results[]?.id // empty' "$RAW/projects.json" 2>/dev/null)
for pid in $PROJECT_IDS; do
  api_get "/project/${pid}/environment"          "$RAW/project/$pid/environments.json"
  api_get "/project/${pid}/environment/overview" "$RAW/project/$pid/overview.json"
  api_get "/project/${pid}/deploymentRule"       "$RAW/project/$pid/deployment-rules.json"
done

say "environments & services"
ENV_IDS=$(jq -r '.results[]?.id // empty' "$RAW/environments.json" 2>/dev/null)
[ -z "$ENV_IDS" ] && ENV_IDS=$(jq -r '.results[]?.id // empty' "$RAW"/project/*/environments.json 2>/dev/null | sort -u)

for eid in $ENV_IDS; do
  E="$RAW/env/$eid"
  api_get "/environment/${eid}"                      "$E/environment.json"
  api_get "/environment/${eid}/statuses"             "$E/statuses.json"
  api_get "/environment/${eid}/services"             "$E/services.json"
  api_get "/environment/${eid}/deploymentStage"      "$E/deployment-stages.json"
  api_get "/environment/${eid}/deploymentRule"       "$E/deployment-rule.json"
  api_get "/environment/${eid}/environmentVariable"  "$E/variables.json"
  # Secret KEYS only. The API never returns values; never print these either.
  api_get "/environment/${eid}/secret"               "$E/secret-keys.json"
  api_get "/environment/${eid}/deploymentHistoryV2"  "$E/deployment-history.json"

  ENV_NAME=$(jq -r '.name // "?"' "$E/environment.json" 2>/dev/null)
  ENV_MODE=$(jq -r '.mode // "?"' "$E/environment.json" 2>/dev/null)
  say "  $ENV_NAME ($ENV_MODE)"

  # Deployment logs for the most recent executions (redacted on write).
  for exec_id in $(jq -r '.results[0:'"$DEPLOY_LOG_RUNS"'][]?.identifier.execution_id // empty' \
                     "$E/deployment-history.json" 2>/dev/null); do
    api_get_redacted "/environment/${eid}/logs?version=${exec_id}" \
      "$E/deployment-logs/${exec_id}.json"
  done

  # Per-service detail. The environment services payload already carries the main
  # config, so only the sub-resources are fetched here.
  jq -r '.results[]? | [.id, .service_type] | @tsv' "$E/services.json" 2>/dev/null |
  while IFS=$'\t' read -r sid stype; do
    [ -z "$sid" ] && continue
    S="$RAW/service/$sid"
    case "$stype" in
      APPLICATION)
        api_get "/application/${sid}/advancedSettings"       "$S/advanced-settings.json"
        api_get "/application/${sid}/deploymentRestriction"  "$S/deployment-restriction.json"
        api_get "/application/${sid}/customDomain"           "$S/custom-domains.json"
        if has_git_source "$sid" "$E/services.json"; then
          api_get "/service/${sid}/gitWebhookStatus"         "$S/git-webhook-status.json"
          api_get "/application/${sid}/commit"               "$S/commits.json"
        fi
        [ "$WITH_RUNTIME_LOGS" = "1" ] && \
          api_get_redacted "/application/${sid}/log"         "$S/runtime-logs.json"
        ;;
      CONTAINER)
        api_get "/container/${sid}/advancedSettings"         "$S/advanced-settings.json"
        api_get "/container/${sid}/customDomain"             "$S/custom-domains.json"
        [ "$WITH_RUNTIME_LOGS" = "1" ] && \
          api_get_redacted "/container/${sid}/log"           "$S/runtime-logs.json"
        ;;
      JOB)
        api_get "/job/${sid}/advancedSettings"               "$S/advanced-settings.json"
        api_get "/job/${sid}/deploymentRestriction"          "$S/deployment-restriction.json"
        if has_git_source "$sid" "$E/services.json"; then
          api_get "/service/${sid}/gitWebhookStatus"         "$S/git-webhook-status.json"
          api_get "/job/${sid}/commit"                       "$S/commits.json"
        fi
        ;;
      HELM)
        api_get "/helm/${sid}/advancedSettings"              "$S/advanced-settings.json"
        api_get "/helm/${sid}/deploymentRestriction"         "$S/deployment-restriction.json"
        api_get "/helm/${sid}/customDomain"                  "$S/custom-domains.json"
        if has_git_source "$sid" "$E/services.json"; then
          api_get "/service/${sid}/gitWebhookStatus"         "$S/git-webhook-status.json"
          api_get "/helm/${sid}/commit?of=chart"             "$S/commits.json"
        fi
        ;;
      TERRAFORM)
        api_get "/terraform/${sid}/advancedSettings"         "$S/advanced-settings.json"
        api_get "/terraform/${sid}/deploymentRestriction"    "$S/deployment-restriction.json"
        if has_git_source "$sid" "$E/services.json"; then
          api_get "/service/${sid}/gitWebhookStatus"         "$S/git-webhook-status.json"
          api_get "/terraform/${sid}/commit"                 "$S/commits.json"
        fi
        ;;
      DATABASE)
        # NEVER /database/{id}/masterCredentials.
        api_get "/database/${sid}/backup"                    "$S/backups.json"
        ;;
    esac
  done
done

# --- summary ----------------------------------------------------------------
OK_COUNT=$(awk '/^OK/   {n++} END {print n+0}' "$LOG")
MISS_COUNT=$(awk '/^MISS/ {n++} END {print n+0}' "$LOG")

echo ""
echo "Snapshot complete — GET requests only, nothing was modified."
echo "  readable:   $OK_COUNT"
echo "  unreadable: $MISS_COUNT  (see $LOG; these become UNKNOWN checks)"
echo "  output:     $RAW"

if [ "$MISS_COUNT" -gt 0 ]; then
  echo ""
  echo "Unreadable endpoints:"
  grep '^MISS' "$LOG" | sed 's/^/  /' | head -20
fi
