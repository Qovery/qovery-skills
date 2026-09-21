## Phase 2: Cluster Assessment (CL checks)

The cluster is the floor everything else stands on. A service configured perfectly on
a single-node, unmonitored cluster is still one node failure from an outage.

Data sources: `clusters.json`, `cluster-status.json`,
`cluster/<id>/advanced-settings.json`, `cluster/<id>/cloud-provider-info.json`,
`default/cluster-advanced-settings.json`.

**Severity convention:** the severity listed is for a cluster carrying production
workloads. For a cluster that only hosts dev/preview environments, drop it by two
levels (Critical→Medium, High→Low, Medium→Info).

---

### CL-01 — Every cluster is in a healthy, current state

**Severity:** Critical

```bash
jq -r '.results[] | [.cluster_id, .status, .is_deployed, .last_deployment_date,
  (.reason // "-"), (.cluster_lock.reason // "-")] | @tsv' raw/cluster-status.json
jq -r '.results[] | [.name, .status, .deployment_status] | @tsv' raw/clusters.json
```

**Fails when:** `status` is any error state (`DEPLOYMENT_ERROR`, `BUILD_ERROR`,
`STOP_ERROR`, `DELETE_ERROR`, `RESTART_ERROR`, `INVALID_CREDENTIALS`) or `deployment_status` shows the
cluster is out of date with its desired configuration.

**Why it matters:** a cluster stuck in an error state means Qovery cannot reconcile
infrastructure changes — node pool updates, add-on upgrades, and security patches
silently stop landing.

**Recommendation:** resolve the cluster error before any other remediation; everything
downstream depends on a reconciling cluster.

---

### CL-02 — Kubernetes version is inside the provider's supported window

**Severity:** High

The cluster status endpoint reports whether a newer version is available, so this
check does not depend on an external version table:

```bash
jq -r '.results[] | [.cluster_id, .next_k8s_available_version // "up to date"] | @tsv' \
  raw/cluster-status.json
jq -r '.results[] | [.name, .cloud_provider, .region, .kubernetes, .version] | @tsv' raw/clusters.json
```

**Fails when**, using the minor-version distance between `version` and
`next_k8s_available_version`:

| Distance | Result |
|---|---|
| 0 (`next_k8s_available_version` unset or equal) | **PASS** |
| 1 minor version | **PASS** — one release behind is normal operating practice |
| 2 minor versions | **PARTIAL**, Medium. An upgrade should be scheduled |
| 3 or more | **FAIL**, High. Most providers support three or four minor versions, so this is at or past the edge of the window |
| running version is past the provider's published end-of-support date | **FAIL**, Critical, whatever the distance |

```bash
# Minor-version distance, computed rather than eyeballed.
jq -r '.results[] | select(.next_k8s_available_version != null)
  | [.cluster_id, .version, .next_k8s_available_version,
     (((.next_k8s_available_version | split(".")[1] | tonumber)
       - (.version | split(".")[1] | tonumber)) | tostring)] | @tsv' \
  raw/cluster-status.json | column -t
```

Record the distance in the finding, so a reassessment can see it move. The end-of-support
row is the one input this cannot compute: check the provider's support matrix at assessment
time and **cite the URL and the date you read it** — that date is what keeps the document
honest when it is read weeks later.

Do **not** hardcode a "latest" version into the report. Quote the version found and the
`next_k8s_available_version` the API returned; where end-of-support matters, check the
provider's current support matrix (EKS / GKE / AKS / Kapsule release calendar) at
assessment time and cite the source URL — so the document stays accurate when it is read
weeks later.

**Why it matters:** an unsupported control plane stops receiving security patches, and
extended-support tiers are billed at a premium on most providers.

**Recommendation:** plan a rolling upgrade path; Qovery performs cluster upgrades
without rebuilding the cluster.

---

### CL-03 — Production workloads run on a cluster flagged `production: true`

**Severity:** Medium

```bash
jq -r '.results[] | [.name, .production, .is_demo, .is_default] | @tsv' raw/clusters.json
```

**Fails when:** a cluster hosting `PRODUCTION`-mode environments has
`production: false`.

**Why it matters:** the flag drives Qovery's guardrails and defaults, and it is the
signal the team reads when deciding whether a change is safe.

---

### CL-04 — No production workload on a demo cluster

**Severity:** Critical

```bash
jq -r '.results[] | select(.is_demo == true) | .id' raw/clusters.json
# cross-reference with environments on that cluster
jq -r --arg c "<clusterId>" '.results[] | select(.cluster_id == $c) | [.name, .mode] | @tsv' raw/environments.json
```

