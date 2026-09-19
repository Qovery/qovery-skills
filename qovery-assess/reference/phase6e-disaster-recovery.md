## Phase 6e: Disaster Recovery & Continuity (DR checks)

Every other pillar asks whether the platform survives a component failing. This one asks
what happens when something larger goes — an availability zone, a region, a corrupted
database, a deleted cluster, a compromised account.

Most of DR cannot be read from an API. Qovery shows the **capability** (backups exist,
multi-AZ is possible, infrastructure is described in code); only the team can confirm the
**practice** (objectives agreed, restores rehearsed, runbook current). Resolve honestly:
mark `UNKNOWN` where the team has not answered rather than inferring a pass from the
presence of a backup.

For a regulated organization, DORA and ISO 22301 expect documented objectives and evidence
of testing — not just the existence of a backup. Apply the Phase 1b lens.

---

### DR-01 — Recovery objectives exist and are written down

**Severity:** High (Critical under a regulatory obligation)

Ask directly — no API answers this:

- **RPO** — how much data may be lost? (the last 5 minutes? the last 24 hours?)
- **RTO** — how long may recovery take? (minutes? a working day?)
- Are these stated **per service**, or one blanket number? A payments ledger and an
  internal admin tool should not share an RPO.
- Who signs off on them, and when were they last reviewed?

**Fails when:** there are no stated objectives, or objectives exist but nothing in the
configuration is sized to meet them.

**Why it matters:** without an RPO and RTO, every other DR decision is arbitrary — you
cannot tell whether daily backups are generous or negligent, and you cannot tell whether a
single-AZ database is acceptable. This is the check that makes the rest of the phase
meaningful, which is why it is first.

**Correlate:** a stated RTO of minutes against a single-AZ managed database (`BP-03`), which
fails over by restoring in tens of minutes, is a contradiction the team may not have
noticed. That correlation is usually the most valuable sentence in this section.

---

### DR-02 — Backups are automated, off-cluster, and cover everything stateful

**Severity:** Critical

```bash
for d in raw/env/*/; do
  [ "$(jq -r .mode "$d/environment.json")" = "PRODUCTION" ] || continue
  jq -r '.results[] | select(.service_type=="DATABASE" or ((.storage // []) | length) > 0)
    | [.id, .name, (.mode // "-")] | @tsv' "$d/services.json"
done | while IFS=$'\t' read -r id name mode; do
  echo "$name	mode=$mode	backups=$(jq -r 'if ._unreadable then "n/a(\(._status))" else (.results|length|tostring) end' "raw/service/$id/backups.json" 2>/dev/null)"
done | column -t
```

**Assess three things, and they are genuinely different:**

1. **Coverage** — is every stateful thing backed up? Managed databases usually are, by the
   cloud provider. Persistent volumes on container services usually are **not**, and that
   gap is the one teams are most often surprised by.
2. **Location** — are backups in a different failure domain from the thing they protect? A
   snapshot in the same account and region survives a database failure but not an account
   compromise or a region event.
3. **Automation** — scheduled, or someone's calendar reminder?

A `404` from the backup endpoint on a managed database is expected — the cloud provider owns
those. Do not report it as "no backups"; report it as "managed by AWS, verify retention and
PITR window in the provider console" and mark `UNKNOWN` until confirmed.

---

### DR-03 — A restore has actually been performed and timed

**Severity:** Critical

No API answers this. Ask: **when did you last restore from a backup, into what, and how long
did it take?**

**Fails when:** the answer is "we haven't", or nobody knows.

**Why it matters:** an untested backup is a hypothesis. The common failure is not the backup
missing — it is the restore taking six hours when the RTO says one, or the backup restoring
successfully but missing a schema the application needs, or nobody holding the credentials
to perform it. Measuring it once converts a hope into a number, and that number usually
changes the architecture conversation.

**This is the single highest-value thing this assessment can prompt**, and it is also the
easiest to offer help with — a timed restore drill against a clone is a contained,
low-risk exercise.

---

### DR-04 — The platform can be rebuilt from code

**Severity:** High

```bash
jq -r '.results[]? | select(.service_type=="TERRAFORM") | [.environment_name, .name] | @tsv' raw/services.json
jq -r '.origin' raw/events.ndjson | sort | uniq -c | sort -rn
```

**Fails when:** the setup is Console-managed with no infrastructure-as-code (`OP-01`,
`DL-07`), so rebuilding after a destructive event means reconstructing it from memory and
screenshots.

**Assess the whole chain**, not just the services: cluster definition, Qovery services,
cloud resources outside Qovery (`OP-05`), DNS, secrets. A gap anywhere in that chain is a
gap in the recovery.

**Recommendation:** `qovery-terraform` generates manifests from the live setup and imports
existing resources into state — the fastest route from "documented nowhere" to "rebuildable".

---

### DR-05 — The failure domain is understood: AZ today, region as a decision

**Severity:** High

```bash
jq -r '.results[] | [.name, .cloud_provider, .region, .min_running_nodes] | @tsv' raw/clusters.json
# Zone spread actually in effect:
for f in raw/service/*/advanced-settings.json; do
  jq -r '."deployment.topology_spread.zone" // "unset"' "$f" 2>/dev/null
done | sort | uniq -c
```

**Two separate questions — do not merge them:**

- **Availability zone** — is the platform resilient to one AZ failing *today*? That is
  `CL-06` (≥3 nodes), `RL-11` (zone spread), and `BP-03` (multi-AZ database). A cluster with
  three nodes and zone spread disabled is single-AZ in practice, whatever the node count
  suggests.
- **Region** — every cluster in one region is a deliberate, usually correct trade-off.
  Multi-region is expensive and complicated, and most organizations should not do it. The
  finding is not "you are single-region"; it is whether that is a **decision with a stated
  consequence** ("a region outage means we are down for N hours, and we accept that") or an
  assumption nobody has tested. Under DORA or ISO 22301 the stated position is the thing
  that gets examined.

---

### DR-06 — There is a runbook, it has owners, and it has been rehearsed

**Severity:** High (Critical under a regulatory obligation)

Ask:

- Is there a written procedure for: database restore, full environment rebuild, cluster
  loss, credential compromise, and a bad deploy that must be rolled back?
- Does it name **people or roles**, not just steps?
- When was it last exercised, and what broke when it was?
- Where does it live — and is it readable when the platform it documents is down? A runbook
  stored only in the system it recovers is not a runbook.

**Fails when:** no runbook exists, or it exists but has never been exercised.

**Why it matters:** DR failures are rarely technical. They are the on-call engineer who has
never run the restore, the credential held by someone on holiday, the procedure written
against a system that changed two quarters ago. A rehearsal finds all three cheaply.

**Recommendation:** a game day against the top findings in this report — drain a node, fail
an AZ, restore the database into a clone, and time it. It validates `DR-01` through `DR-05`
in one exercise and produces the evidence an auditor asks for.
