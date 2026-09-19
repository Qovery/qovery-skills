## Phase 4: Service Reliability & Resilience (RL checks)

This is the core of the assessment. Run every check against every service, then
report findings **grouped by check**, not by service — "14 production services run a
single replica" lands; fourteen separate findings do not.

Data sources: `env/<envId>/services.json`, `service/<id>/advanced-settings.json`,
`service/<id>/backups.json`,
`env/<envId>/deployment-history.json`, `default/application-advanced-settings.json`.

**Severity convention:** severities below are for services in a `PRODUCTION`
environment (or one the user flagged as business-critical in Phase 1.3). For
`STAGING` drop one level; for `DEVELOPMENT`/`PREVIEW` drop two, or mark `N/A` where
the check is meaningless outside production.

---

## Availability & scaling

### RL-01 — Production services run at least 2 replicas (3 is better)

**Severity:** Critical

```bash
jq -r '.results[] | select(.service_type == "APPLICATION" or .service_type == "CONTAINER")
  | [.name, .min_running_instances, .max_running_instances] | @tsv' raw/env/<prodEnvId>/services.json
```

**Fails when:** `min_running_instances < 2` on any production application or container.

**Why it matters:** with one replica there is no high availability and no zero-downtime
deploy. Every rollout, node drain, node upgrade, spot reclaim, or OOM kill is a full
outage of that service. Kubernetes will reschedule the pod — in 10 to 60 seconds,
during which the service returns nothing.

**Why 3 is better than 2:** with 2 replicas, losing one halves capacity, so each
replica must be provisioned to carry 100% of traffic alone. With 3, losing one costs
33%, which a modest headroom absorbs. Three replicas also survive a single-AZ failure
when combined with zone spread (`RL-10`), and let a `maxUnavailable: 1` rolling update
proceed while still serving from two pods.

**Recommendation:** `min_running_instances: 2` as the floor for anything
customer-facing, `3` for the revenue path and for anything fronting a queue consumer
with at-least-once semantics.

**Exception to check before reporting:** a service with an attached RWO volume
(`RL-19`) or a singleton leader-election workload legitimately runs one replica.
Verify against `storage` before calling it a gap.

---

### RL-02 — Autoscaling has room to act

**Severity:** High

**Fails when:** `max_running_instances == min_running_instances` on a production
service — the HPA exists but can never scale.

**Why it matters:** a fixed replica count means traffic spikes are absorbed by latency,
then by errors. It also means capacity is sized for the peak and paid for at the
trough.

**Recommendation:** `max_running_instances` at 2–4× the minimum, with
`hpa.cpu.average_utilization_percent` around 60–70% so scale-out starts before
saturation, not after.

---

### RL-03 — HPA thresholds are set deliberately

**Severity:** Medium

```bash
jq '{cpu: ."hpa.cpu.average_utilization_percent", mem: ."hpa.memory.average_utilization_percent"}' \
  raw/service/<id>/advanced-settings.json
```

**Fails when:** the threshold is ≥ 90% (scale-out triggers only once the service is
already degraded) or ≤ 30% (constant flapping and wasted spend).

**Also check:** whether the service is event-driven (queue consumer, batch worker). CPU
is the wrong signal there — KEDA scaling on queue depth is. Flag as an opportunity, and
confirm `keda.enabled` on the cluster (`CL-09`).

---

## Health checks

A wrong health check is worse than none: it either hides a broken pod or restarts a
healthy one. Assess liveness and readiness **separately** — they answer different
questions.

### RL-04 — A readiness probe is configured

**Severity:** Critical

```bash
# The probe `type` object returns ALL four keys (tcp/http/exec/grpc) with nulls for the
# unused ones, so select the non-null entry — `keys[0]` always answers "exec" and is wrong.
jq -r '.results[] | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
  | .name as $n | .healthchecks as $h
  | [$n,
     "ready=\($h.readiness_probe.type // {} | to_entries | map(select(.value != null)) | .[0].key // "NONE")",
     "live=\($h.liveness_probe.type  // {} | to_entries | map(select(.value != null)) | .[0].key // "NONE")"]
  | @tsv' raw/env/<envId>/services.json
```

