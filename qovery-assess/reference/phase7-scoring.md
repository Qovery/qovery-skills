## Phase 7: Scoring & Maturity Level

The score exists so the customer can track progress across reassessments. That only
works if the formula is **deterministic** — two runs on the same configuration must
produce the same number. Follow this mechanically; do not adjust a score because the
result "feels harsh".

### Step 1 — Resolve each check

Scoring uses exactly four resolutions: `PASS`, `FAIL`, `N/A`, `UNKNOWN`. The report prints
six labels. They are not a second vocabulary — two of them are renderings of a resolution
the arithmetic already produced, and the mapping is fixed:

| Report label | Scoring resolution | How it is produced |
|---|---|---|
| `PASS` | PASS | `fraction_passing == 1` |
| `PARTIAL` | PASS/FAIL mix | `0 < fraction_passing < 1` on a multi-instance check. Scored by the fraction, exactly as Step 2 computes it — `PARTIAL` is what a fraction between 0 and 1 is called in the appendix |
| `FAIL` | FAIL | `fraction_passing == 0` |
| `UNKNOWN` | UNKNOWN | Excluded from scoring, counted in coverage |
| `N/A` | N/A | Excluded from scoring, counted in coverage |
| `OBSERVATION` | — | An Info-severity check. Weight 0, so it never moves a score; it is recorded because the customer needs the observation |

Never invent a seventh. A row whose label is not in this table means the check was not
resolved.

The two excluded resolutions:

- `N/A` — the check does not apply (an AWS-only check on a GCP cluster; a readiness
  probe on a service that receives no traffic). Excluded from scoring entirely.
- `UNKNOWN` — the data could not be read, or the answer depends on information only the
  team has (`RL-07` dependency checks, `RL-17` restore testing). Excluded from scoring,
  **counted and disclosed** in the report.

### Step 2 — Handle checks with many instances

Most `RL-` and `SC-` checks run against every service. Two aggregation modes, and picking
the wrong one is how a score ends up flattering a dangerous configuration.

**Partial credit — the default.** Use it where the risk scales with the number of affected
instances:

```
fraction_passing = (applicable instances that PASS) / (applicable instances)
```

`RL-01` with 12 production services, 4 of which run a single replica, scores
`8/12 = 0.667` — not zero. The finding still reports all 4 by name.

**All-or-nothing — for exposure checks.** Use it where **one** failing instance is the whole
risk, and the compliant instances provide no mitigation whatsoever:

```
fraction_passing = 0 if any applicable instance FAILS, else 1
```

Apply it to: `SC-01` (public database), `SC-03` (open Kubernetes API), `LG-06` (credentials
in logs), `BP-04` (stateful service with neither backup nor replica), `BP-07` (one
environment reaching into another's datastore), `VS-01` (credential value in a plain
variable), `VS-02` (secret in Helm values or job arguments).

**Why the distinction matters — a real example.** An organization with 20 databases, one of
which is internet-facing, scores `19/20 = 0.95` on `SC-01` under partial credit. That single
database is the most severe finding in the entire assessment, and the nineteen private ones
do nothing to reduce its risk; a 95% pass rate is actively misleading. Under all-or-nothing
it scores 0, which is what a reader needs to see.

The unresolved-Critical cap in Step 6 also fires in that case, so the *level* was never
wrong — but the pillar score was, and the pillar score is what a customer tracks between
assessments.

Org-level and cluster-level checks have one instance, so the fraction is 1 or 0 either way.

### Step 3 — Apply severity weight

Use the **context-adjusted** severity — the per-mode adjustment stated in each phase
file, plus the Phase 1.3 answers (a 99.99% availability target or a compliance
obligation promotes a check by one level).

| Severity | Weight |
|---|---|
| Critical | 10 |
| High | 6 |
| Medium | 3 |
| Low | 1 |
| Info | 0 — never scored, and never in the roadmap |