**Fails when:** any `PRODUCTION` or `STAGING` environment sits on `is_demo: true`.

**Why it matters:** demo clusters are ephemeral, unsupported, and carry no
availability expectation.

---

### CL-05 — Production is isolated from development workloads

**Severity:** High

```bash
jq -r '.results[] | [.cluster_id, .mode, .name] | @tsv' raw/environments.json | sort
```

**Fails when:** a cluster hosts both `PRODUCTION` and `DEVELOPMENT`/`PREVIEW`
environments.

**Why it matters:** a runaway dev build or a memory-hungry preview environment evicts
production pods, and the blast radius of a cluster-wide incident now includes revenue.
Separate clusters also separate IAM, network, and audit scope — which is what a SOC 2
or ISO auditor asks about first.

**Recommendation:** a dedicated production cluster. If cost rules that out, at minimum
document the shared-cluster risk and enforce resource limits on every non-prod service.

---

### CL-06 — Production node pool tolerates a node failure

**Severity:** High

```bash
jq -r '.results[] | [.name, .production, .instance_type, .min_running_nodes, .max_running_nodes] | @tsv' raw/clusters.json
```

**Fails when:** `min_running_nodes < 3` on a production cluster.

**Why it matters:** with 2 nodes, losing one removes 50% of capacity and both replicas
of a 2-pod service can be on the failed node. Three nodes let the scheduler spread
across availability zones and survive a single-AZ event.

**Recommendation:** `min_running_nodes: 3` on production, spread across 3 AZs.

---

### CL-07 — Node autoscaling has real headroom

**Severity:** Medium

**Fails when:** `max_running_nodes == min_running_nodes` — the cluster cannot absorb a
traffic spike or a rollout that temporarily doubles pods.

**Why it matters:** during a rolling update the cluster needs room for surge pods. With
no headroom, deployments stall in `Pending` and the rollout blocks.

**Recommendation:** `max_running_nodes` at least 2× `min_running_nodes` on production.
Where Karpenter is available, prefer it for faster, bin-packed scale-out.

---

### CL-08 — Observability is enabled

**Severity:** High

```bash
jq -r '.results[] | [.name,
  (.metrics_parameters.enabled|tostring),
  (.metrics_parameters.configuration.kind // "-"),
  (.metrics_parameters.configuration.resource_profile // "-"),
  # Every field below is a boolean, so `// "-"` is wrong: jq's alternative operator treats
  # `false` as empty and would render an explicitly DISABLED sub-feature exactly like one
  # the API never reported. The difference between "never turned on" and "we could not
  # read it" is the whole finding here — test for null instead.
  "ha=\(.metrics_parameters.configuration.high_availability | if . == null then "not-reported" else tostring end)",
  "alerting=\(.metrics_parameters.configuration.alerting.enabled | if . == null then "not-reported" else tostring end)",
  "cloudwatch=\(.metrics_parameters.configuration.cloud_watch_export_config.enabled | if . == null then "not-reported" else tostring end)",
  "netmon=\(.metrics_parameters.configuration.internal_network_monitoring.enabled | if . == null then "not-reported" else tostring end)"] | @tsv' \
  raw/clusters.json | column -t
