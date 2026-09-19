## Phase 6f: Measured data from an external observability platform (optional)

Six checks — `CE-03`, `CE-07`, `CE-08`, `CE-09`, `CE-11` and `RL-14` — need measured CPU,
memory and storage against what is requested. They read Qovery's own metrics stack, so when
a customer runs Datadog, New Relic, Grafana or CloudWatch instead, those checks resolve
UNKNOWN even though the data plainly exists.

This phase closes that gap. **It is optional, it is opt-in, and it is the only part of this
skill that talks to a system other than Qovery.** Skip it entirely and the assessment is
still complete — the six checks stay UNKNOWN with a reason, which is the honest default.

Run `templates/scripts/detect-observability-access.sh` first. Which platform to ask about
comes from the `CL-08` detection in Phase 2.

---

### 6f.1 Never take the credential from the cluster

**The platform's key is almost certainly in the estate. Do not use it.**

`DD_API_KEY`, `NEW_RELIC_LICENSE_KEY` and their equivalents are usually held as Qovery
secrets, and Qovery's API never returns a secret's value — the object has no `value` field at
all. So the normal case is that it is not obtainable, and that is the correct behaviour, not
an obstacle to work around.

The case that needs a rule is the other one: sometimes a read-capable key sits in a **plain
variable**, where the value *is* readable. Using it would be wrong on three counts, and none
of them is softened by how convenient it is:

1. It was provisioned so an agent could ship telemetry. Querying a vendor API from the
   assessor's machine is a different purpose, and the customer authorized an assessment of
   their Qovery configuration, not that.
2. A readable credential in a plain variable **is finding `VS-01`**. Using it means exploiting
   the vulnerability the report is about to raise.
3. Submission keys and read keys are usually different objects — a Datadog API key submits,
   an Application key reads — so the key that is exposed is typically the wrong one anyway.

There is no exception. If the only path is a credential found in the snapshot, the answer is
that this phase does not run.

---

### 6f.2 Prefer a route that handles no credential at all

In this order. Stop at the first that works.

| Route | Why it ranks here |
|---|---|
| **1. An MCP server for the platform** | Check your own tool list — Datadog, Grafana, New Relic and others publish one. Brokered per call, nothing handled, nothing stored. Always prefer it |
| **2. An already-authenticated local CLI** | `detect-observability-access.sh` reports these. The credential stays in the tool's own store and never passes through the conversation. `aws` is the common win: if CloudWatch Container Insights is on, the data is there and the customer's existing session already reaches it |
| **3. A read-only key the user creates for this** | Only when 1 and 2 fail, and only after asking. See below |

---

### 6f.3 Asking — what to say before the user creates anything

This is an outward-facing action: it authenticates to a third party, appears in that
platform's audit log, and counts against their rate limits. Ask once, plainly, and include
all four of these:

- **What is missing** — name the six checks and what each would produce.
- **What will be queried** — the specific metrics, the time window, read-only, nothing written.
- **What permission to ask for** — the narrowest that works (below), not "an API key".
- **That they can decline** — the assessment completes without it; those checks stay UNKNOWN.

**Ask for the narrowest credential the platform offers, and a short expiry.** Do not accept
an admin key because it is what someone had to hand. Vendor console paths move, so confirm
the current one in the platform's own documentation rather than reciting a menu path:

| Platform | Ask for | Notes |
|---|---|---|
| **Datadog** | An **Application key** created by a user holding the read-only role, plus the org's API key. Scope to `timeseries_query` / `metrics_read` | An Application key inherits the *creating user's* permissions — a key made by an admin is an admin key regardless of scopes |
| **New Relic** | A **User key** on an account whose role is read-only | Queried through NRQL / NerdGraph |
| **Grafana Cloud** | An access-policy token with `metrics:read`, or a service account with the **Viewer** role | Viewer is genuinely read-only |
| **Prometheus (self-hosted)** | A read-only proxy user, or a reachable query URL | Often unauthenticated inside the VPC — then no credential exists to hand over |
| **Dynatrace** | An access token scoped to `metrics.read` | |
| **CloudWatch** | An IAM principal with `cloudwatch:GetMetricData`, `GetMetricStatistics`, `ListMetrics` | Usually already available via their existing AWS session — try route 2 first |
| **Honeycomb** | An API key with query permission only | |

---

### 6f.3b What a validated external measurement does to the score

A figure read from the customer's own observability platform is **evidence**, and it
resolves the check it answers. `CE-03`, `CE-07`, `CE-08`, `CE-09`, `CE-11` and `RL-14` are
`UNKNOWN` by default because Qovery's metrics endpoint returns nothing; a P95 from Datadog
or CloudWatch is a better answer than that endpoint would have given, not a worse one.

So when a measurement is obtained and validated:

1. The check moves from `UNKNOWN` to `PASS`, `PARTIAL` or `FAIL` on the measured value, and
   **enters scoring** like any other resolved check. Update the coverage line: the
   `UNKNOWN` count drops.
2. Record it as a distinct evidence class in the findings table — `measured (Datadog, 30d
   P95)` rather than a bare number — so a reader can tell it apart from a
   configuration-derived result and reproduce it.
3. If the platform was read but the metric was absent or the window too short to be
   meaningful, the check stays `UNKNOWN`. A measurement you cannot defend is worse than an
   admitted gap.

The method section must name the platform, the window, and the statistic, or the number is
not reproducible and should not be in the document.

### 6f.4 Handling the credential

If a key is supplied, it is under the same rules as the Qovery token, and one more:

| Rule | |
|---|---|
| Read it from the environment | The user sets it in their own shell, and never by typing the value into a command. `read -r -s DD_APP_KEY && export DD_APP_KEY` keeps it out of shell history; `export DD_APP_KEY=<value>` does not. Never from a chat message, never from a file you create |
| Never print, echo or log it | Not in a command you show, not in an error, not in the report |
| Never persist it | No config file, no snapshot directory, no shell history |
| Use it for the stated queries only | The window and metrics you named when you asked. Not "while we are here" |
| Tell them to revoke it | When the assessment is delivered. Put it in the report's method section |

---

### 6f.5 What to fetch

Only what the six checks need. Resist the pull of a platform full of interesting data — a
broader query is a broader disclosure and a longer audit-log entry to explain.

| Check | Needs | Typical metric |
|---|---|---|
| `CE-07` / `RL-14` | CPU used vs requested, P95 over ≥7 days | `container.cpu.usage` vs `kubernetes.cpu.requests` |
| `CE-08` | Memory used vs requested, P95 and max | `container.memory.usage` vs `kubernetes.memory.requests` |
| `CE-09` | Volume used vs provisioned | `kubernetes.filesystem.usage_pct` |
| `CE-11` | Node allocatable vs sum of requests | `kubernetes.cpu.capacity`, `kubernetes.memory.capacity` |
| `CE-03` | Whether any of the above informed the current sizing | Answered by the numbers plus the team |

**Use a window of at least 7 days, and prefer P95 over mean.** A mean over a day hides the
peak that sizing has to survive, and a week is the shortest window that contains a weekend —
which for most products is the difference between the two workloads the platform serves.

---

### 6f.6 Reporting it

Mark these findings as a **distinct evidence class**, exactly as with in-cluster MCP
observations: they are point-in-time measurements from a third-party system, taken at a
different moment from the configuration snapshot, and the two can legitimately disagree.

In the method section, record: which platform, which route was used (MCP, local CLI, or a
user-supplied key), the window queried, and — where a key was supplied — that it should now
be revoked. A customer reconciling this against their own audit log should find exactly what
this document says they will find.
