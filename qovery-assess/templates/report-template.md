# Qovery Platform Assessment — {{organization_name}}

**Prepared for:** {{customer_team}}
**Prepared by:** {{author}}
**Assessment date:** {{assessment_date}}
**Scope:** Qovery organization `{{organization_id}}` — all clusters, projects, environments and services
**Method:** read-only configuration review. No change was made to the environment.

---

## 1. Executive summary

{{two_or_three_sentences: what this organization runs, what state it is in, and the
single most important thing to act on.}}

### Scorecard

| Pillar | Score | Level | Headline |
|---|---:|---|---|
| Reliability & Resilience | {{rl_score}}/100 | {{rl_level}} | {{rl_headline}} |
| Security & Data Protection | {{sc_score}}/100 | {{sc_level}} | {{sc_headline}} |
| Performance & Scalability | {{pf_score}}/100 | {{pf_level}} | {{pf_headline}} |
| Delivery & Operations | {{dl_score}}/100 | {{dl_level}} | {{dl_headline}} |
| Cost Efficiency | {{ce_score}}/100 | {{ce_level}} | {{ce_headline}} |
| **Overall** | **{{overall_score}}/100** | **{{maturity_level}}** | {{overall_headline}} |

{{if_capped: The overall level is capped at Level 2 because {{count}} Critical
finding(s) remain unresolved — see {{finding_ids}}.}}

**Coverage:** {{total_checks}} checks defined, {{evaluated}} evaluated,
{{not_applicable}} not applicable, {{unknown}} could not be determined.

### Top risks

| # | ID | Severity | Compliance | Risk | Impact if unaddressed | Effort |
|---|---|---|---|---|---|---|
| 1 | {{id}} | {{severity}} | {{badges, or —}} | {{risk}} | {{impact}} | {{S/M/L}} |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |

### What is already strong

{{3–6 bullets naming the practices that are genuinely in place, with the evidence.
This is not padding — it tells the team what not to regress.}}

---

## 2. Scope & method

**Assessed:** {{n_clusters}} clusters, {{n_projects}} projects, {{n_environments}}
environments, {{n_services}} services.

**How:** configuration was read through the Qovery public API using GET requests only,
and evaluated against {{total_checks}} checks across six categories (`CL` cluster,
`TP` topology, `RL` reliability, `SC` security, `DL` delivery, `CE` cost). Each check
is scored by severity, weighted by environment criticality, and aggregated into the
pillar scores above. Check IDs are stable, so a reassessment produces a directly
comparable score.

**Assumptions** (correct any that are wrong — they change the severity ratings):

| Assumption | Value |
|---|---|
| Business-critical environments | {{critical_envs}} |
| Availability target | {{availability_target}} |
| Report audience | {{audience}} |

### Compliance profile

Derived in Phase 1b from {{organization_name}}'s public statements and regulated activity.
It sets the bar this assessment measures against, and promotes the severity of the checks
listed below. This is a correlation of public claims with observable configuration — **not
a legal opinion, and not an audit against any framework**.

| Source | Claim | URL |
|---|---|---|
| {{page}} | {{claim, verbatim}} | {{url}} |

**Applicable regimes:** {{frameworks}}
**Severity lens applied:** {{which checks were promoted, and why}}

Findings carrying a compliance badge map to a control that the named framework examines.
A badge indicates relevance, never compliance or non-compliance with that control.

**What this assessment is not:** it is a review of the Qovery-layer configuration. It is
not a penetration test, not an application security or code review, not a cloud-account
audit, and not a performance benchmark. See Limitations in the appendix.

---

## 3. Platform topology

### Clusters

| Cluster | Cloud / Region | K8s | Nodes (min–max) | Instance type | Production | Observability | Status |
|---|---|---|---|---|---|---|---|
| {{name}} | {{provider}} / {{region}} | {{version}} | {{min}}–{{max}} | {{type}} | {{yes/no}} | {{on/off}} | {{status}} |

### Environments

| Project | Environment | Mode | Cluster | Services | State |
|---|---|---|---|---|---|
| {{project}} | {{env}} | {{mode}} | {{cluster}} | {{n}} | {{state}} |

### Service inventory

| Type | Production | Staging | Development | Preview | Total |
|---|---:|---:|---:|---:|---:|
| Applications | | | | | |
| Containers | | | | | |
| Databases | | | | | |
| Jobs | | | | | |
| Helm charts | | | | | |
| **Total** | | | | | |

---

## 4. Findings

Findings are grouped by pillar and ordered by severity. Each carries a stable ID for
tracking. The full machine-readable list, including passing checks, is in
`findings.csv`.

### 4.1 Reliability & Resilience — {{rl_score}}/100

#### {{ID}} — {{title}}

