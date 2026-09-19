## Phase 6: Delivery & Operations (DL checks)

Reliability is not only how the system is configured — it is how changes reach it and
how fast anyone finds out when something breaks. This phase covers the delivery
pipeline, the feedback loop, and the waste.

Cost efficiency moved to its own phase file (`phase6d-cost-efficiency.md`); anti-patterns
to `phase4b-bad-practices.md`.

Data sources: `env/<envId>/deployment-stages.json`, `env/<envId>/deployment-history.json`,
`service/<id>/deployment-restriction.json`, `service/<id>/git-webhook-status.json`,
`service/<id>/commits.json`, `webhooks.json`, `alert-receivers.json`,
`alert-rules.json`, `current-cost.json`, `environments.json`, `clusters.json`.

---

## Delivery (DL)

### DL-01 — Deployment stages order the pipeline correctly

**Severity:** High

```bash
jq -r '.results[] | [.deployment_order, .name, (.services | length)] | @tsv' \
  raw/env/<envId>/deployment-stages.json | sort -n
```

**Fails when:** every service sits in a single default stage in an environment where
ordering matters — migrations, databases, and backing services must be ready before the
applications that depend on them.

**Why it matters:** without stages, Qovery deploys in parallel. An application can start
against a database that has not finished its migration, fail its health check, and roll
back a deploy that was actually fine. It also costs time: correctly staged pipelines
parallelise everything *within* a stage.

**Recommendation:** stage 1 datastores, stage 2 migration jobs, stage 3 backend
services, stage 4 frontends.

---

### DL-02 — Auto-deploy is deliberate per tier

**Severity:** Medium

```bash
jq -r '.results[] | [.name, .auto_deploy, .auto_preview] | @tsv' raw/env/<envId>/services.json
```

**Expected pattern:** `auto_deploy: true` in development and staging so the team gets
fast feedback; production gated behind an explicit action or a protected branch.

**Fails when:** the pattern is inverted (production auto-deploys from a shared branch
while staging is manual), or `auto_deploy` is inconsistent across services in the same
environment so a deploy leaves the environment half-updated.

---

### DL-03 — Monorepo services have deployment restrictions

**Severity:** Medium

**Applicability — check this before skipping it.** The check applies to any service built
from Git (`service_type: APPLICATION`, and `JOB`/`HELM`/`TERRAFORM` with a Git source), not
only to a monorepo you already know about. Determine it from the data:

```bash
# Distinct services sharing one repository WITHIN one environment.
for d in raw/env/*/; do
  E=$(jq -r '.name' "$d/environment.json")
  jq -r --arg e "$E" '.results[]? | select(.git_repository != null)
    | [$e, .git_repository.url, .name] | @tsv' "$d/services.json"
done | sort -u | awk -F'\t' '{k=$1"\t"$2; c[k]++; n[k]=n[k]" "$3}
  END {for (k in c) if (c[k]>1) {split(k,a,"\t"); print c[k]" in "a[1]": "a[2]n[k]}}'
```

**Scope the grouping to one environment, and de-duplicate service names.** The same service
deployed to `development` and `production` legitimately points at the same repository. Group
by repository alone and every ordinary two-environment service is reported as a monorepo —
a false finding, and usually the majority of the output. Only two distinct services in the
*same* environment sharing a repository are a monorepo.

`N/A` only when **no** service is Git-built (an organization deploying pre-built images
only). For each repository the query above returns, read the restrictions of every service
sharing it:

```bash
jq -r '.results[]? | [.mode, .type, .value] | @tsv' raw/service/<id>/deployment-restriction.json
```

**Fails when:** two or more services in one environment share a repository and the set of
restrictions does not separate them — no restrictions at all, or overlapping paths that
still rebuild every service on a common commit.

**Read the restrictions as a set, not per service.** A correct split is complementary: one
service `EXCLUDE`s the paths its sibling owns while the sibling `MATCH`es exactly those
paths. Judging either service alone would mislabel that — the `EXCLUDE` side looks like it
has "some restriction", the `MATCH` side like it is narrowly scoped, and neither tells you
whether the repository is actually partitioned. Quote the pair as evidence.