**Fails when:** `healthchecks.readiness_probe` is null or absent on a service that
receives traffic.

**Why it matters:** readiness gates traffic. Without it, Kubernetes sends requests to a
pod the moment the container process starts — before the app has connected to its
database, loaded config, or warmed a cache. Every rolling deploy then serves a burst of
errors. This is the most common cause of "we get 502s for ten seconds on every deploy".

---

### RL-05 — A liveness probe is configured

**Severity:** High

**Fails when:** `healthchecks.liveness_probe` is null on a long-running service.

**Why it matters:** liveness recovers a process that is alive but wedged — a deadlocked
thread pool, an exhausted connection pool, an event loop blocked forever. Without it
the pod stays `Running` and broken until a human notices.

---

### RL-06 — Liveness and readiness are not the same probe

**Severity:** High

```bash
# Flag services whose two probes are identical apart from timing:
jq -r '.results[] | select(.healthchecks.readiness_probe and .healthchecks.liveness_probe)
  | select(.healthchecks.readiness_probe.type == .healthchecks.liveness_probe.type)
  | [.name, (.healthchecks.readiness_probe.type | to_entries
             | map(select(.value != null)) | .[0].value | tostring)] | @tsv' \
  raw/env/<envId>/services.json
```

**Fails when:** both probes resolve to the same probe type, port, and path.

**A good configuration looks like this** — distinct endpoints, and a liveness probe that
starts earlier and is cheaper than the readiness probe:

```
readiness: HTTP /health/ready  port 3000  delay 30s
liveness:  HTTP /health/live   port 3900  delay 15s
```

**Why it matters:** readiness should be strict and fast — fail it and the pod leaves the
load balancer, harmlessly. Liveness should be tolerant and slow — fail it and the pod is
**killed**. Identical probes mean a transient dependency blip kills every pod at once,
turning a degradation into a total outage with a restart loop on top.

**Recommendation:** liveness with a longer `period_seconds` and a higher
`failure_threshold` than readiness. The Qovery defaults are `period_seconds: 10`,
`timeout_seconds: 5`, `failure_threshold: 9`, `initial_delay_seconds: 30` — tune from
there rather than tightening both probes symmetrically.

---

### RL-07 — The liveness probe does not check dependencies

**Severity:** Critical (when confirmed)

**Fails when:** the liveness path is a deep health endpoint that verifies the database,
cache, or a downstream API.

**Why it matters:** this is the classic cascading-failure amplifier. The database has a
30-second blip; every pod of every service fails liveness simultaneously; Kubernetes
kills all of them; they all restart and hammer the recovering database at once. A
database hiccup becomes a platform outage.

**How to assess:** the API exposes the path, not its implementation. Report the paths
found (`/health`, `/healthz`, `/api/health`, `/status`) and **ask the team** which
dependencies each one touches. Record as `UNKNOWN` if unanswered — do not guess.

**Recommendation:** liveness on a shallow "is the process responsive" endpoint;
dependency checks belong in readiness (shed traffic) or in monitoring (page someone),
never in liveness (kill the pod).

---

### RL-08 — `initial_delay_seconds` matches real startup time

**Severity:** High

```bash
jq -r --arg id "<serviceId>" '.results[]? | select(.id == $id)
  | {name, liveness_delay: .healthchecks.liveness_probe.initial_delay_seconds,
     readiness_delay: .healthchecks.readiness_probe.initial_delay_seconds}' \
  raw/env/<envId>/services.json
```

**Fails when:** the delay is shorter than the application's real cold start. Compare
against observed startup duration in the deployment history and, where the team can
share it, application boot logs.

**Why it matters:** too short and the pod is killed mid-boot, forever — a CrashLoopBackOff
that looks like an application bug. Too long and every rollout and every recovery is
needlessly slow.

**Rough starting points:** JVM / Spring Boot 60–120s; .NET 30–60s; Node.js, Go, Python
5–30s. Verify against the actual service rather than applying the table.

---

### RL-09 — Probe timeout is shorter than the probe period

**Severity:** Medium

