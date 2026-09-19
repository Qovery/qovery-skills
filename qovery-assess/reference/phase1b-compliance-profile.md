## Phase 1b: Compliance Profile (CP checks + severity lens)

Run this immediately after the inventory, **before** scoring anything. What a company
publicly claims about its security posture sets the bar its configuration is measured
against — and a gap that contradicts a public claim is a materially different finding from
the same gap at a company that claims nothing.

This phase does two jobs:

1. **Four CP checks** that stand on their own.
2. **A severity lens and a badge set** applied to every other check in the assessment.

---

### 1b.1 Find what the organization publicly claims

The organization record carries the website:

```bash
jq -r '{name, website_url, plan}' raw/organization.json
```

Then read the public pages where compliance posture is stated. Fetch each; absence is as
informative as presence:

| Page | Typical URL | What it tells you |
|---|---|---|
| Trust centre / security | `/trust`, `/security`, `trust.<domain>` | Certifications held, audit dates, pen-test cadence |
| Privacy policy | `/privacy`, `/privacy-policy` | GDPR posture, data residency, retention, DPO |
| Sub-processors | `/subprocessors`, `/sub-processors`, often inside the DPA | Which clouds and regions actually hold customer data |
| Terms / DPA | `/terms`, `/dpa`, `/legal` | Contractual security commitments, SLAs, breach notification |
| Certifications page | `/compliance`, footer badges | SOC 2, ISO 27001, PCI DSS, HIPAA, ISO 22301 |

Record, verbatim and with the source URL, every claim of the form "we are SOC 2 Type II
certified", "ISO 27001 certified", "GDPR compliant", "PCI DSS Level 1", "HIPAA compliant",
"DORA", "data stored in the EU". Note the date of any audit or report mentioned.

**Also infer from the business itself.** A company does not have to publish a claim for an
obligation to apply:

| Signal | Likely regime |
|---|---|
| Regulated financial services, e-money, funds, payments (EU) | DORA, plus the national regulator's ICT requirements |
| Card payments touched directly | PCI DSS |
| Health data | HIPAA (US), or health-specific national rules |
| EU personal data at any scale | GDPR Art. 32 (security of processing) |
| Selling to enterprises | SOC 2 Type II / ISO 27001 as a commercial requirement |
| Public sector | The relevant national baseline |

> **Stay factual and stay in your lane.** This is *not* a legal or audit opinion, and it must
> never be written as one. You are correlating publicly stated claims with technically
> observable configuration. Say exactly that in the report, and say that a formal assessment
> against any framework is the auditor's job, not this document's.

---

### 1b.2 The severity lens

Once the profile is set, apply it to every check in Phases 2–6c:

| Profile | Effect on severity |
|---|---|
| No stated obligation, no regulated activity | Baseline severities as written in the phase files |
| Enterprise sales / SOC 2 or ISO claimed | **+1 level** on traceability, retention, access control and encryption checks: `CL-10`, `SC-15`, `SC-16`, `SC-17`, `SC-19`, `VS-07`, `OP-01`, `OP-03`, `OP-04`, `DR-01`, `DR-03` |
| Regulated (DORA / PCI DSS / HIPAA) or health, financial, payment data | **+1 level** on all of the above **plus** `SC-01`, `SC-03`, `SC-13`, `SC-14`, `LG-06`, `DR-02`, `DR-05`, `DR-06`; and any Critical finding here is reported as a **compliance-relevant** finding |

Apply the lens once, record it in the report's Scope section, and never apply it twice.

---

### 1b.3 Badges

Tag each finding with the framework controls it maps to. Keep badges to the frameworks in
the profile — badging a finding with PCI DSS at a company that never touches card data is
noise, and it makes the whole document look automated.

