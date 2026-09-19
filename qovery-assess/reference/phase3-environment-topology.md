## Phase 3: Environment Topology & Tier Separation (TP checks)

This phase answers: **does this organization have a real path to production?**
A team with only a production environment ships untested changes. A team whose
staging has diverged from production tests something that does not exist.

Data sources: `env/<envId>/statuses.json` (per-service state; ids and states only, no
names — join to `services.json` on `id`), `environments.json`, `projects.json`, `clusters.json`,
`env/<envId>/environment.json`, `env/<envId>/deployment-rule.json`,
`env/<envId>/services.json`.

Build the tier table first:

```bash
jq -r '.results[] | [.mode, .name, .cluster_name, .project_name] | @tsv' \
  raw/environments.json | sort | column -t
```

---

### TP-01 — A production environment exists and is identified as such

**Severity:** Critical

**Fails when:** no environment has `mode: PRODUCTION`, yet the organization clearly
serves live traffic (public custom domains, managed databases, steady deploy history).

**Why it matters:** `mode` is not cosmetic. It drives Qovery's defaults for preview
creation, auto-stop eligibility, and deletion guardrails. A production workload in
`DEVELOPMENT` mode is a production workload with development-grade protection.

---

### TP-02 — A staging or pre-production environment exists

**Severity:** High

**Fails when:** the only tiers are production and developer sandboxes — no shared
environment where a release candidate is validated with production-like data and
configuration.

**Why it matters:** without a staging tier the only integration test is the production
deploy. This is the single strongest predictor of change-failure rate.

**Recommendation:** one `STAGING` environment per product, cloned from production so
the topology matches, backed by the same database engine and version.

---

### TP-03 — Development work has somewhere to go that is not production

**Severity:** High

**Fails when:** developers deploy feature work into the production environment, or
there is no `DEVELOPMENT`/`PREVIEW` tier at all.

**Recommendation:** per-PR preview environments (`qovery-preview`) give every developer
an isolated stack without a permanent per-developer environment bill.

---

### TP-04 — Environment `mode` matches the environment's real role

**Severity:** High

```bash
jq -r '.results[] | [.name, .mode] | @tsv' raw/environments.json
```

**Fails when:** the name and the mode disagree — an environment named `prod`,
`production`, `live`, or `main` with `mode: DEVELOPMENT`, or an environment named
`sandbox` with `mode: PRODUCTION`.

**Why it matters:** every severity rating in this report, and every Qovery guardrail,
keys off `mode`. Misclassification makes both wrong.

---

### TP-05 — Production sits on its own cluster

**Severity:** High

**Fails when:** the production environment's `cluster_id` also hosts development or
preview environments. Pairs with `CL-05`; report it once, under whichever pillar the
customer will act on.

---

### TP-06 — Staging is a faithful mirror of production

**Severity:** High

Compare the two environments service by service:

```bash
# Type and name alone cannot show an engine, version or topology mismatch — the three
# things the failure rule below turns on. Carry those fields into the comparison.
PARITY='.results[]
  | [ .service_type, .name,
      (.mode // "-"),                                  # database CONTAINER vs MANAGED
      ((.type // "-") + ":" + (.version // "-")),      # engine and version
      ("min=" + ((.min_running_instances // "-")|tostring)),
      ("cpu=" + ((.cpu // "-")|tostring) + " mem=" + ((.memory // "-")|tostring)),
      ("storage=" + ((.storage // "-")|tostring))
    ] | @tsv'
jq -r "$PARITY" raw/env/<prodEnvId>/services.json    | sort > /tmp/prod.txt
jq -r "$PARITY" raw/env/<stagingEnvId>/services.json | sort > /tmp/stg.txt
diff /tmp/prod.txt /tmp/stg.txt
```

Resource sizes legitimately differ between tiers, so do not report `cpu=`/`mem=` gaps as
parity failures on their own — they are there to show *how far* staging is from production
when something else already diverges. `mode`, engine, version and replica floor are the ones
that change behaviour.