- **Severity:** {{severity}} {{if promoted: "(raised from {{base}} — {{framework}} applies)"}}
- **Compliance:** {{badges, or "no framework mapping"}}
- **Scope:** {{n_affected}} of {{n_applicable}} {{unit}} — {{named_instances}}
- **Finding:** {{what the configuration is}}
- **Evidence:** `{{field}}: {{value}}` {{from which resource}}
- **Impact:** {{the concrete consequence, in the customer's operational terms}}
- **Recommendation:** {{the specific change}}
- **Effort:** {{S/M/L}}

{{repeat per finding}}

### 4.2 Security & Data Protection — {{sc_score}}/100

{{same structure}}

### 4.3 Performance & Scalability — {{pf_score}}/100

{{same structure}}

### 4.4 Delivery & Operations — {{dl_score}}/100

{{same structure}}

### 4.5 Cost Efficiency — {{ce_score}}/100

{{same structure. No savings figures unless they were measured — point at
`qovery-optimize` for quantified estimates.}}

---

## 5. Remediation roadmap

Sequenced by risk reduced per unit of effort, not by severity alone.

### Now — this week

| ID | Action | Effort | Owner | Risk removed |
|---|---|---|---|---|
| {{id}} | {{action}} | {{S/M/L}} | {{owner}} | {{risk}} |

### Next — this quarter

| ID | Action | Effort | Owner | Risk removed |
|---|---|---|---|---|

### Later — beyond this quarter

| ID | Action | Effort | Owner | Risk removed |
|---|---|---|---|---|

---

## 6. Where Qovery helps

### Already in the platform — configuration, not engineering

{{The findings that are a setting away because Qovery already implements the control.
Name the finding IDs and the setting. Make the point that these are hours, not projects.}}

| Finding | Qovery capability | Change |
|---|---|---|
| {{ids}} | {{capability}} | {{what to set}} |

### Automated by the Qovery skills

| Finding | Skill | What it produces |
|---|---|---|
| {{ids}} | `qovery-optimize` | Measured right-sizing from real consumption, with a cost report |
| {{ids}} | `qovery-speedup` | Deployment timeline breakdown and the fixes that shorten it |
| {{ids}} | `qovery-terraform` | Terraform manifests generated from this live setup, state imported |
| {{ids}} | `qovery-policy-token` | Least-privilege API tokens scoped with OPA/Rego |
| {{ids}} | `qovery-preview` | Per-PR preview environments with auto-shutdown |

### Alongside your team

The work below needs judgement about {{organization_name}}'s systems, not tooling. This
is where the Qovery team works as an extension of yours:

- **Availability targets per service** — deciding what actually needs three replicas and
  what does not, and sizing the architecture to that answer rather than uniformly.
- **Staging↔production parity** — designing the model that makes a staging test mean
  something, then keeping the two from drifting.
- **Health check semantics** — reviewing what each probe depends on, so a dependency blip
  degrades instead of cascading. {{reference RL-06 / RL-07 findings}}
- **Database migration planning** — container→managed with a rehearsed cutover and a
  measured restore. {{reference RL-16 / RL-17 findings}}
- **Alerting baseline** — what pages a human at 3am, what waits until morning, and what
  is noise. {{reference DL-05}}
- **Game day** — exercising the top findings in this report against the real system
  before an incident does it first.
- **Reassessment cadence** — re-running this assessment so the score tracks real
  progress against the roadmap.

---

## 7. Appendix

### 7.1 Complete check results

| ID | Check | Pillar | Severity | Result | Scope |
|---|---|---|---|---|---|
| {{id}} | {{title}} | {{pillar}} | {{severity}} | PASS / FAIL / N/A / UNKNOWN | {{scope}} |

### 7.2 Unknowns

Checks that could not be evaluated, and what is needed to close them.

| ID | Why unknown | What would resolve it |
|---|---|---|
| {{id}} | {{reason}} | {{what to provide or enable}} |

### 7.3 Limitations

- Configuration was read at a point in time ({{assessment_date}}); later changes are not reflected.
- Checks depending on runtime behaviour (actual startup time, real resource consumption,
  probe dependency graphs) require cluster observability and, in some cases, answers from
  the team. Those are marked UNKNOWN rather than assumed.
- Application code, container image contents, database schemas, and cloud-account IAM
  outside Qovery's scope were not examined.
- No change was made to the environment during this assessment.

### 7.4 Scoring method

Each check resolves to PASS / FAIL / N/A / UNKNOWN. Checks evaluated across many
services score partial credit (`passing ÷ applicable`). Contributions are weighted by
severity — Critical 10, High 6, Medium 3, Low 1, Info 0 — and aggregated per pillar:
`100 × Σ(weight × fraction) ÷ Σ(weight)`. The overall score weights Reliability 30%,
Security 30%, Performance 15%, Delivery 15%, Cost Efficiency 10%. N/A and UNKNOWN
checks are excluded from both numerator and denominator and disclosed above. Any
unresolved Critical finding caps the maturity level at 2.