**A check that spans environment modes is scored once per mode, not once overall.** Most
`RL-` checks state a production severity and a "drop one level for staging, two for
development" adjustment, so a single check run across 40 services has no one severity and
therefore no defined weight. Split it into **cohorts by environment mode**, and let each
cohort carry its own fraction and its own weight into the Step 4 sum:

```
RL-01, 12 production services, 4 failing   → fraction 0.667, severity Critical, weight 10
RL-01,  9 staging services,    6 failing   → fraction 0.333, severity High,     weight  6
RL-01, 20 development services             → N/A, excluded
```

Two cohorts, two terms in the pillar sum, no averaging across severities. This is what
makes the score reproducible: pooling them leaves the weight dependent on which mode the
reader happened to think of first. Report the finding once, grouped by check, with the
per-mode counts beside it — the cohort split is a scoring mechanism, not a second finding.

### Step 4 — Compute each pillar

```
pillar_score = 100 * Σ(weight_i × fraction_passing_i) / Σ(weight_i)
```

summed over all scored checks in that pillar (excluding `N/A`, `UNKNOWN`, and Info).

### Step 5 — Compute the overall score

```
overall = 0.30 × Reliability
        + 0.30 × Security
        + 0.15 × Performance
        + 0.15 × Delivery
        + 0.10 × CostEfficiency
```

**Truncate, do not round.** 74.9 is a Level 2 score, and rounding it to 75 promotes the
organization into "Defined" on a tenth of a point — exactly the flattery the "never round up
to a nicer band" rule exists to prevent. Report the truncated integer, and keep one decimal
in the findings CSV so a reassessment can show movement inside a band. If an entire pillar
is `UNKNOWN` (no readable data),
redistribute its weight proportionally across the remaining pillars and say so
explicitly in the report.

### Step 6 — Assign the maturity level

| Overall | Level | What it means |
|---|---|---|
| 90–100 | **4 — Optimized** | Resilient, observable, and cost-aware by default. Remaining work is refinement. |
| 75–89 | **3 — Defined** | Solid production posture. Gaps are known, scoped, and survivable. |
| 55–74 | **2 — Managed** | It works. Reliability depends on individual vigilance rather than on the configuration. |
| < 55 | **1 — Ad hoc** | Structural gaps in availability or data protection. An incident is a matter of time. |

**One override:** any unresolved **Critical** finding caps the overall level at **2**,
whatever the arithmetic says. A 92-point organization with a publicly exposed
production database is not "Optimized". State the cap and its reason in the summary.

---

## Pillar mapping

Every scored check belongs to exactly one pillar. Use this table — do not improvise.
`CP-01` and `CP-04` are mechanisms, not checks: they set the severity lens and the badges,
and never score.

### Reliability & Resilience (weight 0.30 — 42 checks)

```
CL-01  CL-04  CL-05  CL-06  CL-12  CL-15  CL-16  CL-17
TP-01  TP-02  TP-05  TP-06  TP-08
RL-01  RL-04  RL-05  RL-06  RL-07  RL-08  RL-09  RL-10  RL-11  RL-12  RL-13
RL-16  RL-17  RL-18  RL-19  RL-20  RL-21  RL-23
BP-01  BP-02  BP-03  BP-04  BP-05  BP-07
LG-04  LG-05
DR-02  DR-03  DR-05
```

### Security & Data Protection (weight 0.30 — 42 checks)

```
CP-02  CP-03
CL-02  CL-10  CL-11
SC-01 … SC-27
VS-01  VS-02  VS-07  VS-09
LG-06  LG-07
OP-03  OP-04  OP-06
BP-06
```

### Performance & Scalability (weight 0.15 — 9 checks)

```
CL-07  CL-09  CL-14
RL-02  RL-03  RL-14  RL-15
LG-09  LG-10
```

### Delivery & Operations (weight 0.15 — 39 checks)