**Fails when:** `timeout_seconds >= period_seconds` — probes overlap and pile up,
producing misleading failures under load.

---

## Scheduling & rollout

### RL-10 — Pod anti-affinity keeps replicas off the same node

**Severity:** High

```bash
jq '{antiaffinity: ."deployment.antiaffinity.pod"}' raw/service/<id>/advanced-settings.json
```

**Fails when:** a production service with 2+ replicas has no pod anti-affinity.

**Why it matters:** two replicas scheduled onto the same node is two replicas with one
failure domain. The replica count on the dashboard says "highly available"; the node
says otherwise. Qovery accepts `Preferred` (best-effort spread, recommended) or
`Requirred` (hard requirement — note the API's spelling; a hard requirement leaves pods
`Pending` if no node is free).

---

### RL-11 — Replicas are spread across availability zones

**Severity:** High

```bash
jq '{zone_spread: ."deployment.topology_spread.zone"}' raw/service/<id>/advanced-settings.json
```

**Fails when:** `Disabled` on a production service in a multi-AZ cluster.

**Why it matters:** anti-affinity survives a node failure; zone spread survives an AZ
failure. `ScheduleAnyway` is the safe default — it spreads when it can and still
schedules when it cannot. `DoNotSchedule` is stricter and can block rollouts.

---

### RL-12 — Rolling updates, not recreate

**Severity:** Critical

```bash
jq '{strategy: ."deployment.update_strategy.type",
     max_unavailable: ."deployment.update_strategy.rolling_update.max_unavailable_percent",
     max_surge: ."deployment.update_strategy.rolling_update.max_surge_percent"}' \
  raw/service/<id>/advanced-settings.json
```

**Fails when:** `Recreate` on a production service — every deploy takes the service
fully down before starting the new version. Also flag `max_unavailable_percent` at
100%, which is `Recreate` wearing a different name.

**Recommendation:** `RollingUpdate` with `max_unavailable` at 0–25% and a positive
`max_surge` so new pods come up before old ones go down. `max_unavailable: 0` needs
node headroom (`CL-07`) to schedule the surge pod.

---

### RL-13 — Connections drain on shutdown

**Severity:** High

```bash
jq '{grace: ."deployment.termination_grace_period_seconds",
     pre_stop: ."deployment.lifecycle.pre_stop_exec_command"}' \
  raw/service/<id>/advanced-settings.json
```

**Fails when:** the grace period is shorter than the service's longest in-flight
request, or there is no pre-stop hook on a service behind an ingress.

**Why it matters:** on shutdown, the pod stops and the load balancer deregisters it —
concurrently, not in order. Without a short pre-stop pause, in-flight requests are cut
and the client sees a 502 on every single deploy. This is the second half of the
"errors on every deploy" complaint that `RL-04` starts.

---

## Resources

### RL-14 — Requests and limits are sane

**Severity:** High

> **Read these fields correctly.** `cpu` (millicores) and `memory` (MB) are the
> service's allocation. `maximum_cpu` and `maximum_memory` are **not** per-service
> limits — the API defines them as the ceiling allowed by the cluster's instance type,
> so they are identical across every service on a cluster. Comparing `cpu` to
> `maximum_cpu` as if it were a request/limit ratio produces a false finding on every
> service. Use `maximum_*` only for `RL-15` (headroom against the cluster ceiling).

```bash
jq -r '.results[] | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
  | [.name, "cpu=\(.cpu)m", "mem=\(.memory)MB", "replicas=\(.min_running_instances)"] | @tsv' \
  raw/env/<envId>/services.json | column -t
```

**Assess three things:**

- **Uniform values across unrelated services** — every service at the same `cpu`/`memory`
  means nobody has sized anything; the numbers are decoration inherited from a default.
- **Allocation vs actual consumption** — the only question that matters, and it needs
  metrics. Without cluster observability (`CL-08`) this is `UNKNOWN`, not a pass.
- **Total requested vs cluster capacity** — sum `cpu × min_running_instances` across the
  environment and compare with the node pool. An environment that cannot fit its own
  minimum replicas after a node loss has no real headroom.