**Why it matters:** without restrictions, a README change redeploys every service in the
repository. That is wasted build minutes, unnecessary rollout risk, and a team that stops
trusting the deploy notification channel. Where the organization already runs a correct
split somewhere, cite it — remediation lands better as "do what `<service>` already does"
than as a generic recommendation.

---

### DL-04 — Deploy notifications reach the team

**Severity:** Medium

```bash
jq -r '.results[] | [.kind, .target_url, .enabled, (.events | join(",")),
  (.environment_types_filter // [] | join(","))] | @tsv' raw/webhooks.json
```

**Fails when:** no webhook exists, or all webhooks are disabled, or production
deployment failures are not routed anywhere.

---

### DL-05 — Alerting exists and covers production

**Severity:** Critical

```bash
jq -r '.results[] | [.name, .type, .enabled] | @tsv' raw/alert-receivers.json
jq -r '.results[] | [.name, .severity, .enabled, .source, .state,
  (.alert_receiver_ids | length)] | @tsv' raw/alert-rules.json

# Rules that will never notify anyone:
jq -r '.results[] | select(.enabled == false or (.alert_receiver_ids | length) == 0)
  | [.name, .severity, .enabled, (.alert_receiver_ids | length)] | @tsv' raw/alert-rules.json
```

**Check for an external alerting platform before failing this.** Zero Qovery alert rules
does not mean nobody is paged. Run the detection in `CL-08`: an APM or monitoring agent
deployed cluster-wide, with its API key held as a secret, is where alerting almost certainly
lives. Score the check on that basis and name the platform.

Two things it does **not** cover, which stay findings on their own merits:

- **Deployment notifications (`DL-04`).** An APM agent does not see Qovery deploy outcomes.
  A failed production deploy visible only in the Console is a real gap even on a
  well-monitored estate.
- **Whether rules actually exist.** A deployed agent proves telemetry is flowing, not that
  anyone configured an alert on it. Say which of the two you verified, and put "confirm
  alert rules exist in <platform>" in the report rather than asserting coverage you did not
  see.



**Fails when:** there are no alert receivers, no alert rules, or rules that are
disabled or have an empty `alert_receiver_ids` — a rule with no receiver fires into
nothing, which is indistinguishable from having no rule at all.

**Why it matters:** this is the difference between a four-minute incident and a
four-hour one. Every other reliability control in this report assumes somebody finds out.
An organization with perfect replica counts and no alerting is still operating blind.

**Also flag** `source: GHOST` rules — they exist in Prometheus but were deleted from
Qovery, so nobody owns or maintains them.

---

### DL-06 — Deployment duration is not a tax on shipping

**Severity:** Medium

```bash
jq -r '.results[] | [.status, .total_duration] | @tsv' raw/env/<envId>/deployment-history.json | head -20
```

**Fails when:** median production deploy duration is long enough that the team batches
changes. Pairs with `RL-22` (failure rate).

**Recommendation:** route to `qovery-speedup`, which separates build, scheduling, image
pull, startup, and health-check time and says which part is the customer's and which is
Qovery's.

---

### DL-07 — Configuration is reproducible

**Severity:** Medium

**Assess:** is this setup managed through the Console only, or is there
infrastructure-as-code? Check for `.tf` files in the customer's repositories and for
Terraform services in the inventory (`service_type: TERRAFORM`).

**Why it matters:** a Console-only setup cannot be code-reviewed, diffed, or rebuilt
after a mistake. It also means this assessment's findings must be fixed by hand, in
every environment, without a record.

**Recommendation:** `qovery-terraform` generates provider manifests from the live setup
and imports existing resources into state — no rebuild required.

---

### DL-08 — Environment variables are scoped, not duplicated

**Severity:** Medium

```bash
jq -r '.results[] | [.key, .scope, .variable_type] | @tsv' raw/env/<envId>/variables.json \
  | sort | awk '{print $1}' | uniq -c | sort -rn | head -20
```

