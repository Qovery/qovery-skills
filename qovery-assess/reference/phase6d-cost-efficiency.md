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

A weekday 08:00–19:00 window runs 55 of the week's 168 hours, so scheduling removes the
other 113 — **about two thirds of that cluster's running time**, with no production impact.
State the saved share, not the running share; the two are easy to transpose and a customer
will check this one. Check whether a schedule exists but is **inactive** —
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

First confirm metrics are available — and read the sub-features, not just the top-level
flag, because they are the difference between "no observability" and "observability with a
switch left off":

```bash
jq -r '.results[] | [.name,
  "metrics=\(.metrics_parameters.enabled // false)",
  # `false // "-"` is "-" in jq: the alternative operator treats false as empty, so a
  # sub-feature that is explicitly DISABLED renders identically to one the API did not
  # report. That is the exact distinction this check exists to make — test for null.
  "alerting=\(.metrics_parameters.configuration.alerting.enabled | if . == null then "not-reported" else tostring end)",
  "cloudwatch=\(.metrics_parameters.configuration.cloud_watch_export_config.enabled | if . == null then "not-reported" else tostring end)"] | @tsv' \
  raw/clusters.json | column -t -s$'\t'
```

> **Attribute the gap to the switch, never to the data.** An early adopter can have
> observability enabled from before `alerting` and CloudWatch export existed as options, and
> still be sitting on their defaults years later — the stack is deployed, the sub-features
> were never turned on, and nobody was told. A report that says "metrics could not be
> retrieved" in that situation is wrong in the way that costs the most credibility: the
> reader knows the stack is installed, so the report reads as broken rather than as a
> finding. Write the cause instead — "observability is enabled on `<cluster>`; alerting and
> CloudWatch export are off, which is why `DL-05` has no alert path and why <X> is
> UNKNOWN" — and file it under `CL-08`, which already reads these fields.

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

**Ask whether the volume should exist before asking how big it should be.** A persistent
volume attached to a stateless service is often not durable storage at all — it is scratch
space for uploads, exports or temp files that are buffered locally and then written
somewhere else. Teams reach for a volume because a path needs to be writable, not because
the data needs to survive the pod, and the cost of that reflex is larger than the disk: an
RWO volume pins the pod to a node, blocks `CE-10` spot capacity, and turns `RL-19` into a
single point of failure for data nobody intended to keep.

The assessment cannot tell durable from scratch by reading the mount point, so do not
assert it. Put it to the team as a question per volume — *what is on this, and does it need
to outlive the pod?* — and note that object storage answers the scratch case without the
scheduling constraints. A volume they can explain is a pass; one nobody can account for is
the finding.

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

**Requests are not utilization, and the distinction decides what you may recommend.** The
sum above is what services *asked for*. It bounds the problem in one direction only: a pool
whose requests come to a fraction of its capacity is provably carrying nodes nothing has
claimed, and that is worth reporting on its own. It says nothing about the opposite case —
requests near capacity with real usage far below it is the commonest shape of all, and it
looks identical here.

So separate the two sentences the report can make:

| Evidence available | What the report may say |
|---|---|
| Requests only | "The production pool provisions N nodes; workloads request X% of their capacity. Nodes are running that nothing has scheduled onto." Report it, name the gap, stop there |
| Requests **and** node utilization over time | "…and measured utilization over the last 30 days peaked at Y%." Only now is a sizing recommendation defensible |

**A reduction recommendation needs a time series, never a snapshot.** A pool sized for a
nightly batch, a weekly report run, or a seasonal peak is indistinguishable from an
oversized pool at any single instant — and the code freeze or the peak trading week is
precisely when a wrong recommendation gets acted on. Where the series is unavailable,
resolve `UNKNOWN` with the reason, state what was observed, and name the data that would
settle it. `CL-18` covers the mechanism side of the same waste: whether anything is
configured to reclaim the idle nodes at all.

**When node-level series are not exposed, say which it is.** "Not measured" and "measured
elsewhere, not readable here" are different findings with different fixes, and collapsing
them into one sentence is the failure mode this file warns about throughout. If cluster
observability is on but exposes pod series and not node series, that is the sentence to
write — not a silent fallback to requests, and not a claim that the estate is unmonitored.
