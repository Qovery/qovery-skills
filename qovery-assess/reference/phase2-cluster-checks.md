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
  (.reason // "-"), (.cluster_lock.lock_reason // "-")] | @tsv' raw/cluster-status.json
jq -r '.results[] | [.name, .status, .deployment_status] | @tsv' raw/clusters.json
```

**Fails when:** `status` is any error state (`DEPLOYMENT_ERROR`, `BUILD_ERROR`,
`STOP_ERROR`, `DELETE_ERROR`, `INVALID_CREDENTIALS`) or `deployment_status` shows the
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

**Fails when:** `next_k8s_available_version` is set and the cluster is several minor
versions behind it, or the provider has announced end-of-support for the running version.

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
  "ha=\(.metrics_parameters.configuration.high_availability // "-")",
  "alerting=\(.metrics_parameters.configuration.alerting.enabled // "-")",
  "cloudwatch=\(.metrics_parameters.configuration.cloud_watch_export_config.enabled // "-")",
  "netmon=\(.metrics_parameters.configuration.internal_network_monitoring.enabled // "-")"] | @tsv' \
  raw/clusters.json | column -t
```

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

```bash
jq '{min: ."nginx.hpa.min_number_instances", max: ."nginx.hpa.max_number_instances",
     cpu_threshold: ."nginx.hpa.cpu_utilization_percentage_threshold",
     cpu_limit: ."nginx.vcpu.limit_in_milli_cpu", mem_limit: ."nginx.memory.limit_in_mib"}' \
  raw/cluster/<clusterId>/advanced-settings.json
```

**Fails when:** `nginx.hpa.min_number_instances < 2` on a production cluster.

**Why it matters:** every public request crosses the ingress controller. One replica
means a single pod restart drops all inbound traffic — the most common cause of a
"the whole platform went down for 30 seconds" report.

---

### CL-13 — Cluster advanced settings are a deliberate diff from defaults

**Severity:** Info

```bash
jq -s '.[0] as $cur | .[1] as $def
  | $cur | to_entries | map(select(.value != $def[.key])) | from_entries' \
  raw/cluster/<clusterId>/advanced-settings.json raw/default/cluster-advanced-settings.json
```

List every setting that diverges from the Qovery default. Each divergence should have
a reason someone on the team can state. Undocumented drift is how clusters become
un-reproducible.

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