| Check | SOC 2 (TSC) | ISO 27001:2022 | GDPR | DORA / PCI DSS |
|---|---|---|---|---|
| `SC-01` public database | CC6.1, CC6.6 | A.8.20, A.8.22 | Art. 32(1)(b) | PCI 1.3 |
| `SC-03` open K8s API | CC6.1, CC6.6 | A.8.20 | Art. 32(1)(b) | PCI 1.2 |
| `SC-04` unintended public ports | CC6.1 | A.8.20 | Art. 32(1)(b) | PCI 1.3 |
| `SC-05` HTTPS enforcement | CC6.7 | A.8.24 | Art. 32(1)(a) | PCI 4.1 |
| `SC-08` / `VS-01` secrets as variables | CC6.1, CC6.3 | A.8.24, A.5.15 | Art. 32(1)(a) | PCI 3.5, 8.2 |
| `LG-06` credentials in logs | CC6.1, CC7.2 | A.8.15, A.8.24 | Art. 32(1)(a), Art. 33 | PCI 3.3, 10.3 |
| `SC-10` / `SC-11` workload hardening | CC6.8 | A.8.9 | Art. 32(1)(b) | DORA ICT risk |
| `SC-13` IMDSv2 | CC6.6 | A.8.20 | Art. 32(1)(b) | — |
| `SC-14` disk encryption | CC6.1 | A.8.24 | Art. 32(1)(a) | PCI 3.4 |
| `SC-15` SSO | CC6.1, CC6.2 | A.5.16, A.5.17 | Art. 32(1)(b) | DORA access mgmt |
| `SC-16` admin minimisation | CC6.2, CC6.3 | A.5.15, A.5.18 | Art. 32(1)(b) | DORA access mgmt |
| `SC-17` token scoping | CC6.1, CC6.3 | A.5.15, A.8.2 | Art. 32(1)(b) | PCI 7.1, 8.6 |
| `SC-19` / `CL-10` logging & retention | CC7.2, CC7.3 | A.8.15, A.8.16 | Art. 30, Art. 33 | PCI 10.5, DORA logging |
| `OP-01` change via Terraform | CC8.1 | A.8.32 | — | DORA change mgmt |
| `OP-03` interactive prod access | CC6.1, CC7.2 | A.8.15, A.8.18 | Art. 32(1)(b) | PCI 10.2, DORA |
| `OP-04` access change audit | CC6.2 | A.5.18 | Art. 30 | PCI 10.2 |
| `DL-05` alerting | CC7.2 | A.8.16 | Art. 33 (breach detection) | DORA incident detection |
| `RL-16` / `BP-03` DB durability | A1.2 | A.8.13, A.8.14 | Art. 32(1)(c) | DORA resilience |
| `DR-02` backups off-cluster | A1.2 | A.8.13 | Art. 32(1)(c) | DORA backup |
| `DR-03` restore tested | A1.3 | A.8.13, A.5.30 | Art. 32(1)(d) | DORA testing |
| `DR-05` multi-AZ / region | A1.2 | A.5.29, A.8.14 | Art. 32(1)(c) | DORA continuity |
| `DR-06` rehearsed runbook | A1.3, CC7.4 | A.5.29, A.5.30 | Art. 32(1)(d) | DORA response |

Render a badge as the short control reference only (`SOC 2 CC6.1`, `ISO A.8.24`,
`GDPR Art. 32`, `DORA`), never a claim of compliance or non-compliance with it.

---

### CP-01 — Public compliance claims are identified and recorded

**Severity:** Info (this check never scores; it sets up the others)

Record every claim with its source URL and date. If no claims exist, say so plainly — many
companies are in that position legitimately, and it lowers rather than raises the bar.

---

### CP-02 — Stated data residency matches where workloads actually run

**Severity:** High when a residency claim exists

```bash
jq -r '.results[] | [.name, .cloud_provider, .region] | @tsv' raw/clusters.json
jq -r '.results[] | select(.service_type=="DATABASE") | [.name, .mode, .type] | @tsv' raw/services.json
```

Compare cluster regions and managed-database locations with the privacy policy's residency
statement and the sub-processor list. **Fails when** a policy says "data is stored in the
EU" and a cluster, a database, a registry, or a log destination sits elsewhere.

Also check the sub-processor list against what is actually deployed: an observability or
error-tracking vendor receiving production data, deployed as a Helm chart but absent from
the published sub-processor list, is a genuine and commonly missed gap.

```bash
jq -r '.results[]? | select(.service_type=="HELM") | .name' raw/services.json
jq -r '.results[]? | [.kind, .url] | @tsv' raw/container-registries.json
```

---

### CP-03 — Technical controls support the frameworks claimed

**Severity:** High when a certification is claimed

Cross-tabulate the claim against what this assessment observed. The output is a small table
in the report:

| Claim | Controls this assessment can see | Observed |
|---|---|---|
| SOC 2 Type II | Access control, audit logging, encryption, availability, change management | `SC-15`, `SC-16`, `SC-17`, `SC-19`, `OP-01`, `OP-04`, `DR-02` results |
| ISO 27001 | Same, plus continuity | Add `DR-03`, `DR-05`, `DR-06` |
| GDPR Art. 32 | Encryption, confidentiality, availability, restore capability | `SC-01`, `SC-14`, `LG-06`, `DR-02`, `DR-03` |
| DORA | ICT risk, resilience testing, incident detection, change control | `DL-05`, `DR-*`, `OP-01`, `OP-03` |

**Fails when** a publicly claimed certification is contradicted by an observable control gap
— for example an organization advertising SOC 2 Type II with no SSO, admin-scoped shared
API tokens, and no alerting.

**How to word it:** *"The public trust page states SOC 2 Type II. This assessment observed
`SC-17` (three shared admin-scoped API tokens) and `DL-05` (no alerting configured), which
are the kinds of controls a SOC 2 audit examines under CC6.1 and CC7.2. Worth confirming
how these are evidenced in the current report period."* Raise the question; do not render a
verdict.

---

### CP-04 — Findings that contradict a public claim are escalated

**Severity:** inherits, +1 level

Any finding whose badge set intersects a **claimed** framework is promoted one severity
level and marked in the report with a compliance badge. This is the mechanism by which the
lens in 1b.2 is actually applied — apply it here, once, and record the promotion in the
finding so the reader can see why the severity is what it is.
