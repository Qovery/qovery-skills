## Phase 8: Writing the Deliverable

The report is the product. Write it as though it goes to a customer, is read by people who
were not in the session, and is forwarded to a CTO or an auditor — because writing for that
reader is what keeps it evidenced and free of padding.

**But it is not what gets sent.** The full report is an internal qualification artifact: it
finds everything and proves each one, which is exactly what makes it the wrong thing to hand
to a team seeing it for the first time. The customer deliverable is the derived briefing —
five or six findings, each with a concrete offer of help — built in **Phase 8c** (`reference/phase8c-customer-briefing.md`, reached from `SKILL.md`).
Finish this phase first; the briefing is a selection from it and cannot be written without it.

### Pick up the format answered in Phase 1.3b

Three formats, three different artifacts. If Phase 1.3b was skipped, ask now before
writing a word — the choice decides which template gets filled, and discovering it after
forty findings are written means writing them twice.

| Answer | Fill | Ships alongside |
|---|---|---|
| **HTML** (default when unanswered) | `templates/report.html` | `findings.csv` |
| **Markdown** | `templates/report-template.md` | `findings.csv` |
| **Raw** | nothing — deliver `findings.csv` plus the `raw/` snapshot as collected | — |

```bash
mkdir -p qovery-assessment
# HTML — the default
cp templates/report.html qovery-assessment/qovery-assessment-{{organization_name}}.html
# Markdown — when it goes into a repo, a wiki or a review with diffs
cp templates/report-template.md qovery-assessment/qovery-assessment-{{organization_name}}.md
```

**Raw is a real answer, not a cop-out.** When the caller is piping this into their own
tooling, prose is overhead. Deliver the CSV and the snapshot, state the coverage numbers
in the conversation, and stop. Do not write a report nobody asked for.

Whichever format, the content rules below are the same — they are about the argument, not
the markup. The HTML-specific structure is in **The HTML deliverable** further down.

Copy `templates/report-template.md` (linked from `SKILL.md`) and fill every
`{{placeholder}}`. Copy `templates/findings.csv` and append **one row per defined check** —
including `PASS`, `PARTIAL`, `N/A`, `UNKNOWN` and `OBSERVATION` rows, not only the failures.
The CSV and the report's control appendix are the same data in two formats, so a row count
that does not reconcile with the coverage line is a bug in the deliverable. Leave
`severity`, `impact`, `recommendation`, `effort` and `horizon` empty on rows that are not
findings; the example rows in the template show both shapes.

