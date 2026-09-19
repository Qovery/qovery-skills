#!/usr/bin/env bash
#
# cluster-settings-sweep.sh — surface the cluster advanced settings that carry assessment
# weight, and flag divergence between a customer's own clusters.
#
# Usage:  ./cluster-settings-sweep.sh <snapshotDir>
#
# A Qovery cluster exposes ~120 advanced settings. Most are tuning knobs with no bearing on
# reliability or security, and a handful decide real outcomes. This prints the handful, per
# cluster, so none of them stays invisible just because no check happens to name it.
#
# It deliberately does NOT diff against a table of vendor defaults: defaults move between
# Qovery releases, and a stale table produces confident wrong findings. Divergence BETWEEN
# the customer's own clusters is the signal that travels — two production clusters that
# disagree on a security setting is a finding regardless of what the default is.

set -uo pipefail
DIR="${1:-.}"
F="$DIR/raw/clusters.json"
[ -f "$F" ] || { echo "ERROR: $F not found" >&2; exit 1; }
jq -e '._unreadable // false' "$F" >/dev/null 2>&1 && { echo "UNREADABLE — report as UNKNOWN, not as absent settings" >&2; exit 1; }

KEYS_SECURITY="
aws.eks.encrypt_secrets_kms_key_arn|K8s Secrets envelope encryption (CMK)|SC-23
k8s.api.allowed_public_access_cidrs|K8s API allow-list|SC-03
aws.eks.ec2.metadata_imds|IMDSv2|SC-13
aws.vpc.enable_s3_flow_logs|VPC flow logs|SC-19
object_storage.enable_logging|Object-storage access logging|SC-19
aws.cloudwatch.eks_logs_retention_days|Control-plane log retention|SC-22
aws.eks.enable_pod_identity_addon|Per-pod cloud identity|SC-12
aws.iam.enable_sso|Cluster IAM SSO|SC-15
aws.iam.enable_admin_group_sync|IAM admin-group sync|SC-16
aws.iam.admin_group|IAM admin group|SC-16
aws.eks.alb_controller.load_balancer_scheme|ALB exposure|SC-04
aws.eks.alb_controller.load_balancer_source_ranges|ALB source allow-list|SC-04
envoy.client_validation.ca_certificates|mTLS client validation|SC-06
database.postgresql.deny_any_access|DB network policy|SC-02
"
KEYS_RELIABILITY="
allow_service_cpu_overcommit|CPU overcommit permitted|CL-17
allow_service_ram_overcommit|RAM overcommit permitted|CL-17
aws.metrics_server.replicas|metrics-server replicas (HPA depends on it)|CL-17
k8s.use_api_gateway|API Gateway in use|CL-12
k8s.remove_nginx|nginx removed|CL-12
nginx.hpa.min_number_instances|nginx ingress min replicas|CL-12
envoy.hpa.min_number_instances|Envoy gateway min replicas|CL-12
envoy.gateway_controller.replicas|Envoy controller replicas|CL-12
loki.deployment_mode|Log store topology|CL-10
loki.log_retention_in_week|Log retention|CL-10
registry.image_retention_time|Image retention|CL-10
cluster.profile|Cluster profile|CL-13
"

names=$(jq -r '[.results[].name] | @tsv' "$F")
emit() {
  local title="$1" list="$2"
  echo "=== $title ==="
  printf '%-52s %-34s %s\n' "SETTING" "MEANS" "VALUE PER CLUSTER"
  echo "$list" | while IFS='|' read -r key label check; do
    [ -z "$key" ] && continue
    vals=$(jq -r --arg k "$key" '[.results[] | .advanced_settings[$k]
             | if . == null then "—"
               elif (type=="array") then (if length==0 then "<empty>" else join(",") end)
               elif (type=="string") then (if length==0 then "<unset>" else . end)
               else tostring end] | @tsv' "$F")
    uniqn=$(printf '%s' "$vals" | tr '\t' '\n' | sort -u | wc -l | tr -d ' ')
    flag=""
    [ "$uniqn" -gt 1 ] && flag="   <<< DIVERGES between clusters"
    printf '%-52s %-34s %s%s\n' "$key" "$label [$check]" "$(printf '%s' "$vals" | tr '\t' '|')" "$flag"
  done
  echo
}

echo "clusters: $(printf '%s' "$names" | tr '\t' ' ')"
echo
emit "SECURITY-RELEVANT" "$KEYS_SECURITY"
emit "RELIABILITY-RELEVANT" "$KEYS_RELIABILITY"

echo "=== coverage ==="
tot=$(jq -r '.results[0].advanced_settings | keys | length' "$F")
echo "  $tot advanced settings exist on a cluster; this sweep surfaces the subset above."
echo "  The remainder are tuning knobs (resource requests for bundled components, Envoy"
echo "  timeouts, EFS modes). Read them only when a finding already points at one —"
echo "  listing all $tot in a customer report is noise, not thoroughness."
