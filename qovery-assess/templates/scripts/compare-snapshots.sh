#!/usr/bin/env bash
#
# compare-snapshots.sh — diff two read-only Qovery assessment snapshots.
#
# Turns a point-in-time assessment into a trend: what changed between two runs,
# which findings closed, and which regressed. Reads only local files — it makes
# no API calls and modifies nothing.
#
# Usage:
#   ./compare-snapshots.sh <older-snapshot-dir> <newer-snapshot-dir>
#
# Each argument is a directory containing raw/ (as produced by collect-snapshot.sh).

set -uo pipefail

OLD="${1:-}"; NEW="${2:-}"
[ -z "$OLD" ] || [ -z "$NEW" ] && { echo "Usage: $0 <older-snapshot-dir> <newer-snapshot-dir>" >&2; exit 1; }
for d in "$OLD" "$NEW"; do
  [ -d "$d/raw" ] || { echo "ERROR: $d/raw not found" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

hr(){ printf '\n%s\n' "── $1 ${2:-}"; }
# tsv_diff <label> <file-relative-path> <jq-program>
tsv_diff() {
  local label="$1" rel="$2" prog="$3" a b
  a=$(mktemp); b=$(mktemp)
  jq -r "$prog" "$OLD/raw/$rel" 2>/dev/null | sort > "$a"
  jq -r "$prog" "$NEW/raw/$rel" 2>/dev/null | sort > "$b"
  if diff -q "$a" "$b" >/dev/null 2>&1; then
    printf '  %-34s unchanged\n' "$label"
  else
    printf '  %-34s CHANGED\n' "$label"
    diff "$a" "$b" | grep -E '^[<>]' | sed 's/^</    removed: /; s/^>/    added:   /' | head -25
  fi
  rm -f "$a" "$b"
}

echo "Comparing assessment snapshots"
echo "  before: $OLD"
echo "  after:  $NEW"

hr "Organization & identity"
tsv_diff "members and roles"      "members.json"              '.results[]? | [.name, .role_name] | @tsv'
tsv_diff "API tokens"             "api-tokens.json"           '.results[]? | [.name, .role_name] | @tsv'
tsv_diff "scoped policy tokens"   "policy-tokens.json"        '.results[]? | .name'
tsv_diff "SSO connections"        "sso.json"                  '.results[]? | .connection_name'
tsv_diff "alert receivers"        "alert-receivers.json"      '.results[]? | [.name, .type, (.enabled|tostring)] | @tsv'
tsv_diff "alert rules"            "alert-rules.json"          '.results[]? | [.name, (.severity//"-"), (.enabled|tostring)] | @tsv'
tsv_diff "webhooks"               "webhooks.json"             '.results[]? | [.kind, (.enabled|tostring), ((.events//[])|join(","))] | @tsv'
tsv_diff "container registries"   "container-registries.json" '.results[]? | [.kind, .name] | @tsv'
# SC-24: the credential TYPE and the clusters it carries. Never the access_key_id.
tsv_diff "cloud credentials"      "cloud-credentials.json" \
  '.results[]? | [.credential.name, .credential.object_type, ((.clusters//[])|map(.name)|sort|join(","))] | @tsv'
# SC-26: an invitation appearing or disappearing is an access change.
tsv_diff "pending invitations"    "pending-invitations.json"  '.results[]? | [.email, .role, .invitation_status] | @tsv'

hr "Clusters"
tsv_diff "cluster inventory"      "clusters.json" \
  '.results[]? | [.name, .cloud_provider, .region, .version, .instance_type, "nodes:\(.min_running_nodes)-\(.max_running_nodes)", "prod:\(.production)", "obs:\(.metrics_parameters.enabled // false)", "keda:\(.keda.enabled // false)", "ssh_keys:\((.ssh_keys//[])|length)"] | @tsv'
tsv_diff "cluster status"         "cluster-status.json" \
  '.results[]? | [.cluster_id, .status, (.is_deployed|tostring), (.next_k8s_available_version // "current")] | @tsv'

for cdir in "$NEW"/raw/cluster/*/; do
  [ -d "$cdir" ] || continue
  cid=$(basename "$cdir")
  [ -f "$OLD/raw/cluster/$cid/advanced-settings.json" ] || { echo "  cluster $cid — new since last run"; continue; }
  a=$(mktemp); b=$(mktemp)
  jq -S 'to_entries|map(select(.key|startswith("_")|not))|from_entries' "$OLD/raw/cluster/$cid/advanced-settings.json" > "$a" 2>/dev/null
  jq -S 'to_entries|map(select(.key|startswith("_")|not))|from_entries' "$cdir/advanced-settings.json"           > "$b" 2>/dev/null
  if ! diff -q "$a" "$b" >/dev/null 2>&1; then
    printf '  cluster %s advanced settings CHANGED\n' "${cid:0:8}"
    jq -s -r '.[0] as $o | .[1] as $n
      | ($o+$n|keys_unsorted|unique)[]
      | select(($o[.]|tostring) != ($n[.]|tostring))
      | "    \(.): \($o[.]|tostring) -> \($n[.]|tostring)"' "$a" "$b" 2>/dev/null | head -20
  fi
  rm -f "$a" "$b"
done

hr "Environments & services"
# cluster_id and project matter: an environment that keeps its name but moves cluster has
# changed its isolation and production topology, and must not diff as unchanged.
tsv_diff "environments"           "environments.json" '.results[]? | [.mode, .name, (.cluster_id // "-"), (.project.id // "-")] | @tsv'
tsv_diff "service inventory"      "services.json"     '.results[]? | [.environment_name, .service_type, .name] | @tsv'

# Per-environment service configuration — the fields findings are built on.
SVC_PROG='.results[]? | select(.service_type=="APPLICATION" or .service_type=="CONTAINER")
  | [.name, "min=\(.min_running_instances)", "max=\(.max_running_instances)",
     "cpu=\(.cpu)", "mem=\(.memory)",
     "ready=\(.healthchecks.readiness_probe.type // {} | to_entries | map(select(.value!=null)) | .[0].key // "NONE")",
     "live=\(.healthchecks.liveness_probe.type // {} | to_entries | map(select(.value!=null)) | .[0].key // "NONE")",
     "public=\([.ports[]? | select(.publicly_accessible==true)] | length)"] | @tsv'
DB_PROG='.results[]? | select(.service_type=="DATABASE")
  | [.name, .mode, .accessibility, (.disk_encrypted|tostring), "storage=\(.storage)"] | @tsv'

for edir in "$NEW"/raw/env/*/; do
  [ -f "$edir/services.json" ] || continue
  eid=$(basename "$edir")
  ename=$(jq -r '.name // "?"' "$edir/environment.json" 2>/dev/null)
  if [ ! -f "$OLD/raw/env/$eid/services.json" ]; then
    printf '  env %-26s NEW since last run\n' "${ename:0:26}"; continue
  fi
  for pair in "services:$SVC_PROG" "databases:$DB_PROG"; do
    lbl="${pair%%:*}"; prog="${pair#*:}"
    a=$(mktemp); b=$(mktemp)
    jq -r "$prog" "$OLD/raw/env/$eid/services.json" 2>/dev/null | sort > "$a"
    jq -r "$prog" "$edir/services.json"             2>/dev/null | sort > "$b"
    if ! diff -q "$a" "$b" >/dev/null 2>&1; then
      printf '  env %-22s %-10s CHANGED\n' "${ename:0:22}" "$lbl"
      diff "$a" "$b" | grep -E '^[<>]' | sed 's/^</      before: /; s/^>/      after:  /' | head -14
    fi
    rm -f "$a" "$b"
  done
done

hr "Per-service advanced settings (resilience-relevant keys)"
KEYS='["deployment.antiaffinity.pod","deployment.topology_spread.zone","deployment.update_strategy.type","deployment.termination_grace_period_seconds","security.read_only_root_filesystem","security.automount_service_account_token","network.ingress.force_ssl_redirect","hpa.cpu.average_utilization_percent"]'
changed=0
for sdir in "$NEW"/raw/service/*/; do
  sid=$(basename "$sdir")
  [ -f "$sdir/advanced-settings.json" ] || continue
  [ -f "$OLD/raw/service/$sid/advanced-settings.json" ] || continue
  out=$(jq -s -r --argjson keys "$KEYS" '.[0] as $o | .[1] as $n
    | $keys[] | select(($o[.]|tostring) != ($n[.]|tostring))
    | "    \(.): \($o[.]|tostring) -> \($n[.]|tostring)"' \
    "$OLD/raw/service/$sid/advanced-settings.json" "$sdir/advanced-settings.json" 2>/dev/null)
  if [ -n "$out" ]; then
    printf '  service %s\n%s\n' "${sid:0:8}" "$out"
    changed=$((changed+1))
  fi
done
[ "$changed" -eq 0 ] && echo "  no resilience-relevant advanced settings changed"

hr "Variables & secrets" "(KEYS ONLY — values are never compared or printed)"
for edir in "$NEW"/raw/env/*/; do
  eid=$(basename "$edir"); ename=$(jq -r '.name // "?"' "$edir/environment.json" 2>/dev/null)
  [ -f "$OLD/raw/env/$eid/variables.json" ] || continue
  for f in variables secret-keys; do
    a=$(mktemp); b=$(mktemp)
    jq -r '.results[]? | [.key, .scope, .variable_type] | @tsv' "$OLD/raw/env/$eid/$f.json" 2>/dev/null | sort > "$a"
    jq -r '.results[]? | [.key, .scope, .variable_type] | @tsv' "$edir/$f.json"              2>/dev/null | sort > "$b"
    if ! diff -q "$a" "$b" >/dev/null 2>&1; then
      printf '  env %-22s %-12s CHANGED\n' "${ename:0:22}" "$f"
      diff "$a" "$b" | grep -E '^[<>]' | sed 's/^</      removed: /; s/^>/      added:   /' | head -12
    fi
    rm -f "$a" "$b"
  done
done

hr "Change attribution" "(from the newer snapshot's audit events)"
if [ -f "$NEW/raw/events.ndjson" ]; then
  echo "  origin of config changes in the newer window:"
  jq -r 'select(.event_type=="CREATE" or .event_type=="UPDATE" or .event_type=="DELETE") | .origin' \
    "$NEW/raw/events.ndjson" 2>/dev/null | sort | uniq -c | sort -rn | sed 's/^/    /'
  echo "  most-changed targets:"
  jq -r 'select(.event_type=="UPDATE" or .event_type=="DELETE")
    | [(.target_type//"-"), (.target_name//"-")] | @tsv' "$NEW/raw/events.ndjson" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'
else
  echo "  no events.ndjson in the newer snapshot"
fi

hr "Summary"
o_svc=$(jq -r '.results|length' "$OLD/raw/services.json" 2>/dev/null || echo 0)
n_svc=$(jq -r '.results|length' "$NEW/raw/services.json" 2>/dev/null || echo 0)
o_env=$(jq -r '.results|length' "$OLD/raw/environments.json" 2>/dev/null || echo 0)
n_env=$(jq -r '.results|length' "$NEW/raw/environments.json" 2>/dev/null || echo 0)
printf '  services:     %s -> %s\n' "$o_svc" "$n_svc"
printf '  environments: %s -> %s\n' "$o_env" "$n_env"
echo ""
echo "Re-run the CL/TP/RL/BP/SC/VS/DL/LG/OP/CE/DR checks against the newer snapshot to"
echo "score it. Because check IDs and the scoring formula are stable, the two scores are"
echo "directly comparable — report the delta per pillar, and name which findings closed."
