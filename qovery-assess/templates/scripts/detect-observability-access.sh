#!/usr/bin/env bash
#
# detect-observability-access.sh — find a way to query the customer's observability
# platform that does NOT involve this skill handling a credential.
#
# Usage:  ./detect-observability-access.sh [platform]
#           platform: datadog | newrelic | prometheus | grafana | cloudwatch | dynatrace
#                     (omit to probe for all of them)
#
# Order of preference, and it matters:
#   1. An MCP server for the platform — the agent checks its own tool list; this script
#      cannot see it. Nothing is handled, nothing is stored.
#   2. An already-authenticated local CLI — the credential stays in the tool's own store.
#   3. Nothing found → fall back to asking the user for a read-only key (Phase 6f).
#
# This script NEVER reads a credential, and never reads the snapshot. It only reports
# which doors are already open.

set -uo pipefail
WANT="${1:-all}"
found=0

have() { command -v "$1" >/dev/null 2>&1; }
report() { printf '  %-12s %-22s %s\n' "$1" "$2" "$3"; found=1; }

echo "=== local CLI tooling ==="

if [ "$WANT" = "all" ] || [ "$WANT" = "datadog" ]; then
  # `dog` is a common name for unrelated tools, and exiting 0 on --help proves only that
  # something with that name is installed. Look for datadogpy's own vocabulary before
  # claiming Datadog tooling.
  if have dog; then
    if dog --help 2>&1 | grep -qiE 'datadog|metric[[:space:]]+post|monitor[[:space:]]+show'; then
      report datadog "dog (datadogpy)" "present — needs DD_API_KEY + DD_APP_KEY in its own config"
    else
      report datadog "dog (unverified)" "a binary named 'dog' exists but does not look like datadogpy — ignore it"
    fi
  fi
  have datadog-ci && report datadog    "datadog-ci"          "present — CI-oriented, limited query support"
fi

if [ "$WANT" = "all" ] || [ "$WANT" = "newrelic" ]; then
  if have newrelic; then
    if newrelic profile list >/dev/null 2>&1; then
      report newrelic "newrelic CLI" "AUTHENTICATED — use 'newrelic nrql query'"
    else
      report newrelic "newrelic CLI" "present but no profile — 'newrelic profile add'"
    fi
  fi
fi

if [ "$WANT" = "all" ] || [ "$WANT" = "cloudwatch" ]; then
  if have aws; then
    if acct=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
      # sts:GetCallerIdentity is granted to almost every principal and proves identity, not
      # CloudWatch permission. Probe the API that will actually be used.
      if aws cloudwatch list-metrics --max-items 1 >/dev/null 2>&1; then
        report cloudwatch "aws CLI" "AUTHENTICATED as account $acct, cloudwatch:ListMetrics allowed"
      else
        report cloudwatch "aws CLI" "identity OK (account $acct) but CloudWatch access UNVERIFIED — ListMetrics denied or unavailable"
      fi
    else
      report cloudwatch "aws CLI" "present but not authenticated"
    fi
  fi
fi

if [ "$WANT" = "all" ] || [ "$WANT" = "prometheus" ] || [ "$WANT" = "grafana" ]; then
  have promtool && report prometheus "promtool" "present — needs a reachable Prometheus URL"
  [ -n "${PROMETHEUS_URL:-}" ]  && report prometheus "\$PROMETHEUS_URL"  "set — try /api/v1/query"
  [ -n "${GRAFANA_URL:-}" ]     && report grafana    "\$GRAFANA_URL"     "set — Grafana datasource proxy"
fi

echo
echo "=== environment already carrying read access (use, never print) ==="
for v in DD_APP_KEY DATADOG_APP_KEY NEW_RELIC_API_KEY NR_API_KEY GRAFANA_API_KEY \
         PROMETHEUS_URL DYNATRACE_API_TOKEN HONEYCOMB_API_KEY; do
  if [ -n "${!v:-}" ]; then printf '  %-24s set (value not read)\n' "$v"; found=1; fi
done

# Datadog needs BOTH keys. An application key on its own authenticates nothing, and
# reporting it as available sends the agent down a route that will 403.
if [ -n "${DD_APP_KEY:-}${DATADOG_APP_KEY:-}" ] && [ -z "${DD_API_KEY:-}${DATADOG_API_KEY:-}" ]; then
  echo "  NOTE: a Datadog APPLICATION key is set but no API key (DD_API_KEY). Datadog"
  echo "        requires both — treat Datadog access as NOT available until the user"
  echo "        supplies the API key as well."
fi

echo
if [ "$found" = "0" ]; then
  echo "No local access found."
fi
cat <<'ENDOFNOTE'

NEXT — in this order:
  1. Check your own tool list for an MCP server for this platform (Datadog, Grafana,
     New Relic and others publish one). An MCP call handles no credential and is
     always preferable to anything below.
  2. If a CLI above says AUTHENTICATED, use it. The credential stays in its own store.
  3. Otherwise ask the user — see Phase 6f. Never take a key from the cluster, the
     snapshot, or a Qovery variable, even if one is readable there.
ENDOFNOTE