**Fails when:** staging is missing services present in production, runs a different
database engine or major version, a different database `mode` (container in staging,
managed in production), or a different replica topology.

**Why it matters:** parity gaps are where "it worked in staging" incidents are born.
The most damaging version: staging on a container database, production on a managed
one — different failover behaviour, different connection limits, different timeouts.

**Report the diff itself** — the list of divergent services is more persuasive than
the finding.

---

### TP-07 — Non-production environments are not running 24/7 for nothing

**Severity:** Medium (cost pillar)

```bash
jq '{auto_stop, start_time, stop_time, weekdays, timezone}' raw/env/<envId>/deployment-rule.json
```

**Fails when:** a `DEVELOPMENT` or `STAGING` environment has `auto_stop: false` and no
start/stop schedule.

**Why it matters:** a weekday 8am–8pm schedule leaves the environment running 60 of
168 hours — roughly 64% saved on that environment, with no production impact.

---

### TP-08 — Production has no auto-stop or on-demand-preview rule

**Severity:** Critical

```bash
jq '{auto_stop, on_demand_preview, auto_preview, start_time, stop_time}' \
  raw/env/<prodEnvId>/deployment-rule.json
```

**Fails when:** a `PRODUCTION` environment has `auto_stop: true` or a stop schedule.

**Why it matters:** this is a scheduled outage waiting to happen. It is rare, and when
it happens it is spectacular.

---

### TP-09 — Preview environments are configured for the team's workflow

**Severity:** Medium

```bash
jq '{auto_preview}' raw/env/<envId>/deployment-rule.json
jq -r '.results[] | [.name, .auto_preview, .auto_deploy] | @tsv' raw/env/<envId>/services.json
```

**Fails when:** the team reviews pull requests but no environment has `auto_preview`
enabled, or `auto_preview` is inconsistently enabled across services in the same
environment so a preview comes up half-built.

**Also check that previews actually get cleaned up** — this is where the check earns its
keep, and `auto_preview: true` on its own will mask it:

```bash
for d in raw/env/*/; do
  [ -f "$d/environment.json" ] || continue
  jq -r 'select(.mode=="PREVIEW") | [(.name|.[0:44]), .updated_at[0:10]] | @tsv' "$d/environment.json"
done | sort -k2 | column -t
# and their states — DELETE_ERROR is the one that matters:
for d in raw/env/*/; do
  # `jq 'select(...)'` exits 0 with no output when nothing matches, so using it as an && gate
  # lets every environment through and the state breakdown below counts non-preview
  # environments too. Test the output, not the exit status.
  [ "$(jq -r '.mode // ""' "$d/environment.json" 2>/dev/null)" = "PREVIEW" ] || continue
  jq -r '.environment.state // empty' "$d/statuses.json" 2>/dev/null
done | sort | uniq -c
```

**Fails when** preview environments are weeks or months old, and especially when any sit in
`DELETE_ERROR` — Qovery tried to clean them up and could not. That state recurs until the
cause is found (usually a stuck finalizer or an external resource holding a reference), so
each failed PR leaves another environment behind, paying for compute and running unpatched
images. Report the count, the oldest date, and the state breakdown.

---

### TP-10 — Project structure reflects ownership

**Severity:** Info

```bash
jq -r '.results[] | [.name, .associated_environments_count] | @tsv' raw/projects.json
```

**Observation, not a gap:** a single project holding every environment for every
product makes RBAC all-or-nothing — custom roles grant per-project permissions, so
project boundaries are also permission boundaries. Note it when the org has more than
one team and exactly one project.

---

### TP-11 — No orphaned or abandoned environments

**Severity:** Medium (cost + security)

```bash
jq -r '.results[] | [.name, .mode, .updated_at] | @tsv' raw/environments.json | sort -k3
jq -r '.environment.state' raw/env/<envId>/statuses.json
```

**Fails when:** environments have not been deployed or touched in months but still
hold running services, databases, and public endpoints.

**Why it matters:** abandoned environments keep costing money, keep running
unpatched images, and keep exposing endpoints nobody is monitoring.
