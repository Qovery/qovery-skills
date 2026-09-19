## Phase 6d: Cost Efficiency & Measured Waste (CE checks)

Two halves. `CE-01`–`CE-06` are structural and readable from configuration alone.
`CE-07`–`CE-11` are **measured**, and they need cluster observability — without it they are
`UNKNOWN`, and saying so is itself the most valuable finding in this phase.

> **Never invent a savings figure.** A number in a customer document will be quoted back.
> Quote measured utilisation and the allocation it is measured against; leave the euro
> amounts to `qovery-optimize`, which computes them from real consumption and current cloud
> pricing. "Allocated 2 vCPU, P95 usage 180m" is evidence. "Save ~€400/month" without a
> measurement behind it is a guess with a currency symbol.

---

## Structural (readable without metrics)

### CE-01 — Non-production environments are scheduled

**Severity:** Medium — evidence as in `TP-07`. Report once, in whichever pillar the team
will act on.

A weekday 08:00–19:00 window runs 55 of 168 hours: roughly two thirds of that cluster's
compute, with no production impact. Check whether a schedule exists but is **inactive** —
`start_time`/`stop_time` populated with `auto_stop: false` means someone configured the
intent and never switched it on.

### CE-02 — Capacity is elastic

**Severity:** Medium — services with `min == max` (`RL-02`) pay peak cost at the trough.

### CE-03 — Sizing comes from measurement

**Severity:** Medium — requires `CL-08`. Without observability this is `UNKNOWN`, and the
recommendation is to enable it, not to resize.

### CE-04 — No abandoned environments

**Severity:** Medium — evidence as in `TP-11`.

### CE-05 — Managed databases earn their cost

**Severity:** Low

```bash
jq -r '.results[] | select(.service_type=="DATABASE") | [.name, .mode, (.instance_type // "-")] | @tsv' \
  raw/env/<devEnvId>/services.json
```

Managed databases in short-lived development environments pay for multi-AZ and automated
backup nobody needs there. The inverse of `RL-16`.

### CE-06 — Spend is visible

**Severity:** Low

```bash
jq '{plan, cost}' raw/current-cost.json
jq -r '.results[] | [.name, .estimated_cloud_provider_cost] | @tsv' raw/clusters.json
```

**Expect these to be empty.** In testing across two organizations (Enterprise and Business
plans), `GET /organization/{orgId}/currentCost` returned `total_in_cents: 0`,
`estimated_cloud_provider_cost` was `0` on every cluster, and
`GET /organization/{orgId}/cluster/{clusterId}/currentCost` returned **HTTP 501 Not
Implemented**. Qovery does not surface cloud spend through these endpoints today.

**So do not put a cost figure in the report** unless the customer supplies one. What you
*can* report, and what is genuinely useful, is the **allocation** these findings act on:

```bash
# Requested capacity per environment — the denominator for any later cost conversation
for d in raw/env/*/; do
  N=$(jq -r .name "$d/environment.json")
  jq -r --arg n "$N" '[.results[] | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
    | {c:(.cpu*.min_running_instances), m:(.memory*.min_running_instances)}]
    | [$n, "cpu=\([.[].c]|add)m", "mem=\([.[].m]|add)MB", "services=\(length)"] | @tsv' "$d/services.json"
done | column -t
```

Frame savings as **proportions of running time or capacity**, which are defensible from
configuration alone — "68 non-production services run 168 hours a week where the configured
window is 55" — and leave currency to `qovery-optimize` and the customer's own cloud bill.

---

## Measured waste (requires `CL-08` observability)

> **`GET /clusters/{id}/analysis` returns the analysis *metadata* — id, status, timestamps —
> not the P95 and peak figures these checks need, and `GET /cluster/{id}/metrics` returned
> an empty `metrics` string for every query shape tested. So `CE-03`, `CE-07`, `CE-08`,
> `CE-09` and `CE-11` resolve to **UNKNOWN by default**, excluded from scoring and disclosed
> in the coverage line. They become answerable in exactly two ways: the customer runs
> `qovery-optimize`, which reads the analysis result server-side, or Phase 6f reads the
> figures from an external observability platform the customer already has. Never estimate
> the numbers from instance types or request settings — an invented waste figure is the
> fastest way to lose a cost conversation.

First confirm metrics are available:

```bash
jq -r '.results[] | [.name, (.metrics_parameters.enabled|tostring)] | @tsv' raw/clusters.json
```

**If `false` on every cluster:** mark `CE-07`–`CE-09` and `CE-11` as `UNKNOWN`, exclude them
from scoring, and make this the headline of the cost section:

> "Resource waste could not be measured because cluster observability is disabled. Enabling
> it is the prerequisite for any credible sizing or savings work — it is a cluster setting,
> not a project, and it unlocks P99-based, OOM-aware recommendations."

**If `true`**, the supported measurement path is Qovery's **server-side cluster analysis**
(KRR), which applies P99 and OOM-aware logic for you:

```bash
# Read analyses that have ALREADY been run — this is read-only and safe here:
jq -r 'if ._unreadable then "unreadable" else (.results[]? | [.id, .status, .created_at] | @tsv) end' \
  raw/cluster/<clusterId>/analyses.json
```