**Fails when:** the same key is defined separately on many services instead of once at
environment or project scope, or aliases and overrides are used where a single scoped
variable would do.

---

### DL-09 — Service-to-service configuration uses Qovery's built-in variables

**Severity:** Info

**Observation:** hardcoded hostnames and URLs between services break when an
environment is cloned — which is exactly what preview environments do. Qovery's built-in
variables and aliases keep a cloned environment internally consistent.

---

### DL-10 — Cluster and workload ownership is documented

**Severity:** Info

Who owns each cluster, each environment, and each production service? If the answer
lives in one person's head, that is a finding worth writing down even though no API
returns it.

---

### DL-11 — Container images come from a controlled registry

**Severity:** Medium

```bash
jq -r '.results[] | [.name, .kind, .url] | @tsv' raw/container-registries.json
jq -r '.results[] | select(.service_type == "CONTAINER") | [.name, .image_name, .tag] | @tsv' \
  raw/env/<envId>/services.json
```

**Fails when:** production containers use a mutable tag (`latest`, `main`, `staging`) —
the running image cannot be identified, a restart can silently change the version, and a
rollback has nothing to roll back to.

---

### DL-12 — Helm and Terraform sources are pinned

**Severity:** Medium

```bash
jq -r --arg id "<helmId>" '.results[]? | select(.id == $id)
  | {name, source, values_override: ((.values_override // {}) | keys)}' \
  raw/env/<envId>/services.json
```

**Fails when:** a Helm chart tracks a floating version or a Git branch rather than a
pinned chart version or commit.

---

### DL-13 — Git webhooks are healthy

**Severity:** High (where `auto_deploy` is on), Medium otherwise

```bash
# Webhook state per git-sourced service.
for f in raw/service/*/git-webhook-status.json; do
  sid=$(basename "$(dirname "$f")")
  jq -r --arg sid "$sid" '[$sid, (.status // "UNREADABLE"), (.provider // "-"),
    ((.missing_events // []) | join(","))] | @tsv' "$f" 2>/dev/null
done | column -t

# Does Qovery still have access to the repository at all?
# The git source sits at a different path per service type (.git_repository on an
# application, .source.docker.git_repository on a job, .terraform_files_source.git
# on a Terraform service), so match on shape rather than on path.
jq -r '.results[]? | . as $s
  | ([.. | objects | select(has("branch") and has("deployed_commit_id"))][0] // null) as $g
  | select($g != null)
  | [$s.name, $s.service_type, ($s.auto_deploy|tostring), $g.branch,
     ($g.has_access|tostring), ($g.git_token_name // "account")] | @tsv' \
  raw/env/<envId>/services.json | column -t
```

**Fails when:** a service with `auto_deploy: true` reports anything other than `ACTIVE`,
or its git source reports `has_access: false`.

| Status | What it means |
|---|---|
| `ACTIVE` | Webhook present with every required event. |
| `NOT_CONFIGURED` | No Qovery webhook on the repository. Pushes reach nothing. |
| `MISCONFIGURED` | Webhook exists but `missing_events` are not subscribed. Some pushes are ignored, others are not. |
| `UNABLE_TO_VERIFY` | Qovery could not query the provider — the git token lacks the scope to read webhooks, the integration was reinstalled, or the provider rate-limited. Report `UNKNOWN`, not `PASS`. |

**Expect a lot of `UNABLE_TO_VERIFY`.** On a real organization of 199 services, a
60-service sample returned 25 `ACTIVE` and 35 `UNABLE_TO_VERIFY`. Report the distribution
as coverage — "webhook health confirmed for 25 of 60 services sampled" — and score only
the services that answered. Do not present an unverifiable webhook as a failure; an
`UNABLE_TO_VERIFY` cluster concentrated on one git token is itself worth mentioning under
`SC-18`, because the token that cannot read a webhook is often the token that can no longer
install one.