```
CL-03  CL-08  CL-13
TP-03  TP-04  TP-09  TP-10
RL-22
DL-01 … DL-14
VS-03  VS-04  VS-05  VS-06  VS-08
LG-01  LG-02  LG-03  LG-08
OP-01  OP-02  OP-05  OP-07
DR-01  DR-04  DR-06
BP-08
```

### Cost Efficiency (weight 0.10 — 13 checks)

```
TP-07  TP-11
CE-01 … CE-11
```

---

## The compliance lens

Phase 1b sets a compliance profile from the organization's public claims and its regulated
activity. It changes scoring in exactly one way: **it changes severities before weights are
applied.** Apply it once, at Step 3, and record in the report that you did.

- Promotion is +1 severity level (Medium→High, High→Critical). Critical does not promote
  further.
- Only the checks named in the Phase 1b lens tables promote. Never promote a whole pillar.
- A promoted check carries its framework badges into the findings table and the CSV.
- Promotion can therefore cap the maturity level via the unresolved-Critical rule. That is
  intended: a control gap that contradicts a published certification is a different class of
  problem from the same gap at a company that claims nothing.

Where no claims exist and the activity is unregulated, the lens is a no-op and baseline
severities apply. Say that in the report too — it is a finding that the bar is lower, not an
omission.

---

## Checks that are usually UNKNOWN, and why that is correct

Resolving these to PASS without evidence is the most damaging error this skill can make.

| Check | Needs |
|---|---|
| `RL-07`, `LG-09` semantics | What the liveness endpoint actually touches — ask the team |
| `RL-14`, `CE-03`, `CE-07`, `CE-08`, `CE-09`, `CE-11` | Cluster observability (`CL-08`). Without it these are UNKNOWN, and enabling it is the recommendation |
| `RL-17`, `DR-02` | Backup coverage for managed databases lives in the cloud provider |
| `DR-01`, `DR-03`, `DR-06` | Objectives, rehearsal history and runbooks exist outside any API |
| `BP-03` multi-AZ | A cloud-provider setting Qovery does not expose |
| `OP-05` | Whether an external resource split is deliberate — ask |
| `SC-06`, `SC-07` | Which services are *meant* to be internal |

An assessment where a third of the checks are UNKNOWN is not a failed assessment — it is an
honest one, and the unknowns are a precise list of questions for the follow-up conversation.
Present them that way.

---

## Worked example

A production environment with 10 applications. Reliability pillar, four scored checks:

| Check | Severity | Weight | Instances | Passing | Fraction | Contribution |
|---|---|---|---|---|---|---|
| RL-01 (2+ replicas) | Critical | 10 | 10 | 6 | 0.60 | 6.0 |
| RL-04 (readiness probe) | Critical | 10 | 10 | 10 | 1.00 | 10.0 |
| RL-10 (anti-affinity) | High | 6 | 10 | 2 | 0.20 | 1.2 |
| RL-16 (managed prod DB) | Critical | 10 | 2 | 1 | 0.50 | 5.0 |
| **Total** | | **36** | | | | **22.2** |

`pillar_score = 100 × 22.2 / 36 = 62`

With Security 71, Performance 55, Delivery 60, Cost 40:

```
overall = 0.30(62) + 0.30(71) + 0.15(55) + 0.15(60) + 0.10(40)
        = 18.6 + 21.3 + 8.25 + 9.0 + 4.0 = 61
```

Level 2 — Managed. If one of those databases were `accessibility: PUBLIC`, the
unresolved-Critical rule would cap the level at 2 regardless.

---

## Presenting the score honestly

- **Always disclose coverage:** "147 checks defined, 96 evaluated, 14 not applicable, 25
  unknown." A score computed over 40% of the checks is a different claim from one
  computed over 95%.
- **Never round up to a nicer band.** A 74 is Level 2, not Level 3.
- **Show the passes too.** A report that lists only failures reads as an indictment. The
  customer needs to know what is already right — both because it is true and because it
  tells them what not to break.
- **The score is a conversation opener, not a verdict.** The findings and the roadmap
  are the deliverable; the number is the index into them.