**Recommendation:** enable cluster observability (`CL-08`) and run `qovery-optimize`,
which uses KRR for P99-based, OOM-aware recommendations. Do not invent numbers in this
report — point at the measurement.

---

### RL-15 — Ephemeral storage is sized for the workload

**Severity:** Medium

```bash
jq -r '.results[] | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
  | [.name, (.ephemeral_storage_in_gib // "default"),
     "headroom_cpu=\(.maximum_cpu - .cpu)", "headroom_mem=\(.maximum_memory - .memory)"] | @tsv' \
  raw/env/<envId>/services.json | column -t
```

**Why it matters:** a pod that exceeds its ephemeral storage is evicted without warning —
services writing logs, temp files, or upload buffers to local disk are the usual victims.
The `maximum_*` columns show how close a service sits to the cluster's per-pod ceiling: a
service near it cannot be scaled vertically without changing the cluster instance type.

---

## Data layer

### RL-16 — Production databases are managed, not containers

**Severity:** Critical

```bash
jq -r '.results[] | select(.service_type == "DATABASE")
  | [.name, .mode, .type, .version, .instance_type, .storage] | @tsv' raw/env/<prodEnvId>/services.json
```

**Fails when:** a production database has `mode: CONTAINER`.

**Why it matters:** container databases run as a single pod on a single node with no
automated backup, no point-in-time recovery, no failover, no multi-AZ, and no managed
patching. A node failure is data loss. They are excellent for development and
categorically unsuitable for production data.

**Recommendation:** `mode: MANAGED` (RDS / Cloud SQL / equivalent) for every production
datastore. Keep `CONTAINER` in dev and staging — but see `TP-06`: a mode mismatch
between staging and production means staging is not testing production's failure
behaviour.

---

### RL-17 — Backups exist and are recent

**Severity:** Critical

```bash
jq -r '.results[0:5][] | [.name, .created_at, .status] | @tsv' raw/service/<dbId>/backups.json
```

**Fails when:** no backups exist for a production database, or the most recent one is
older than the stated recovery point objective.

**Ask the question the backup list cannot answer:** when was a restore last tested? An
untested backup is a hypothesis. Record as `UNKNOWN` if the team cannot say — that
itself is the finding.

---

### RL-18 — Database storage has headroom

**Severity:** High

```bash
jq -r '.results[] | select(.service_type == "DATABASE") | [.name, .storage, .disk_type] | @tsv' \
  raw/env/<envId>/services.json
```

**Why it matters:** a full database disk is not a degradation, it is a hard stop —
writes fail, and on some engines recovery requires manual intervention. Growth trends
come from the cluster metrics API when observability is enabled.

---

### RL-19 — Single-replica stateful services are intentional

**Severity:** High

```bash
# `storage` is an ARRAY on applications/containers but a NUMBER (GB) on databases,
# so filter by service_type first or jq fails with "Cannot iterate over number".
jq -r '.results[] | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
  | select((.storage // []) | length > 0)
  | [.name, .min_running_instances,
     ((.storage | map("\(.mount_point):\(.size)GB")) | join(","))] | @tsv' \
  raw/env/<envId>/services.json | column -t
```

**Fails when:** a service with persistent volumes runs one replica **and** sits on the
critical path.

**Why it matters:** an RWO volume binds the pod to one node and one AZ. This is a
structural single point of failure that no replica-count change fixes — it needs a
managed service, an RWX volume, or object storage instead.

---

## Jobs, Helm & pipeline reliability

### RL-20 — Jobs have restart and duration bounds

**Severity:** Medium

```bash
jq -r --arg id "<jobId>" '.results[]? | select(.id == $id)
  | {name, max_nb_restart, max_duration_seconds, schedule}' raw/env/<envId>/services.json
```

**Fails when:** `max_duration_seconds` is unset or longer than the cron interval — runs
overlap, pile up, and contend for the same rows or the same API quota.

---

### RL-21 — Helm releases are bounded and scoped

**Severity:** Medium

```bash
jq -r --arg id "<helmId>" '.results[]? | select(.id == $id)
  | {name, timeout_sec, allow_cluster_wide_resources}' raw/env/<envId>/services.json
```