**Why it matters:** this is the quietest failure in the whole delivery chain. `DL-02` reads
`auto_deploy: true` and the team believes merges ship. If the webhook was removed during a
repository migration, or the token that installed it was revoked (`SC-18`), nothing
happens on push and nothing reports an error. The gap is usually found weeks later, when
someone notices production is running code from a sprint ago — which is exactly what
`DL-14` measures.

`MISCONFIGURED` is worse than `NOT_CONFIGURED`, because it works often enough that nobody
distrusts it.

**Recommendation:** reconnect the service's git source, which reinstalls the webhook with
the full event set. Where `has_access` is false, the git token behind the service has been
revoked or has expired — fix it centrally (`SC-18`) rather than per service.

---

### DL-14 — Running code matches the branch

**Severity:** Medium (High in production)

```bash
# What is deployed, per service — same shape match as DL-13.
jq -r '.results[]? | . as $s
  | ([.. | objects | select(has("branch") and has("deployed_commit_id"))][0] // null) as $g
  | select($g != null)
  | [$s.name, $s.service_type, $g.branch,
     ($g.deployed_commit_id // "none")[0:8],
     ($g.deployed_commit_date // "-")[0:10],
     ($g.deployed_commit_tag // "-")] | @tsv' \
  raw/env/<prodEnvId>/services.json | column -t

# What the branch head actually is (the commit list is newest first).
# A 404 here is EVIDENCE, not a gap in the data: the API answers
# "Cannot get last commit on <owner>/<repo> <branch>. Verify that the repository or
# branch still exists" — the service points at a repository or branch that is gone.
jq -r '.results[0] | [.git_commit_id[0:8], .created_at[0:10], .author_name] | @tsv' \
  raw/service/<id>/commits.json

# How far behind: position of the deployed commit in the last 100.
jq -r --arg dep "<deployed_commit_id>" \
  '[.results[]? | .git_commit_id] | index($dep) as $i
   | if $i == null then "deployed commit not in the last 100 on this branch"
     else "\($i) commits behind head" end' raw/service/<id>/commits.json
```

**Fails when:** a production service is more than ~20 commits or ~30 days behind its
configured branch, the deployed commit does not appear on that branch at all, or the
commit endpoint returns **404** — the repository or branch the service deploys from no
longer exists.

That last case is more common than it sounds: on the organization this check was built
against, 18 of 40 sampled applications returned 404. Most were long-dead demo services,
which is the point — a service still configured against a repository nobody can reach
cannot be deployed, and nothing in the Console says so until someone tries.

**Why it matters:** the branch is what the team reads when they ask "what is in
production". When the two have drifted, every subsequent judgement is made against the
wrong code: the incident review reads a fix that was never deployed, and the next deploy
ships a quarter of accumulated change instead of one commit. A deployed commit that is
**not on the branch** is the sharper version — the history was rewritten, or the service
was deployed from somewhere else, and nothing in Qovery records which.

Distinguish the two causes before writing the finding. Drift with a broken webhook is
`DL-13` and the remedy is technical. Drift with a healthy webhook and `auto_deploy: false`
is a process finding: the gate exists, nobody walks through it.

**Recommendation:** deploy, then decide whether the gap was intentional. If production is
deliberately pinned behind the branch, say so in the environment description so the next
reader does not have to guess.

---

## Hand-off map

Every finding in this assessment should point at what comes next. Use this mapping in
the report's "Where Qovery helps" section:

| Finding cluster | Next step |
|---|---|
| `RL-14`, `CE-02`, `CE-03` — sizing and elasticity | `qovery-optimize` (KRR-based, uses real consumption) |
| `RL-22`, `DL-06` — slow or failing pipeline | `qovery-speedup`, then `qovery-troubleshoot` for a specific failure |
| `DL-07` — no infrastructure-as-code | `qovery-terraform` |
| `DL-13`, `DL-14` — broken webhook or stale deployed commit | `qovery-troubleshoot` for the failing hook, then redeploy |
| `SC-17` — broad API tokens | `qovery-policy-token` |
| `TP-03`, `TP-09` — no isolated developer environments | `qovery-preview` |
| `CL-08` — no observability | Enable Qovery observability, then re-run this assessment |