**If that list is empty, stop and hand off.** Producing a new analysis means *triggering*
one (`qovery cluster analysis cost-recommendation`), and triggering work on a customer's
cluster is outside this skill's read-only contract even though the analysis itself changes
no configuration. Mark `CE-07`–`CE-09` and `CE-11` as `UNKNOWN` and route to
`qovery-optimize`, which owns that step and its confirmation.

> **Do not hand-roll metric queries as a fallback.** `GET /cluster/{clusterId}/metrics` is a
> Thanos-style proxy: `endpoint` and `query` are both **required** (omitting `endpoint`
> returns HTTP 400), and `endpoint` is the upstream API path — `query`, `query_range`,
> `series`, `label/__name__/values`. In testing against a cluster with observability fully
> enabled (`MANAGED_BY_QOVERY`, HA), every shape — instant query, range query, series, label
> listing, with and without `board_short_name` — returned `{"endpoint":"…","metrics":""}`.
> Treat this endpoint as unavailable for assessment purposes unless you have verified
> otherwise on the cluster in front of you, and never present an empty result as "no waste
> found".

### CE-07 — CPU allocation matches real consumption

**Severity:** Medium

Compare allocated `cpu` (millicores) against measured P95, per service:

| Ratio (allocated ÷ P95) | Reading |
|---|---|
| > 4× | Substantial over-allocation — the first place to look |
| 2–4× | Normal headroom for a latency-sensitive service; excessive for a batch worker |
| < 1.2× | Under-allocated — throttling risk, check p99 latency |

Report as a table of the ten largest gaps with both numbers. Do not recommend a specific
new value here — `qovery-optimize` produces those with the safety margins that the
business context calls for.

### CE-08 — Memory allocation matches real consumption

**Severity:** Medium

Same comparison against peak working set. Memory differs from CPU in one important way:
**over-allocation wastes money, under-allocation kills the pod.** Correlate every candidate
with `LG-04` — a service showing `OOMKilled` must never be recommended for a reduction,
however good its average looks.

### CE-09 — Storage is sized to what is used

**Severity:** Medium

```bash
jq -r '.results[] | select(.service_type=="DATABASE") | [.name, .storage, .disk_type] | @tsv' \
  raw/env/<envId>/services.json
jq -r '.results[] | select(((.storage // []) | length) > 0)
  | [.name, ((.storage | map("\(.mount_point):\(.size)GB")) | join(","))] | @tsv' \
  raw/env/<envId>/services.json
jq '{registry_retention: ."registry.image_retention_time"}' raw/cluster/<clusterId>/advanced-settings.json
```

Three distinct sources of storage waste, worth separating: over-provisioned persistent
volumes, database storage far above actual size, and unbounded container-registry retention
which grows forever and is invisible on most cost reviews.

Provisioned volumes only shrink by recreation, so a finding here is usually "right-size at
the next migration", not "change it now". Registry retention is a one-line fix.

### CE-10 — Spot or equivalent capacity on non-production clusters

**Severity:** Medium

```bash
jq -r '.results[] | [.name, .production, .instance_type, .min_running_nodes, .max_running_nodes] | @tsv' \
  raw/clusters.json | column -t
jq -r '.results[] | .features[]? | [.id, .title, (.value_object.value | tostring)] | @tsv' raw/clusters.json
```

**Fails when:** a cluster hosting only development, staging, or preview environments runs
entirely on on-demand capacity.

**Why it matters:** spot / preemptible / low-priority capacity is typically 60–90% cheaper
than on-demand, and the trade-off — nodes can be reclaimed with short notice — is one
non-production can absorb. Karpenter (`instance_type: KARPENTER`) can mix spot and
on-demand with a fallback, so an interruption reschedules rather than fails.

**Where it does *not* apply, and say so:** production, anything stateful with an RWO volume,
single-replica services (`RL-01`), and singleton brokers (`BP-02`) — reclaiming that node is
an outage. Spot works precisely where `RL-01`, `RL-10` and `RL-11` already pass, which is
worth pointing out: the resilience work and the savings work are the same work.

### CE-11 — Nodes are packed, not merely running

**Severity:** Medium

```bash
# Sum of what every service asks for, per environment:
for d in raw/env/*/; do
  N=$(jq -r .name "$d/environment.json")
  jq -r --arg n "$N" '[.results[] | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
    | {c: (.cpu * .min_running_instances), m: (.memory * .min_running_instances)}]
    | [$n, ([.[].c] | add), ([.[].m] | add)] | @tsv' "$d/services.json"
done | column -t
```

Compare total requested CPU and memory with the node pool's capacity
(`min_running_nodes × instance size`). Two failure modes, and they need opposite fixes:

- **Requests far below capacity** — nodes are paid for and idle; either the pool is too
  large or requests are inflated (`CE-07`).
- **Requests near capacity** — no room for a rolling update's surge pods or for a node
  failure. This is a reliability finding wearing a cost costume; pair it with `CL-07`.