```

**Credit an external solution when one is deployed.** Qovery's own metrics stack being off
is not the same as the estate being unmonitored, and reporting it that way is a false
finding. Look for a third-party platform before scoring:

```bash
# Keep the environment, its cluster, and whether the key is a SECRET or a plain variable.
# An agent in a development environment does not instrument a production cluster, and a
# platform name in a plain variable is not the same evidence as its API key held as a secret.
for d in raw/env/*/; do
  E=$(jq -r '.name' "$d/environment.json"); M=$(jq -r '.mode' "$d/environment.json")
  C=$(jq -r '.cluster_id' "$d/environment.json")
  jq -r --arg e "$E" --arg m "$M" --arg c "$C" '.results[]?
    | select(.service_type=="HELM" or .service_type=="CONTAINER")
    # Anchored on a word boundary: an unanchored substring match credits any service whose
    # name merely CONTAINS a platform word — `hotel` matches `otel`, `elasticsearch-api`
    # matches `elastic`, and a plain application then certifies its own cluster as observed.
    | select(.name|test("(^|[^a-z0-9])(datadog|newrelic|new-relic|grafana|dynatrace|splunk|honeycomb|signoz|otel|opentelemetry|fluent-?bit|elastic-agent|apm-server)([^a-z0-9]|$)";"i"))
    | [$e,$m,$c[0:8],"agent",.name] | @tsv' "$d/services.json"
  jq -r --arg e "$E" --arg m "$M" --arg c "$C" '.results[]?.key
    | select(test("^(DD_|DATADOG|NEW_?RELIC|OTEL_|SENTRY|GRAFANA|DYNATRACE|SPLUNK|HONEYCOMB|SIGNOZ)";"i"))
    | [$e,$m,$c[0:8],"secret-key",.] | @tsv' "$d/secret-keys.json" 2>/dev/null
  jq -r --arg e "$E" --arg m "$M" --arg c "$C" '.results[]?.key
    | select(test("^(DD_|DATADOG|NEW_?RELIC|OTEL_|SENTRY|GRAFANA|DYNATRACE|SPLUNK|HONEYCOMB|SIGNOZ)";"i"))
    | [$e,$m,$c[0:8],"plain-var",.] | @tsv' "$d/variables.json"
done | sort -u | column -t -s$'\t'
```

**Credit the check only for a cluster that actually has an agent.** Match the `cluster_id`
column against the cluster being scored. An agent deployed only in a non-production
environment leaves the production cluster uninstrumented, and crediting it there would be a
false pass in the opposite direction from the one this paragraph is warning about.

An agent deployed on the cluster plus its API key held as a secret is **coverage** — score
the check accordingly and name the platform in the evidence. What the missing Qovery-native
stack actually costs is narrower and worth stating precisely: `qovery-optimize` and the
measured `CE-*` checks read Qovery's metrics, not the third party's, so those stay UNKNOWN
with the reason "measured in <platform>, not readable through the Qovery API" rather than
"not measured".



**Fails when:** `metrics_parameters.enabled` is `false` or absent on a production cluster.

**Read the nested configuration too — it carries three findings the top-level flag hides:**

- `alerting.enabled: false` while metrics are on is the **most reliable evidence for
  `DL-05`**. It says the observability stack is deployed but nothing is wired to alert, which
  is stronger than inferring it from an empty alert-rules list.
- `high_availability: false` on a production cluster means the monitoring stack itself is a
  single point of failure — it goes down with the incident you need it for.
- `cloud_watch_export_config` and `internal_network_monitoring` being off are relevant to
  `SC-19` retention and network-forensics findings.

**Why it matters:** without metrics there is no right-sizing, no capacity planning, no
alert thresholds, and no post-incident evidence. It also disables Qovery's KRR-based
recommendations.

**Recommendation:** enable Qovery observability; then `qovery-optimize` can produce
P99-based, OOM-aware resource recommendations instead of guesses.

---

### CL-09 — KEDA is available where workloads are event-driven

**Severity:** Info (Medium if queue-backed workloads exist)

```bash
jq -r '.results[] | [.name, .keda.enabled] | @tsv' raw/clusters.json
```

**Why it matters:** CPU-based HPA cannot scale a worker that is blocked on a queue.
If the inventory shows consumers/workers, KEDA is the difference between a backlog
draining and a backlog growing.

---

### CL-10 — Log and image retention are deliberate

**Severity:** Medium (High under a compliance obligation)

```bash
jq '{loki_weeks: ."loki.log_retention_in_week",
     eks_cloudwatch_days: ."aws.cloudwatch.eks_logs_retention_days",
     registry_image_retention: ."registry.image_retention_time"}' \
  raw/cluster/<clusterId>/advanced-settings.json
```

**Fails when:** retention is left at the default while the customer has a stated
compliance requirement, or image retention is unbounded.

**Why it matters:** too short and you cannot investigate an incident from last month;
too long and you pay to store noise. Unbounded image retention grows registry cost
forever.

---

### CL-11 — Static egress IP configured when partners allow-list

**Severity:** Info (High if the customer integrates with IP-allow-listed partners —
common in fintech, banking, payments)

```bash
jq '{static_ip: ."qovery.static_ip_mode"}' raw/cluster/<clusterId>/advanced-settings.json
jq -r '.results[] | .features[]? | [.id, .value_object.value] | @tsv' raw/clusters.json
```

**Why it matters:** without a stable NAT egress IP, a partner's firewall rule breaks
every time a node is replaced.

---

### CL-12 — Ingress controller is itself highly available

**Severity:** High

**Read the ingress that is actually deployed.** A cluster can run nginx, the Envoy-based
API Gateway, or both, and the nginx settings stay populated after nginx is removed. Citing
`nginx.hpa.min_number_instances` on a cluster with `k8s.remove_nginx: true` reports on a
component that is not there — and would pass a cluster whose real gateway runs one replica.

```bash
jq -r '.results[] | . as $c | .advanced_settings as $a
  | ($a["k8s.remove_nginx"] // false) as $nonginx
  | ($a["k8s.use_api_gateway"] // false) as $gw
  | [ $c.name,
      (if $nonginx then "nginx REMOVED" else "nginx present" end),
      (if $gw then "api-gateway ON" else "api-gateway off" end),
      "nginx.min=" + ($a["nginx.hpa.min_number_instances"]|tostring),
      "envoy.min=" + ($a["envoy.hpa.min_number_instances"]|tostring),
      "envoy.controller=" + ($a["envoy.gateway_controller.replicas"]|tostring),
      "SCORE ON -> " + (if $nonginx or $gw then "envoy" else "nginx" end)
    ] | @tsv' raw/clusters.json | column -t -s$'\t'
```

**Fails when:** the minimum replica count of the ingress **in use** is below 2 on a
production cluster — `envoy.hpa.min_number_instances` and `envoy.gateway_controller.replicas`
where the API Gateway is on, `nginx.hpa.min_number_instances` where nginx still serves.
Where both are deployed, both must hold.

**Why it matters:** every public request crosses the ingress controller. One replica
means a single pod restart drops all inbound traffic — the most common cause of a
"the whole platform went down for 30 seconds" report.

---

### CL-13 — Cluster advanced settings are a deliberate diff from defaults

**Severity:** Info

```bash
bash templates/scripts/cluster-settings-sweep.sh <snapshotDir>
```

A cluster carries roughly 120 advanced settings and the named checks read about twenty of
them. The sweep prints the subset that decides reliability or security outcomes, per cluster,
so none of them stays invisible merely because no check happens to name it — and it flags any
setting where the customer's own clusters **disagree**.

**Divergence between a customer's clusters is the signal worth chasing, not divergence from a
default.** Vendor defaults move between releases, so a hardcoded defaults table produces
confident wrong findings; two production clusters that disagree on a security setting is a
finding whatever the default happens to be. Where they diverge, ask which one is intended —
usually one was configured deliberately and the other was never revisited.

Report the sweep as an observation and let the named checks carry the verdicts. Do not paste
all 120 settings into a customer document: that is noise wearing the costume of thoroughness.

---

### CL-14 — Node disk sizing and storage class are appropriate

**Severity:** Medium

```bash
jq -r '.results[] | [.name, .disk_size, .disk_iops, .disk_throughput] | @tsv' raw/clusters.json
jq '{fast_ssd: ."storageclass.fast_ssd"}' raw/cluster/<clusterId>/advanced-settings.json
```

**Why it matters:** node disk pressure evicts pods, and IOPS-starved volumes show up as
mysterious application latency long before anyone suspects the disk.

---

### CL-15 — Cluster credentials are valid and cloud provider info is current

**Severity:** Critical

```bash
jq -r '.results[] | select(.status == "INVALID_CREDENTIALS") | .name' raw/clusters.json
jq '.' raw/cluster/<clusterId>/cloud-provider-info.json
```

**Why it matters:** expired or rotated cloud credentials silently block every
infrastructure operation until someone tries to deploy during an incident.

---

### CL-16 — Cluster changes are applied, not pending

**Severity:** Medium

```bash
jq -r '.results[0:5][] | [.identifier.execution_id, .status, .total_duration] | @tsv' \
  raw/cluster/<clusterId>/deployment-history.json
```

**Fails when:** the most recent cluster deployment failed, or the cluster has pending
configuration never rolled out.

**Why it matters:** a cluster whose last infrastructure change failed is running a
configuration nobody reviewed.

---

### CL-17 — Overcommit and control-plane redundancy are deliberate

**Severity:** High (Critical on a production cluster running latency-sensitive workloads)

```bash
jq -r '.results[] | [.name,
  "cpu_overcommit=" + (.advanced_settings["allow_service_cpu_overcommit"]|tostring),
  "ram_overcommit=" + (.advanced_settings["allow_service_ram_overcommit"]|tostring),
  "metrics_server_replicas=" + (.advanced_settings["aws.metrics_server.replicas"]|tostring),
  "loki_mode=" + (.advanced_settings["loki.deployment_mode"] // "-"),
  "production=" + (.production|tostring)] | @tsv' raw/clusters.json | column -t -s$'\t'
```

**Fails when:** `allow_service_ram_overcommit` is true on a production cluster, or
`aws.metrics_server.replicas` is 1 where autoscaling is relied on.

**Memory overcommit and CPU overcommit are not the same risk.** CPU is compressible — a pod
exceeding its request is throttled, which costs latency. Memory is not: a node whose pods
collectively exceed real memory kills something, and the kernel chooses, not the scheduler.
Permitting RAM overcommit on a production cluster trades an explicit scheduling failure,
which is visible and fixable, for an OOM kill under load, which lands on whichever pod
happened to allocate last. Correlate with `LG-02` — if the logs already show `OOMKilled`,
this setting is the mechanism.

**metrics-server is the dependency nobody lists.** Every HPA reads from it. A single replica
means a node event stops all autoscaling until it reschedules, and because nothing errors the
symptom arrives a day later as "the platform did not scale during the spike". On a cluster
where `RL-02` shows real autoscaling ranges, a single-replica metrics-server is the thing
that quietly disarms them.

**Do not report either as a finding on a non-production cluster** — overcommit is a
legitimate way to pack a development cluster, and that is usually the intent.

---

### CL-18 — Idle node capacity is reclaimed, not merely provisioned

**Severity:** Medium (High where the production pool is both over-provisioned and
consolidation is off, because the two compound)

```bash
# Karpenter's node-pool parameters live in the cluster `features` array. Dump the whole
# value rather than reaching through a fixed path: the shape carries fields this assessment
# does not model, and a hardcoded path that misses returns null — which reads exactly like
# "consolidation is disabled" and would turn a data gap into a finding.
jq -r '.results[] | select(.production == true)
  | [.name, .instance_type, "\(.min_running_nodes)-\(.max_running_nodes)",
     ([.features[]? | select((.id // "") | test("karpenter";"i")) | .value_object.value] | tostring)]
  | @tsv' raw/clusters.json | column -t -s$'\t'

# Then read the consolidation block out of whatever nesting it arrived in:
jq -r '.results[] | select(.production == true) | .name as $n
  | [.features[]? | .value_object.value? | .. | objects | select(has("consolidation"))]
  | if length == 0 then "\($n)\tconsolidation=not-reported"
    else "\($n)\tconsolidation=\(.)" end' raw/clusters.json
```

**Fails when:** a production node pool has consolidation disabled *and* the pool is running
materially more capacity than the workloads request. Either alone is not the finding —
consolidation is legitimately switched off on clusters with workloads that cannot tolerate
eviction, and a pool with headroom is what `CL-07` asks for.

**Why it matters:** without consolidation, nodes that scaled out for a spike stay allocated
after the spike drains. The pool ratchets upward — it never comes back down — so the cluster
converges on its historical peak as its permanent floor. The symptom is a stable node pool
with several nodes at a token utilization and no mechanism that will ever remove them, and
it is invisible on the Qovery bill because it lands on the cloud provider's.

**Never recommend a capacity reduction from a point-in-time reading.** A snapshot showing
nodes at 10% is a snapshot of *this minute*, and a pool sized for a nightly batch window or
a weekly peak looks identical to a pool that is simply too big. A reduction recommendation
requires utilization **over time**; without it this check resolves `UNKNOWN`, with the
reason stated, and the report says the pool *appears* over-provisioned and names the data
needed to confirm it. That is a genuinely useful finding — it is not the same sentence as
"shrink the pool", and the difference is the customer's next outage.

**Where the time series comes from, in order of preference:**

| Source | How |
|---|---|
| Qovery cluster observability (`CL-08`) | The metrics stack scrapes **pod and container** series. Whether **node**-level utilization is exposed to the customer varies by stack configuration — check before asserting it, and if node series are absent, say so plainly and record it as a platform gap rather than silently falling back to requests |
| **Phase 6f** — the customer's own platform | CloudWatch Container Insights, Datadog, Grafana. If they run one, node utilization over weeks is already there and this is the shortest path |
| Requested resources (`CE-11`) | The fallback, and a weak one: requests are what services *asked for*, not what they used. Sufficient to show a pool that cannot possibly be full; never sufficient to size one down |

**Recommendation:** enable consolidation on the pools whose workloads tolerate
rescheduling — which is the set where `RL-01`, `RL-10` and `RL-11` already pass, the same
set `CE-10` identifies for spot. Exclude the stateful and singleton workloads explicitly
rather than disabling consolidation pool-wide to protect them. Pair with `CE-11`; report
the waste once, under Cost, and cross-reference it here.
