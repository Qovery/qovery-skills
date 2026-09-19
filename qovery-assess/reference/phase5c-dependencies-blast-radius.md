## Phase 5c: External dependencies & blast radius (VS-09)

Every other phase asks "is this setting right?". This one asks a different question:
**if one environment were compromised, what would the attacker reach?** The answer is
rarely contained by the environment boundary, and the two things that break containment
are a shared credential and a shared network.

Data sources: `env/<envId>/variables.json`, `env/<envId>/secret-keys.json`,
`env/<envId>/services.json`, `clusters.json`.

Run `templates/scripts/dependency-surface.sh <snapshotDir>` and
`templates/scripts/cross-env-secrets.sh <snapshotDir>`.

---

### 5c.1 Enumerate the dependency surface

`dependency-surface.sh` lists vendor prefixes per environment from variable and secret
**key names**, the vendors holding a secret in each environment, and the third-party
workloads running in-cluster.

**A prefix is a hint, not a vendor.** Confirm each against the service inventory before it
goes in a customer document, and group them by what they do rather than listing them
alphabetically — the grouping is the insight:

| Layer | Why it matters |
|---|---|
| Telephony / media | Carries the payload. Inherently sees customer content |
| AI / speech / LLM | Transcribes and generates. Inherently sees customer content |
| Domain systems (EHR, CRM, billing, booking) | Holds the records the product acts on |
| Storage & data | Where output lands |
| Identity | Who can get in |
| Observability | Receives logs and traces, which routinely contain more than intended |
| Workflow & comms | Usually peripheral, occasionally not |

**This feeds `CP-02`.** Where the organization publishes a claim like "we do not share
customer data with third parties", set that claim against the layers above. The telephony
and AI layers necessarily process content — that is their function — so the claim is
almost always meant as "not beyond our processors". Say that plainly rather than treating
it as a contradiction. The finding worth reporting is the **absence of a published
sub-processor list**, which is what stops a customer's DPO verifying the intended reading
for themselves. Offer the enumerated table as a first draft of that list.

---

### VS-09 — Credentials are isolated per environment

**Severity:** High (Critical where the shared credential reaches regulated or customer data)

```bash
bash templates/scripts/cross-env-secrets.sh <snapshotDir>
```

The script groups plain variables by a truncated SHA-256 of their value. Two variables in
different environments with the same hash hold the same value. **No value is printed**, and
the hash is truncated so it cannot confirm a guessed value offline.

**Fails when:** the same credential value appears in a production and a non-production
environment. The script flags those `*** PRODUCTION + NON-PRODUCTION ***`.

**Triage by key shape, and expect most hits to be legitimate.** Configuration is *supposed*
to be shared across environments. The script separates the two classes, but check its work:

| Shared value | Verdict |
|---|---|
| `*_SID`, `*_ID`, `*_URL`, `*_HOST`, `*_ENDPOINT`, `*_REGION`, `*_VERSION`, `*_NAME`, `*_RELEASE`, phone numbers, voice and model IDs | **Correct.** Identifiers and endpoints; sharing them is the point |
| Public-by-design keys — client-side analytics tokens, `*_ACCESS_KEY_ID` without its secret half | **Not a finding.** Say why, so the reader trusts the rest |
| API keys, auth tokens, signing keys, session secrets, **password-hashing peppers** | **Finding.** These are the ones that break containment |

**Weight a pepper or signing key above an API key.** An API key can be rotated in minutes
and its blast radius ends at one vendor. A password-hashing pepper or a JWT signing secret
is long-lived, is often embedded in stored data, and rotating it is a migration. A pepper
shared between production and a weaker environment is the most serious result this check
produces.

**Why it matters:** this is what turns a non-production finding into a production one. A
staging environment with a public database is a contained problem right up until staging
holds the same credential as production — at which point reading staging's configuration
*is* holding production's credential, and no boundary has to be crossed.

**Recommendation:** separate credentials per environment, then **rotate**, because the
shared value has been readable in the weaker environment for as long as it has existed.
Most vendors support multiple concurrent keys, so this is usually doable without downtime.

**State the limit in the report.** Qovery never returns a secret's value, so only plain
variables can be compared. Properly-stored secrets are invisible to this method. Write that
the comparison covers plain variables only — never let it read as "the secrets were checked
and found clean".

---

### 5c.2 The blast-radius table

Synthesize one row per environment. This is a **report section**, not a check — it draws on
`VS-09`, `TP-05`, `CL-05`, `SC-01`, `SC-07` and the dependency surface:

| Column | What goes in it |
|---|---|
| Compromise of… | The environment |
| Directly exposes | Its own datastores, credentials, and the vendors it can reach |
| Reaches production because… | The specific mechanism — a shared credential (`VS-09`), a shared cluster (`TP-05`, which fails on `cluster_id` sharing between production and a non-production environment — the absence of a NetworkPolicy is a separate question this skill cannot read from the API), a job writing across environments (`BP-07`). **Name the mechanism, or leave the cell empty** |

**The asymmetry is the finding.** Compare the number of vendors holding a secret in each
environment. A non-production environment carrying the same vendor credential surface as
production is not a reduced-privilege environment — it is a full-privilege environment with
weaker controls, and that is worth saying in those words. Narrowing what non-production can
reach is an independent remediation path, alongside network isolation and credential
separation; give the reader all three and let them pick.

**Do not speculate about exploitability.** State what is reachable and by what mechanism.
Do not write attack narratives, estimate likelihood, or describe how a compromise would be
performed — that is not this document's job, and it makes a configuration assessment read
like a penetration test it is not.