**Why it matters:** `allow_cluster_wide_resources: true` lets a chart create
cluster-scoped objects — CRDs, ClusterRoles, webhooks — that affect every namespace on
the cluster. Legitimate for platform charts, a real blast-radius question for
application charts.

---

### RL-22 — The delivery pipeline itself is reliable

**Severity:** High

```bash
jq -r '.results[] | [.identifier.execution_id, .status, .total_duration, .auditing_data.created_at] | @tsv' \
  raw/env/<envId>/deployment-history.json | head -30
```

Compute per environment: deployment count, failure rate, median duration.

**Fails when:** the production failure rate exceeds ~15%, or deployments are so slow
that the team batches changes to avoid them.

**Why it matters:** change-failure rate and lead time are the two DORA metrics that
predict incident frequency. A team that dreads deploying deploys less, batches more,
and fails harder when it does.

**Recommendation:** route slow pipelines to `qovery-speedup`; route a specific failing
deployment to `qovery-troubleshoot`.

---

### RL-23 — Lifecycle jobs clean up what they create

**Severity:** High (Critical where the job provisions cloud infrastructure)

```bash
jq -r '.results[]? | select(.service_type == "JOB" and .job_type == "LIFECYCLE")
  | [.name,
     (.schedule.lifecycle_type // "GENERIC"),
     (if .schedule.on_start  then "on_start"  else "-" end),
     (if .schedule.on_stop   then "on_stop"   else "-" end),
     (if .schedule.on_delete then "on_delete" else "MISSING" end)] | @tsv' \
  raw/env/<envId>/services.json | column -t
```

**Fails when:** a lifecycle job that **provisions something outside the environment**
defines `on_start` and no `on_delete`.

**`on_start` without `on_delete` is not the finding on its own.** A migration runner, a
seed-data job, a cache warmer — all legitimately have a start action and nothing to tear
down, and reporting them as leaked resources is noise that buries the real one. Establish
what the job creates before scoring:

| Evidence | Result |
|---|---|
| `lifecycle_type` is `TERRAFORM` or `CLOUDFORMATION` | **FAIL** — these exist to create infrastructure, and without `on_delete` the state file is orphaned with everything it tracks |
| `GENERIC`, and the job's image, entrypoint or arguments name a provisioning action (`create-bucket`, `terraform apply`, `aws ...`, `gcloud ...`) | **FAIL**, with the evidence quoted |
| `GENERIC`, and the team confirms it provisions an external resource | **FAIL** |
| `GENERIC`, and nothing indicates provisioning | **UNKNOWN** — ask what `on_start` does. Do not infer from its existence |

```bash
# What the job actually runs, for the GENERIC case. Report the command, never a value.
jq -r '.results[]? | select(.service_type=="JOB" and .job_type=="LIFECYCLE")
  | [.name, (.schedule.lifecycle_type // "GENERIC"),
     ((.schedule.on_start.entrypoint // "-") + " " + ((.schedule.on_start.arguments // []) | join(" ")))]
  | @tsv' raw/env/<envId>/services.json | column -t
```

**Why it matters:** a lifecycle job is how an environment reaches outside itself — it
creates the bucket, the queue, the DNS record, the managed database the environment needs.
`on_start` creates them. `on_delete` is the only thing that removes them. Without it,
deleting the environment deletes the Qovery side and leaves the cloud side running: the
resource keeps its data, keeps its network exposure, and keeps billing, with nothing left
in Qovery pointing at it. Preview and ephemeral environments make this compound, because
each one leaks a fresh copy.

`lifecycle_type: TERRAFORM` or `CLOUDFORMATION` raises it to Critical. Those jobs hold
state, and an environment deleted without `on_delete` orphans the state file along with
everything it tracks, so the resources can no longer be destroyed by the tool that made
them.

**Recommendation:** every lifecycle job that provisions gets an `on_delete` that destroys.
Verify it in a preview environment rather than in production: create one, delete it, and
confirm in the cloud console that nothing remains. Pair with `OP-05`, which asks whether
those external resources are declared in Qovery at all.
