## Phase 4b: Anti-Pattern Detection (BP checks)

The `RL` checks test settings one at a time. This phase looks for **shapes** — combinations
that are individually defensible and collectively dangerous. Each one is a pattern that has
caused a real outage often enough to be worth naming.

Only report a BP finding when the full combination is present. A single-replica service is
`RL-01`; a single-replica *message broker on the production critical path* is `BP-02`, and
it is a different conversation.

> Every query below uses `.results[]?`. An endpoint that failed is stored as
> `{"_unreadable":true,...}`, and `.results[]` on it aborts jq mid-loop, so one unreadable
> environment would silently truncate the sweep for every environment after it. The `?` keeps
> the loop running; check the collect log for MISS lines and report those environments as
> UNKNOWN rather than as clean.

Data sources: `env/<envId>/services.json`, `service/<id>/advanced-settings.json`,
`service/<id>/backups.json`, `env/<envId>/variables.json`.

---

### BP-01 — Stateful singleton on the critical path

**Severity:** Critical

```bash
for d in raw/env/*/; do
  [ "$(jq -r .mode "$d/environment.json")" = "PRODUCTION" ] || continue
  jq -r '.results[]? | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
    | select(.min_running_instances == 1)
    | select(((.storage // []) | length) > 0)
    | [.name, "replicas=\(.min_running_instances)",
       "volumes=\((.storage // []) | length)"] | @tsv' "$d/services.json"
done | column -t
```

**The shape:** one replica **+** a persistent volume **+** production **+** something
depends on it synchronously.

**The query establishes the first three. It cannot establish the fourth**, and the fourth
is what makes this Critical rather than Medium. A single-replica volume-backed service that
nothing calls synchronously — a batch worker draining a queue, a log shipper — is a
recovery-time problem, not an availability one. Confirm the dependency before reporting:

```bash
# Who references this service? A host alias pointing at it is evidence of a caller.
bash templates/scripts/service-graph.sh . <environmentName>
```

If the graph shows a caller, or the team confirms one, report Critical and name the caller
in the finding. If nothing references it and the team cannot name a synchronous dependant,
report it as **High** with the shape stated and the dependency question left open. Never
issue the Critical on the shape alone: it is the most alarming finding in the anti-pattern
family, and one that turns out to be a nightly batch job costs more credibility than the
finding was worth.

**Why it matters:** an RWO volume binds the pod to one node and one availability zone. This
is not fixable by raising the replica count — the second replica cannot mount the volume.
It is a structural single point of failure that needs a managed service, an RWX volume, or
object storage instead. Distinguish it clearly from `RL-01` in the report: `RL-01` has a
one-line fix, `BP-01` needs an architecture change.

---

### BP-02 — Message broker or cache running as a production singleton

**Severity:** Critical

```bash
for d in raw/env/*/; do
  [ "$(jq -r .mode "$d/environment.json")" = "PRODUCTION" ] || continue
  jq -r '.results[]? | select(.name | test("(?i)rabbit|kafka|nats|redis|memcach|pulsar|activemq|mqtt|queue|broker|celery|sidekiq|elastic|opensearch"))
    | [.service_type, .name, "min=\(.min_running_instances // "-")",
       "max=\(.max_running_instances // "-")"] | @tsv' "$d/services.json"
done | column -t
```

For Helm-deployed brokers the replica count lives in the chart values, so check those too:

```bash
jq -r '.results[]? | select(.service_type=="HELM")
  | [.name, (.values_override | tostring | .[0:200])] | @tsv' raw/env/<prodEnvId>/services.json
```

**Why it matters:** a queue is the one component whose failure is silently destructive. A
single-instance broker loses in-flight messages on restart, and "restart" includes every
node upgrade. Worse, the services around it usually keep reporting healthy — the outage
surfaces hours later as missing emails, unprocessed payments, or a reconciliation gap. For
anything with at-least-once delivery semantics, a singleton broker quietly breaks the
guarantee the application assumes.

**Recommendation:** clustered mode (RabbitMQ quorum queues, NATS JetStream cluster, Redis
Sentinel or a managed equivalent), or a managed service. Whichever way, confirm the
application actually reconnects — untested reconnection logic is the other half of this
failure.

---

### BP-03 — Production datastore with no replica or no multi-AZ

**Severity:** Critical

```bash
jq -r '.results[]? | select(.service_type=="DATABASE")
  | [.name, .mode, .type, .version, (.instance_type // "-"),
     "storage=\(.storage // "-")GB", "encrypted=\(.disk_encrypted)"] | @tsv' \
  raw/env/<prodEnvId>/services.json | column -t
```

**Fails when:** a production database is `CONTAINER` mode (no failover at all — see
`RL-16`), or is `MANAGED` on a single-AZ instance class with no read replica or standby.

Qovery reports the mode and instance type; whether multi-AZ is enabled is a cloud-provider
setting, so **ask** rather than assume when it is not visible. Record `UNKNOWN` if unanswered.

**Why it matters:** single-AZ managed Postgres fails over by restoring, which is measured in
tens of minutes, not seconds. That number belongs in the RTO conversation (`DR-01`), and
most teams have never actually measured it.

---

### BP-04 — Stateful service with neither backup nor replica

**Severity:** Critical

The compound case: no redundancy *and* no recovery path.

```bash
for d in raw/env/*/; do
  [ "$(jq -r .mode "$d/environment.json")" = "PRODUCTION" ] || continue
  jq -r '.results[]? | select(.service_type=="DATABASE" or ((.storage // []) | length) > 0)
    | [.id, .name, .service_type, (.mode // "-"), (.min_running_instances // "-")] | @tsv' "$d/services.json"
done | while IFS=$'\t' read -r id name stype mode reps; do
  B=$(jq -r 'if ._unreadable then "none" else (.results | length | tostring) end' \
        "raw/service/$id/backups.json" 2>/dev/null || echo "none")
  echo "$name	$stype	mode=$mode	replicas=$reps	backups=$B"
done | column -t
```

