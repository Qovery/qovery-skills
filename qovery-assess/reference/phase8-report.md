## Phase 8: Writing the Deliverable

The report is the product. It goes to a customer, is read by people who were not in the
session, and is often forwarded to a CTO or an auditor. Write it accordingly.

Copy `templates/report-template.md` (linked from `SKILL.md`) and fill every
`{{placeholder}}`. Copy `templates/findings.csv` and append one row per finding.

```bash
mkdir -p qovery-assessment
cp templates/report-template.md qovery-assessment/qovery-assessment-{{org-slug}}.md
cp templates/findings.csv        qovery-assessment/findings.csv
```

### What makes this document good

**Evidence, not assertion.** Every finding cites the value that produced it:

> ❌ "Some services are not highly available."
> ✅ "4 of 12 production services run `min_running_instances: 1` — `api-gateway`,
> `billing-worker`, `notification-service`, `admin-backend`. A node drain during a
> cluster upgrade takes each of them fully offline for the duration of a pod
> reschedule."

**Impact in the customer's terms.** Translate the setting into the consequence. Not
"anti-affinity is not set" but "both replicas of `checkout-api` can be scheduled on the
same node, so the second replica does not protect against the failure it was added for."

**Grouped by check, ordered by severity.** Fourteen instances of one problem are one
finding with fourteen named instances — never fourteen findings.

**Named and countable.** "Several services" is unactionable. List them. If a list is
longer than ~15 entries, give the count and the first 10 plus "…and N more (full list in
the CSV)".

**Honest about what was not checked.** The Limitations section is a credibility
feature, not a disclaimer. It is what separates an assessment from a sales document.

### Tone

Write for a senior engineer who is competent and busy, and whose setup this is. They
made these choices for reasons — often good ones, sometimes under time pressure. The
document should read like a colleague who reviewed the configuration carefully, not
like a scanner that printed its output.

- No blame, no "you failed to…". Describe the configuration and its consequence.
- No hedging either. If a production database is public, say it plainly and put it first.
- Acknowledge the constraint when you can see it: a single shared cluster is usually a
  budget decision, not an oversight. Say so, then quantify the risk it carries.
- Never pad. If a pillar is in good shape, that section is three lines.

### Structure

The template implements this order. It is deliberate: risk first, roadmap before
detail, so the document is useful to someone who reads only the first page.

1. **Executive summary** — scorecard, maturity level, top 5 risks, what is already strong.
2. **Scope & method** — what was assessed, when, the read-only statement, the Phase 1.3
   assumptions, and the check coverage numbers.
3. **Platform topology** — clusters, projects, environments, services. A table and, where
   it helps, a small diagram. This is also where the customer verifies you assessed the
   right thing.
4. **Findings by pillar** — Reliability, Security, Performance, Delivery, Cost. Each
   finding: ID, severity, what was found, evidence, impact, recommendation, effort.
5. **Remediation roadmap** — Now / Next / Later.
6. **Where Qovery helps** — see below.
7. **Appendix** — full check results including passes, inventory, limitations.

### Effort estimates

Use three bands, and be conservative — an estimate that turns out optimistic damages
trust more than a vague one.

| Band | Meaning |
|---|---|
| **S** | A configuration change and a redeploy. Minutes to an hour. |
| **M** | Coordinated change across services, or a change needing a test cycle. Days. |
| **L** | Architectural: a new cluster, a database migration, an IaC rollout. Weeks. |

### The roadmap

Sequence by risk-reduction per unit of effort, not by severity alone. A Critical
finding that needs a database migration (L) can sit behind three High findings that are
each an S.

| Horizon | Contents |
|---|---|
| **Now** (this week) | All unresolved Criticals that are S or M. Anything exposing data. |
| **Next** (this quarter) | Remaining Criticals, all Highs, and the L-effort structural work. |
| **Later** (next quarter+) | Mediums, Lows, and optimizations that need measurement first. |

Each roadmap row names an owner slot ("platform team", "service owner") so the document
converts into a plan rather than a list.

### The "Where Qovery helps" section

This is what turns an audit into a partnership conversation — and it is the section
most likely to be read by whoever approves budget. Two rules keep it credible:

1. **It comes after the findings, and it maps to them.** Every row references specific
   finding IDs from this report. A generic capabilities list here reads as a pitch and
   devalues everything above it.
2. **It is honest about what the platform does not solve.** Qovery can enforce a
   configuration; it cannot decide a customer's availability target, test their restore
   procedure, or know which endpoint their liveness probe should hit. Naming those
   explicitly is what makes the rest believable.

Structure it in three parts:

**What the platform already handles** — the findings that are a setting away, because
Qovery already implements the control (anti-affinity, zone spread, rolling update
strategy, managed database mode, private accessibility, scheduled environments, staged
pipelines). Frame as: "these are configuration changes, not engineering projects."

**What the Qovery skills automate** — use the hand-off map at the end of
`phase6-delivery-ops-checks.md`. Name the skill and what it produces.

**Where the Qovery team works alongside yours** — the work that needs judgement rather
than tooling, and where a platform partner earns their place:

- Choosing availability targets per service, and sizing the architecture to them.
- Designing the staging↔production parity model so tests mean something.
- Reviewing health check semantics against what each service actually depends on.
- Planning a database migration from container to managed with a rehearsed cutover.
- Running a restore drill, and a game day against the top findings in this report.
- Establishing the alerting baseline — what pages a human at 3am and what does not.
- Re-running this assessment on a cadence so the score tracks real progress.

Keep it factual and specific to their findings. No superlatives.

### Deliver it

Produce three artifacts, and say where each one is:

1. `qovery-assessment/qovery-assessment-{{org-slug}}.md` — the shareable document.
2. `qovery-assessment/findings.csv` — every finding, for import into a tracker.
3. `qovery-assessment/raw/` — the snapshot the findings were derived from.

Then offer — do not perform — the hand-off:

> "This assessment made no changes. When you want to act on it, I can pick up any of
> these: `qovery-optimize` for the sizing findings, `qovery-terraform` to put this
> configuration under version control, or work through the Now items one at a time with
> you confirming each change."

### Reassessment

Note at the end of the report that re-running `qovery-assess` after remediation
produces a comparable score, since check IDs and the formula are stable. That is what
makes the number worth anything.