```bash
head -n 1 templates/findings.csv > qovery-assessment/findings.csv   # header only — the
                                                                     # template's rows are examples
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

   **The top-risks table cross-references findings; it does not restate them.** Every row is
   an ID that appears in full under its pillar, and the row carries the one-line risk and
   impact only. Written any other way the table becomes a second, shorter set of findings —
   "no SSO", "shared API tokens", "no alerting" appearing once here and again under Security
   and Delivery — and a reader who notices the duplication starts counting findings twice and
   trusting the document less. If a row cannot be reduced to a pointer plus one line, the
   finding it points at is underwritten; fix it there.
2. **Scope & method** — what was assessed, when, the read-only statement, the Phase 1.3
   assumptions, and the check coverage numbers.
3. **Platform topology** — clusters, projects, environments, services. A table and, where
   it helps, a small diagram. This is also where the customer verifies you assessed the
   right thing.
4. **Findings by pillar** — Reliability, Security, Performance, Delivery, Cost. Each
   finding: ID, severity, what was found, evidence, impact, recommendation, effort.
5. **Architecture diagram** — one figure showing how the environment actually fits
   together. Include it for any environment with more than a handful of services; skip it
   where a sentence does the job. Rules below.
6. **External dependencies & blast radius** — the third-party surface grouped by layer,
   and one row per environment saying what a compromise of it would reach and *by what
   mechanism*. Include it whenever the organization runs more than one environment or
   depends on third parties for anything on the data path; skip it for a single-environment
   setup with no external processors, where it would be an empty table. Method and the
   rules for writing it are in **Phase 5c**.
7. **Remediation roadmap** — Now / Next / Later.
8. **Where Qovery helps** — see below.
9. **Appendix** — every control that was run, the unknowns, limitations, and the scoring method.

### The architecture diagram

Run `templates/scripts/service-graph.sh <snapshotDir> <environment>`. It resolves Qovery
`BUILT_IN` host variables to service names and reports which aliases reference them, which is
where the edges come from.

**Draw the mechanism, not the inventory.** A box per service is a list with rectangles. Draw
the path the product's actual work takes — how a request or a call enters, what it passes
through, where it lands — and leave out the sidecars, the cron jobs and the internal tooling
unless the argument turns on them. If the top finding is structural, the same figure should
show it: the shared cluster with no boundary, the datastore facing the internet, the credential
crossing a tier. One figure carrying both the architecture and the central finding is worth
more than two carrying one each.

**Hand-author inline SVG.** No libraries and no runtime. Use `currentColor` for strokes and
text so it reads in light and dark, reserve one literal colour for the element that carries
the finding, set a `viewBox` and let CSS scale it, and put the figure in the same
`overflow-x` container as the tables so it survives a phone. Give the `<svg>` `role="img"`
and an `aria-label` that states the same claim as the caption. Label every arrow — `calls`,
`transcribes`, `read / write` — an unlabelled arrow only says "related somehow".

**Reconcile the figure against the deployed set before you publish it.** The graph script
builds edges from declared variables, so a service that declares none — or one added after
the snapshot — can be absent from the drawing while running perfectly well in the
environment. A customer who spots their own service missing from your architecture diagram
stops believing the findings too, and they are right to. Diff it:

```bash
# Everything actually deployed in the environment...
jq -r '.results[] | select(.service_type != "DATABASE") | .name' raw/env/<envId>/services.json | sort > /tmp/deployed.txt
# ...against every node the diagram draws. Anything only on the left is a service the
# figure silently dropped: draw it as an unconnected box, or say in the caption why not.
comm -23 /tmp/deployed.txt /tmp/diagram-nodes.txt
```

**Draw the utility and external services too, not only the request path.** Object storage,
queues, mail and payment providers, the analytics sink — these are where the data actually
comes to rest, and an architecture figure that stops at the cluster boundary hides the part
of the estate with the longest retention and the least review. `dependency-surface.sh` and
the Phase 5c dependency map already enumerate them from variable keys; put the ones on the
data path in the figure, at the edge, with a labelled arrow saying what crosses. It is also
what makes the storage conversation possible: a service writing to a persistent volume
*and* to a bucket is usually one of the two by mistake.

**Caption what it proves, and what it does not.** This is the part that is easy to skip and
expensive to get wrong. Service existence, public exposure and datastore wiring are read
directly from configuration. Service-to-service arrows usually are not: aliases declared at
`ENVIRONMENT` or `PROJECT` scope are visible to every service in the environment, so they
establish that *something* in the environment calls a target, not which caller. Only
`SERVICE`-scoped variables attribute an edge to one service, and many organizations have
none. Say which kind you had, and present an unattributed arrow as a question for the team
rather than a proven call. A diagram that overstates its own evidence undermines every
number beside it.

**Where the blast-radius section earns its place:** the rest of the report is a list of
independent findings, and a reader can rank them individually. This section is the only
one that says how they *combine* — that a public database in staging and a shared
credential and a shared cluster are not three Medium problems but one Critical one. Order
the findings so the combination is visible, and say explicitly which single fix breaks the
chain.

### Show every control, not just the failures

The findings section is the argument; the controls appendix is the proof that the argument
is complete. Without it the reader cannot tell whether you ran 135 checks and 19 failed, or
ran 19 checks and reported all of them.

- **One collapsible block per domain**, closed by default, with counts visible on the closed
  state (`SC · Security & Data Protection — 21 checks · 12 pass · 6 fail · 3 unknown`). The
  reader skims twelve lines and opens only what they care about.
- **Every row gets an evidence note**, passes included. `RL-13 PASS — 19 of 19 production
  services have a pre-stop hook` tells a customer something true and verifiable about their
  platform. A bare `PASS` tells them nothing and reads as filler.
- **Never pad the pass column.** If a check was not actually evaluated, it is `UNKNOWN`, not
  `PASS`. Inflating coverage here is the fastest way to make the whole document worthless —
  and it is the one error a technical reader will catch immediately, because they know their
  own system.
- **Explain `N/A` in the note.** "no git-built services — all pre-built images" is a
  reasonable exclusion. An unexplained `N/A` looks like a check that was skipped.

The counts in this appendix must reconcile exactly with the coverage numbers in the Scope
section. If they disagree, the scoring is wrong somewhere.

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

1. `qovery-assessment/qovery-assessment-{{organization_name}}.md` — the shareable document.
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

---

## The HTML deliverable

`templates/report.html` is the structure. It is a complete, working document already —
header, hero, scoreband, table of contents, every section shell, the appendix filter and
the theme toggle. Fill the `{{placeholders}}`, repeat the blocks marked `REPEAT`, and
delete the sections that do not apply. Do not restyle it, and do not regenerate the CSS:
it is Qovery's design system, it is already correct in light and dark, and a hand-rolled
variant will not be.

### The rule that matters most: one file

No build step, no local assets, no second file to send. This document gets forwarded as an
email attachment, dropped in Slack, and opened months later from a Downloads folder — every
one of those breaks the moment it depends on something outside itself. The only permitted
external reference is the Google Fonts link already in the head, and the page is designed
to degrade to system fonts without it. Never add a script tag pointing at a URL, never add
a stylesheet link, never reference an image file. Inline SVG is how a figure gets in.

### Structure

The fourteen sections in the table of contents, in that order. It is the Markdown structure
with three additions that only work in a browser, and each earns its place:

| Section | Notes |
|---|---|
| Hero + scoreband | The whole verdict above the fold: score, level, per-pillar meters, and the estate in one line of facts |
| Executive summary | Prose, a `callout` for what to act on first, and the coverage chips |
| Top risks | `article.finding` blocks — the same component used everywhere |
| What is already strong | `ul.strengths` with ticks |
| Scope, method, compliance | Public claims table, severity lens, assumptions |
| Platform topology | Cluster table, two `grid2` cards, the architecture diagram |
| One section per pillar | Score chip in the heading, then findings |
| Blast radius | How the findings combine |
| Roadmap | Now / Next / Later, one table each |
| Where Qovery helps | |
| Appendix | Every control, filterable |
| Unknowns & method | Grouped unknowns, limitations, scoring formula |

### The finding component

Every finding in the document — Top risks and every pillar section — is one
`article.finding`. Same markup, same four `<dt>` labels in the same order: **Finding,
Impact, Fix, Effort**. The `f-scope` span carries how many instances and which aggregation
applied (`4 of 12 services · partial`, `all-or-nothing`, `organization-wide`), which is
what lets a reader check the score without opening the CSV.

Do not invent a second finding layout for the "smaller" findings. A visually distinct
component reads as a different *kind* of claim, and the reader starts ranking by styling
instead of by severity.

### The appendix filter

Each row carries `data-result="PASS|FAIL|PARTIAL|UNKNOWN|N/A|OBSERVATION"`, and the buttons
read exactly that string. Three ways to break it, all silent:

- A `data-result` that does not match the chip in the same row. The filter and the eye
  disagree and the filter wins.
- A value outside the six. The row becomes invisible to every filter including `All`.
- Counts in the button labels that do not reconcile with the rows. The filter shows the
  truth and the label shows the typo.

Every row needs an evidence note, including the passes. A `PASS` with an empty evidence
cell is indistinguishable from a check that was never run, which is the exact thing the
appendix exists to rule out.

### Accessibility and print, briefly

Both are already handled by the template; the failure mode is undoing them.

- The meters are `role="img"` with an `aria-label` stating the number and the low-evidence
  caveat. A bar with no label is decoration.
- Colour is never the only signal — every chip carries its word (`FAIL`, not a red dot).
- The print stylesheet drops the nav, the ToC and the buttons, and avoids breaking a
  finding across pages. "Print to PDF" is how this becomes an attachment, so check it.
- Tables live inside `div.tablewrap` so they scroll rather than overflow on a phone. A
  table pasted outside one breaks the layout at narrow widths.

### Before shipping

```bash
# 1. No placeholder survived.
grep -o '{{[^}]*}}' qovery-assessment/*.html | sort -u

# 2. Nothing external crept in. Must return nothing.
#    Written without a negative lookahead on purpose: `grep -P` is not portable, and the
#    template's own favicon is a data: URI, so a naive "any link tag" check false-positives.
grep -noE '<script[^>]+src=[^ >]*|<link[^>]+href=[^ >]*|<img[^>]+src=[^ >]*' \
  qovery-assessment/*.html | grep -vE 'href="(data:|https://fonts\.(googleapis|gstatic)\.com)'

# 3. data-result values are all in the allowed six.
grep -o 'data-result="[^"]*"' qovery-assessment/*.html | sort | uniq -c

# 4. The appendix row count reconciles with the coverage line. If it does not,
#    the deliverable is wrong — fix the rows, never the coverage line.
grep -c 'data-result=' qovery-assessment/*.html
```

Then open it. The theme toggle, the filter buttons and the table-of-contents highlight are
real behaviour, and a broken one is visible in about five seconds — which is five seconds
less than the customer will take to find it.