**Why it matters:** either alone is a risk; together it is unrecoverable data loss from a
single node failure. This is the finding that leads the report when it appears, ahead of
anything else.

---

### BP-05 — Cron jobs that can overlap

**Severity:** High

```bash
# Schedule and duration bound, per cron job.
jq -r '.results[]? | select(.service_type=="JOB" and .job_type=="CRON")
  | [.name, (.schedule.cronjob.scheduled_at // "-"),
     "maxdur=\(.max_duration_seconds // "unset")",
     "restarts=\(.max_nb_restart // "-")"] | @tsv' raw/env/<envId>/services.json | column -t

# Does Kubernetes already prevent the overlap? This is the deciding field.
jq -r '{concurrency: ."cronjob.concurrency_policy",
        failed_history: ."cronjob.failed_jobs_history_limit",
        success_history: ."cronjob.success_jobs_history_limit",
        job_ttl: ."job.delete_ttl_seconds_after_finished"}' \
  raw/service/<jobId>/advanced-settings.json
```

**Read `cronjob.concurrency_policy` first.** It decides the verdict, and the duration
bound only matters when the policy allows a second run:

| `concurrency_policy` | Verdict |
|---|---|
| `Forbid` | **PASS.** Kubernetes skips the run while the previous one is active. The duration bound is still worth reporting, as Info, because a skipped run is a missed run. |
| `Replace` | **PASS** for overlap. Flag separately if the job is not safely interruptible — `Replace` kills the running instance mid-work. |
| `Allow` (the default) | Fall through to the duration test below. |

**Fails when:** the policy is `Allow` **and** `max_duration_seconds` is unset or exceeds
the interval between runs.

**Why it matters:** two instances of the same job running concurrently is how duplicate
charges, double-sent notifications, and corrupted aggregates happen. Where the job holds a
lock, the second run blocks and the backlog compounds until something times out. `RL-20`
checks that bounds exist at all; this one checks the bound against the schedule, and the
concurrency policy against both.

**Recommendation:** `Forbid` expresses the intent directly and does not depend on anyone
keeping the duration bound in step with the schedule. Keep the duration bound as well, so
a hung run is killed rather than blocking every run after it.

**While you are in this payload:** `job.delete_ttl_seconds_after_finished` unset means
completed job objects accumulate on the cluster indefinitely. It is a Low finding on its
own — report it beside this one rather than raising it separately.

---

### BP-06 — Admin or BI tooling with datastore access on the production cluster

**Severity:** High

```bash
for d in raw/env/*/; do
  [ "$(jq -r .mode "$d/environment.json")" = "PRODUCTION" ] || continue
  jq -r '.results[]? | select(.name | test("(?i)metabase|superset|redash|pgadmin|phpmyadmin|adminer|grafana|kibana|airflow|jupyter|retool|mongo-express"))
    | .name as $n | [$n, ((.ports // []) | map(select(.publicly_accessible==true) | tostring) | length | tostring)] | @tsv' "$d/services.json"
done | column -t
```

**Why it matters:** these tools hold standing credentials to production data, are rarely
patched on the same cadence as first-party services, and are a recurring source of published
CVEs. Public exposure (`SC-04`) makes it acute; even private, they widen the blast radius of
any cluster compromise and are frequently the one service nobody owns.

**Recommendation:** network-restrict them, put them behind SSO, and treat their upgrade
cadence as a real obligation — or move them off the production cluster with scoped,
read-only, auditable database access.

---

### BP-07 — One environment reaching into another's datastore

**Severity:** Critical

```bash
# Collect production datastore hostnames, then look for them elsewhere.
jq -r '.results[]? | select(.service_type=="DATABASE") | .host // empty' \
  raw/env/<prodEnvId>/services.json > /tmp/prod-hosts.txt
for d in raw/env/*/; do
  M=$(jq -r .mode "$d/environment.json"); N=$(jq -r .name "$d/environment.json")
  [ "$M" = "PRODUCTION" ] && continue
  while read -r h; do
    [ -z "$h" ] && continue
    jq -r --arg h "$h" --arg n "$N" '.results[]? | select(.value != null)
      | select(.value | contains($h)) | [$n, .key, "references production host"] | @tsv' \
      "$d/variables.json" 2>/dev/null
  done < /tmp/prod-hosts.txt
done | column -t
```

**Why it matters:** a staging or preview environment holding production's database endpoint
is a production incident waiting for a test run — a migration, a fixture load, or a
truncate. It is also almost always a data-protection problem, since non-production usually
has looser access. Nearly always caused by a hardcoded value that `VS-05` would have
prevented.

---

### BP-08 — Uniform default resourcing across unrelated services

**Severity:** Medium

```bash
for d in raw/env/*/; do
  jq -r '.results[]? | select(.service_type=="CONTAINER" or .service_type=="APPLICATION")
    | [.cpu, .memory] | @tsv' "$d/services.json"
done | sort | uniq -c | sort -rn | head
```

**Fails when:** a large share of services share one identical `cpu`/`memory` pair.

**Why it matters:** it means nobody has sized anything — the numbers came from a default and
were never revisited. A gateway and a batch worker do not have the same resource profile, so
one of them is wrong, and usually both. This is a pointer, not a prescription: the fix is
measurement (`CL-08`, then `CE-07`/`CE-08`), not a guess.
