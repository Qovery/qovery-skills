## Phase 5: Security & Data Protection (SC checks)

Scope note: this is a **configuration** assessment of the Qovery layer — exposure,
access control, and data protection as Qovery can observe them. It is not a
penetration test, not an application security review, and not a cloud-account audit.
Say so in the report's Limitations section so the customer does not mistake a good
score here for a clean bill of health.

Data sources: `env/<envId>/services.json`, `service/<id>/advanced-settings.json`, `cluster/<id>/advanced-settings.json`,
`members.json`, `custom-roles.json`, `api-tokens.json`, `policy-tokens.json`,
`sso.json`, `cloud-credentials.json`, `pending-invitations.json`, `clusters.json`,
`service/<id>/custom-domains.json`, `env/<envId>/variables.json`,
`env/<envId>/secret-keys.json`.

> **Never print a secret value.** Secret *keys* and scopes are fine and necessary.
> Values, tokens, passwords, and connection strings never enter the report, the logs,
> or the conversation.

---

## Data exposure

### SC-01 — No database is publicly accessible

**Severity:** Critical

```bash
# Every database in the organization, in one sweep:
for f in raw/env/*/services.json; do
  jq -r --arg env "$(jq -r '.name' "$(dirname "$f")/environment.json")" \
    '.results[]? | select(.service_type == "DATABASE")
     | [$env, .name, .type, .mode, .accessibility] | @tsv' "$f"
done | column -t
```

**Fails when:** any database has `accessibility: PUBLIC`. Critical in every
environment — including development, where the credentials are usually weaker and the
data is often a copy of production.

**Why it matters:** `PUBLIC` puts the database endpoint on the internet, reachable by
anyone who can resolve the hostname. Database ports are continuously scanned; the only
thing between the data and the internet is the password. This is the single
highest-value finding this skill produces, and it is worth leading the executive
summary with when it appears.

**Recommendation:** `accessibility: PRIVATE`. For developer access, `qovery
port-forward` tunnels to a private database without exposing it. If a specific
integration genuinely needs external reach, terminate it behind an allow-listed proxy
rather than opening the database.

---

### SC-02 — Cluster-level database network policy is enforced

**Severity:** High

```bash
jq '{pg_deny: ."database.postgresql.deny_any_access", pg_cidrs: ."database.postgresql.allowed_cidrs",
     mysql_deny: ."database.mysql.deny_any_access", mysql_cidrs: ."database.mysql.allowed_cidrs",
     mongo_deny: ."database.mongodb.deny_any_access", mongo_cidrs: ."database.mongodb.allowed_cidrs",
     redis_deny: ."database.redis.deny_any_access", redis_cidrs: ."database.redis.allowed_cidrs"}' \
  raw/cluster/<clusterId>/advanced-settings.json
```

**Why it matters:** defence in depth behind `SC-01`. Even with every database private,
an explicit deny plus a narrow CIDR allow-list means a future misconfiguration does not
silently become an exposure.

---

### SC-03 — The Kubernetes API server is not open to the internet

**Severity:** Critical

```bash
jq -e '._unreadable // false' raw/cluster/<clusterId>/advanced-settings.json >/dev/null \
  && echo "UNKNOWN — advanced settings unreadable" \
  || jq '{static_ip_mode: ."qovery.static_ip_mode",
          custom_cidrs:   ."k8s.api.allowed_public_access_cidrs"}' \
       raw/cluster/<clusterId>/advanced-settings.json
```

**Check `._unreadable` first.** If the cluster advanced-settings request failed, both fields
are absent because nothing was read, not because nothing is set. Treating that as a Critical
exposure is a false finding.

**An empty CIDR list is the platform default and means nothing on its own.** This is the
trap in this check, and getting it wrong produces a false Critical on nearly every
organization. `GET /defaultClusterAdvancedSettings` returns
`k8s.api.allowed_public_access_cidrs: []`, and the API describes the field as "set **custom**
sources to public access endpoint" — it is the custom allow-list that accompanies
`qovery.static_ip_mode`, not a record of how the endpoint is exposed. An empty list says the
customer has not added custom sources. It does not say the API server is open.

| Evidence | Result |
|---|---|
| list contains `0.0.0.0/0` | **FAIL** — explicitly open to the internet |
| list is non-empty and specific | **PASS** — access is restricted to named ranges |
| list is empty or absent | **UNKNOWN** — the platform default. Report it as unknown and give the customer the action below; never score it as a pass or a fail |

**Resolving the `UNKNOWN`** takes one read the API does not expose: the cluster endpoint's
public-access configuration in the cloud console (EKS "API server endpoint access", or the
equivalent). If the customer confirms it, record the answer and say where it came from. This
is the same posture the skill takes everywhere else — an unreadable answer is disclosed, not
guessed.

**Why it matters:** an internet-reachable API server turns any leaked kubeconfig,
service-account token, or CI credential into full cluster access from anywhere.
Restricting it to the office, VPN, and CI egress ranges shrinks that to a targeted
attack.

---

### SC-04 — Only services that should be public are public

**Severity:** High

```bash
jq -r '.results[] | .name as $n | (.ports[]? | select(.publicly_accessible == true)
  | [$n, .internal_port, .external_port, .protocol, .public_path] | @tsv)' raw/env/<envId>/services.json
```

Then list the public services back to the team and ask which are **meant** to be
public. Internal APIs, admin dashboards, metrics endpoints, queue consumers, and
background workers with a public port are the finding.

**Check the load balancer as well as the service.** A service can be private while the
load balancer in front of it is not:

```bash
jq -r '.results[] | [.name,
  "scheme=" + (.advanced_settings["aws.eks.alb_controller.load_balancer_scheme"] // "-"),
  "source_ranges=" + (if ((.advanced_settings["aws.eks.alb_controller.load_balancer_source_ranges"] // [])|length) == 0
                      then "EMPTY (any source)" else
                      ((.advanced_settings["aws.eks.alb_controller.load_balancer_source_ranges"])|join(",")) end)
  ] | @tsv' raw/clusters.json | column -t -s$'\t'
```

An `internet-facing` scheme with an empty source range means anything routed through that
load balancer is reachable from any address. That is the right configuration for a public
product and the wrong one for an internal tool, so read it against which services sit behind
it rather than reporting the setting on its own.

**Why it matters:** every public port is an entry point. Internal services typically
have weaker authentication precisely because they were never meant to be reachable.

---

### SC-05 — HTTPS is enforced on public services

**Severity:** High

```bash
jq '{force_ssl: ."network.ingress.force_ssl_redirect"}' raw/service/<id>/advanced-settings.json
```

**Fails when:** `false` on a publicly accessible service.

---

### SC-06 — Admin and internal endpoints are network-restricted

**Severity:** Medium

```bash
jq '{allow: ."network.ingress.whitelist_source_range", deny: ."network.ingress.denylist_source_range",
     basic_auth: ."network.ingress.basic_auth_env_var"}' raw/service/<id>/advanced-settings.json
```

**Observation:** `whitelist_source_range` defaulting to `0.0.0.0/0` is correct for a
public product and wrong for an internal admin panel. Report it per service, against
what the service actually is.

---

### SC-07 — Non-production public environments are gated

**Severity:** Medium

**Fails when:** a staging or preview environment exposes public URLs with no basic auth
(`network.ingress.basic_auth_env_var`) and no IP allow-list.

**Why it matters:** open staging environments get crawled and indexed, and they
frequently run with production-shaped data, verbose error pages, and debug endpoints
enabled.

---

## Secrets & configuration

### SC-08 — Secrets are stored as secrets, not as variables

**Severity:** Critical

```bash
# Variable KEYS only — never values.
jq -r '.results[] | [.key, .scope, .variable_type] | @tsv' raw/env/<envId>/variables.json \
  | grep -iE 'password|secret|token|api_?key|private_?key|credential|passwd|dsn|connection_?string|access_?key'
```

**Join against the secret list, or the finding has no denominator.** The command above only
reads `variables.json`. A key matching the pattern is a finding *because it is not in the
secret store* — so compare the two:

```bash
for d in raw/env/*/; do
  E=$(jq -r .name "$d/environment.json")
  jq -r '.results[]?.key' "$d/secret-keys.json" 2>/dev/null | sort > /tmp/sec.$$
  jq -r '.results[]? | select(.variable_type=="VALUE") | select(.value != null)
     | select((.value|length) >= 16)
     | select((.value|test("^https?://"))|not)
     | select(.key|test("password|secret|token|api_?key|private_?key|credential|access_?key";"i"))
     | .key' "$d/variables.json" | sort | while read -r k; do
       grep -qx "$k" /tmp/sec.$$ && echo "$E	$k	also-a-secret" || echo "$E	$k	PLAIN-ONLY"
     done; rm -f /tmp/sec.$$
done | column -t
```

Only `PLAIN-ONLY` rows are findings. **Report both numbers** — "163 stored correctly, 21
are not" is a materially different statement from "21 credentials exposed", and the first
is the one that is true. The length filter drops placeholders; a 3-character
`*_SECRET` is not a live credential.

**There is no `is_secret` field on a variable.** `/variables` returns non-secret variables
only, and `/environment/{id}/secret` returns secret **keys** with no values. A credential
appearing in `variables.json` *with a readable value* is itself the evidence — do not invent
a flag to test.



**Fails when:** a key matching that pattern appears in the environment-variable list
rather than the secret list.

**Triage the matches before reporting — the pattern over-matches by design.** Domain
vocabulary collides with credential vocabulary, and reporting the collisions as security
findings destroys trust in the whole document. Real examples that are *not* credentials:

| Key | Why it is not a secret |
|---|---|
| `LINK_TOKEN_ADDRESS`, `CHAINLINK_TOKEN_POOL_ADDRESSES` | "token" as in ERC-20 asset; these are public on-chain contract addresses |
| `*_ACCESS_KEY_ID` | the identifier half of a cloud key pair — public by design; the matching `*_SECRET_ACCESS_KEY` is the one that matters |
| `PUBLIC_KEY`, `*_KEY_NAME`, `*_KEY_PREFIX` | identifiers and naming, not material |

Report only the keys whose **value** would grant access if disclosed, and say how many
matches you triaged away. Where the name alone cannot settle it, ask the team rather
than assuming either way.

**Why it matters:** Qovery variables are readable by anyone with read access to the
environment, appear in the Console, and are not masked. Secrets are write-only and
masked. The distinction only works if the team uses it.

**Recommendation:** move every matching key to a secret. For organizations with an
existing vault, Qovery can read from a secret manager instead of storing the value at
all.

---

### SC-09 — Secret sprawl is bounded

**Severity:** Medium

```bash
jq -r '.results[] | [.key, .scope] | @tsv' raw/env/<envId>/secret-keys.json | sort | uniq -c | sort -rn
```

**Fails when:** the same secret is duplicated at service scope across many services
instead of being defined once at environment or project scope.

**Why it matters:** rotation. A credential defined in eleven places is rotated in nine
of them, and the other two break at 3am.

---

## Workload hardening

### SC-10 — Containers run with a read-only root filesystem where possible

**Severity:** Medium

```bash
jq '{readonly_root: ."security.read_only_root_filesystem"}' raw/service/<id>/advanced-settings.json
```

**Why it matters:** a read-only root filesystem stops an attacker who achieves code
execution from writing a payload to disk. Services that need scratch space should use a
mounted volume or ephemeral storage explicitly.

---

### SC-11 — Service account tokens are not mounted unnecessarily

**Severity:** Medium

```bash
jq '{automount: ."security.automount_service_account_token",
     sa_name: ."security.service_account_name"}' raw/service/<id>/advanced-settings.json
```

**Fails when:** `automount_service_account_token` is `true` on a service that never
talks to the Kubernetes API.

**Why it matters:** a mounted token inside a compromised container is a credential for
the cluster API. Most application containers have no reason to carry one.

---

### SC-12 — Cloud permissions are scoped per service, not per node

**Severity:** High

```bash
jq -r '.results[] | .name as $n | [$n, (."security.service_account_name" // "none")] | @tsv' \
  raw/service/<id>/advanced-settings.json
```

**Why it matters:** where services access cloud resources (S3, SQS, Secrets Manager) via
node-level instance credentials, every pod on that node inherits the union of all
permissions. A dedicated service account per service (IRSA / Workload Identity) scopes
each service to what it actually needs.

---


**`aws.eks.enable_pod_identity_addon` is the platform-side half of this.** When false,
workloads reach cloud APIs through the node's instance role, so every pod on a node shares
whatever that role grants — the opposite of per-service scoping:

```bash
jq -r '.results[] | [.name, "pod_identity=" + (.advanced_settings["aws.eks.enable_pod_identity_addon"]|tostring)] | @tsv' raw/clusters.json
```

**Read that field narrowly.** `false` means the Pod Identity add-on is not installed. It
does **not** mean every pod inherits the node role: IRSA (the older IAM-roles-for-service-accounts
mechanism) grants per-service identities through a service-account annotation, needs no
add-on, and is invisible to this API. Concluding "every pod shares the node role" from a
disabled add-on is a false finding on any estate that standardised on IRSA.

So: `true` moves the check to a partial pass on the platform half, `false` leaves it
`UNKNOWN` until someone confirms how service accounts are bound. The MCP read-only
cluster-state tools return `.status` only, so they cannot answer it either — the question
is whether service accounts carry a role annotation, and that lives in `.spec`. Ask the
team, or read it from their IaC.
### SC-13 — Instance metadata service is hardened (AWS)

**Severity:** High

```bash
jq '{imds: ."aws.eks.ec2.metadata_imds"}' raw/cluster/<clusterId>/advanced-settings.json
```

**Fails when:** `optional` (IMDSv1 allowed). `N/A` on non-AWS clusters.

**Why it matters:** IMDSv1 turns any SSRF bug in any application into cloud credential
theft — a single crafted URL reads the node's IAM credentials. `required` (IMDSv2)
closes that class of attack.

---

### SC-14 — Managed database disks are encrypted

**Severity:** High

```bash
jq -r '.results[] | select(.service_type == "DATABASE")
  | [.name, .mode, .disk_encrypted, .disk_type] | @tsv' raw/env/<envId>/services.json
```

---

## Identity & access

### SC-15 — SSO is configured

**Severity:** High (Critical under a compliance obligation)

```bash
jq '.' raw/sso.json
```

**Why it matters:** without SSO, offboarding is manual. The measurable risk is the
former employee whose account still works because someone forgot a checkbox. SSO makes
the identity provider the single place access is granted and revoked.

---

### SC-16 — Admin access is minimised

**Severity:** High

```bash
# Role distribution, and the share of the organization holding full control.
jq -r '.results[] | .role_name' raw/members.json | sort | uniq -c | sort -rn
jq '{members: (.results | length),
     privileged: ([.results[] | select(.role_name == "Owner" or .role_name == "Admin")] | length)}' \
  raw/members.json

# Are custom roles used at all, and are they actually narrower than Admin?
jq -r '.results[] | [.name, (.project_permissions | length), (.cluster_permissions | length)] | @tsv' \
  raw/custom-roles.json
```

**Fails when:** more than **half** the members hold `Owner` or `Admin`, or more than
**five** accounts do, whichever comes first — and no custom role is defined. An
organization of three where everyone is an Admin is a deliberate choice and passes; an
organization of thirty where twenty are is not.

Dormancy is a different question with a different remedy, so it is scored separately in
`SC-26`. Report the two together: "19 of 30 accounts are Admin, 6 of them inactive for
over 90 days" is one sentence that carries both findings.

**Why it matters:** blanket Admin is the default because it is easy. It also means
every account is a full-organization account, including the one that gets phished.

**Recommendation:** define a custom role for the common case (deploy and read in named
projects) and leave Admin to the people who administer the organization rather than use
it.

---

### SC-17 — API tokens are scoped and accounted for

**Severity:** High

```bash
jq -r '.results[] | [.name, .role_name, .created_at] | @tsv' raw/api-tokens.json
jq -r '.results[] | [.name, .created_at] | @tsv' raw/policy-tokens.json
```

**Fails when:** long-lived tokens hold Admin-equivalent roles, tokens have names that do
not identify an owner or system, or no scoped Policy Tokens are in use where CI and
agents access the API.

**Recommendation:** `qovery-policy-token` creates least-privilege OPA/Rego-scoped tokens
— for example a CI token that can deploy one environment and nothing else. Name tokens
after their consumer so the next audit can tell what each one is for.

---

### SC-18 — Git and registry credentials are managed centrally

**Severity:** Medium

```bash
jq -r '.results[] | [.name, .type, .created_at, .expired_at // "no expiry"] | @tsv' raw/git-tokens.json
jq -r '.results[] | [.name, .kind, .url] | @tsv' raw/container-registries.json
```

**Why it matters:** a personal access token belonging to one engineer is an
availability risk when they leave and a security risk while they stay.

---

### SC-24 — Cloud credentials are role-based, not static keys

**Severity:** Critical (production), High (elsewhere)

```bash
# One row per credential set: its type, and every cluster it carries.
jq -r '.results[]? | .credential as $c
  | [$c.name, $c.object_type, ((.clusters // []) | map(.name) | join(","))] | @tsv' \
  raw/cloud-credentials.json | column -t -s$'\t'

# Which of those clusters are production, to read the table above against.
jq -r '.results[] | select(.production == true) | .name' raw/clusters.json
```

**Fails when:** a credential set of a static type carries a **production** cluster, or a
single credential set carries both a production and a non-production cluster.

| `object_type` | What it is |
|---|---|
| `AWS`, `GCP`, `AZURE`, `SCW` | Static key pair. A permanent secret held by Qovery. |
| `AWS_ROLE`, `GCP_WORKLOAD_IDENTITY_FEDERATION` | Assumed role / federated identity. Short-lived, revocable at the provider. |
| `EKS_ANYWHERE_VSPHERE`, `OTHER` | Self-managed. Assess against the customer's own control. |

**Credential sets carrying zero clusters are their own small finding.** On the
organization this check was built against, 9 of 13 credential sets were attached to
nothing. An unused credential is an unrotated credential nobody is watching — report the
count as Low, and keep it separate from the production finding so it does not dilute it.

**Report the credential `name` and `object_type` only.** The payload also carries
`access_key_id`. It is not a secret, but it identifies the IAM principal precisely, and it
has no place in a document that leaves the room. Never copy it into the report.

**Why it matters:** a static key pair does not expire. Rotating it means editing the
cluster's credentials and re-running the infrastructure, so in practice nobody does, and
the pair stays valid for as long as the organization exists. An assumed role expires by
construction and can be cut off at the provider without touching Qovery. The second part
of the check matters just as much: when one credential set carries prod and staging, a
compromise or a revocation in either direction takes both down.

**Recommendation:** move production clusters to `AWS_ROLE` (or the provider's federated
equivalent) and give each tier its own credential set, scoped to the accounts it actually
manages.

---

### SC-25 — No SSH keys are registered on production clusters

**Severity:** High

```bash
jq -r '.results[] | [.name, (.production|tostring), ((.ssh_keys // []) | length)] | @tsv' \
  raw/clusters.json | column -t
```

**Fails when:** `ssh_keys` is non-empty on a cluster with `production: true`.

**Why it matters:** a registered public key is standing node access. Whoever holds the
matching private key can reach the instance directly, outside Qovery's RBAC and outside
its event stream — so `OP-03`, which counts shell and port-forward events, will report
"no interactive production access" while a second, unmetered door stands open. The key
also outlives the person: it is attached to the cluster, not to an account, so offboarding
and SSO revocation (`SC-15`) do not touch it.

**An empty list is the norm.** Across the clusters this check was built against, every
one returned `ssh_keys: []`. That is what makes a non-empty list worth chasing rather than
a box to tick: someone added it deliberately, for a reason that is usually no longer
current.

**Never print the key material.** These are public keys, but a public key still names a
person and a machine. Report the count, and the key comment only if the customer needs to
identify which one to remove.

**Recommendation:** remove the keys. `qovery shell` and `qovery port-forward` are
RBAC-scoped and recorded. Where genuine break-glass node access is required, route it
through the cloud provider's session manager so the session is authenticated and logged
rather than through a key baked into the cluster.

---

### SC-26 — Dormant accounts and stale invitations are cleared

**Severity:** High

```bash
# Members with no activity in 90 days. ISO-8601 date prefixes compare correctly as strings.
CUT90=$(date -u -v-90d +%Y-%m-%d 2>/dev/null || date -u -d '90 days ago' +%Y-%m-%d)
jq -r --arg cut "$CUT90" '.results[]
  | select(((.last_activity_at // "0000-00-00")[0:10]) < $cut)
  | [.name, .role_name, ((.last_activity_at // "never")[0:10])] | @tsv' \
  raw/members.json | column -t

# Invitations that were never accepted. EXPIRED and PENDING are the only two states.
CUT14=$(date -u -v-14d +%Y-%m-%d 2>/dev/null || date -u -d '14 days ago' +%Y-%m-%d)
jq -r --arg cut "$CUT14" '.results[]?
  | [.email, .role, (.role_name // "-"), .invitation_status, (.created_at[0:10]),
     (if (.created_at[0:10]) < $cut then "STALE" else "recent" end)] | @tsv' \
  raw/pending-invitations.json | column -t
```

**Fails when:** any account holding `Owner` or `Admin` has been inactive for over 90 days,
or any invitation is still unaccepted after 14 days.

**Why it matters:** the dormant Admin is the account nobody would notice being used. It
is the first thing an access review asks for and the last thing anyone remembers to do.
A stale invitation is the same problem one step earlier: an outstanding grant to an
address that may no longer belong to the person it was sent to, and an `EXPIRED` one still
records intent to grant access that was never followed up.

**Handle the invitation payload carefully.** `GET /organization/{orgId}/inviteMember`
returns an `invitation_link`, which is a usable credential: anyone holding it can accept
the invitation. The collector strips that field in the stream, before anything is written.
If you re-fetch the endpoint by hand, strip it the same way and never paste it anywhere.

**Recommendation:** revoke what nobody has used. Where SSO is in place (`SC-15`), the
identity provider should be the thing that grants and removes access, and a Qovery account
that outlives its SSO identity is exactly the gap SSO was bought to close.

---

## Traceability

### SC-19 — Audit and network logs are retained

**Severity:** Medium (High under a compliance obligation)

```bash
jq '{vpc_flow_logs: ."aws.vpc.enable_s3_flow_logs", flow_retention: ."aws.vpc.flow_logs_retention_days",
     eks_logs: ."aws.cloudwatch.eks_logs_retention_days"}' raw/cluster/<clusterId>/advanced-settings.json
```

Qovery also records organization-level activity — `GET /organization/{orgId}/events` —
which answers "who changed this, and when" during an incident review.

---


**Object-storage access logging belongs in this finding too.** For most platforms the object
store holds the largest volume of customer data, and `object_storage.enable_logging: false`
means there is no record of who read it:

```bash
jq -r '.results[] | [.name, "object_storage_logging=" + (.advanced_settings["object_storage.enable_logging"]|tostring)] | @tsv' raw/clusters.json
```

Report it beside the VPC flow-log gap rather than as a separate finding — they answer the
same question, "can we reconstruct who accessed what", at two different layers.

---

### SC-20 — Custom domains present valid certificates

**Severity:** Medium

```bash
jq -r '.results[] | [.domain, .generate_certificate, .status] | @tsv' raw/service/<id>/custom-domains.json
```

**Fails when:** a domain's certificate status is not valid, or a production domain
relies on a certificate nobody is renewing.

---

### SC-27 — No dangling custom domain

**Severity:** High

```bash
# Every custom domain in the organization, with the service it is attached to.
for f in raw/service/*/custom-domains.json; do
  sid=$(basename "$(dirname "$f")")
  jq -r --arg sid "$sid" '.results[]? |
    [$sid, .domain, .status, (.generate_certificate|tostring), (.use_cdn|tostring),
     (.validation_domain // "-")] | @tsv' "$f" 2>/dev/null
done | column -t

# Does the service behind each domain still expose a public port?
jq -r '.results[]? | select(.service_type == "APPLICATION" or .service_type == "CONTAINER"
                            or .service_type == "HELM")
  | [.id, .name, ([.ports[]? | select(.publicly_accessible == true)] | length)] | @tsv' \
  raw/env/<envId>/services.json | column -t
```

**Fails when:** a domain is still configured on a service that no longer exposes a public
port, or its status is stuck in `VALIDATION_PENDING` — both mean a DNS record still points
somewhere that no longer answers for it.

**Why it matters:** this is subdomain takeover. The customer's DNS keeps a `CNAME` to a
Qovery endpoint that has stopped serving the name. Anyone who can make that endpoint answer
for the hostname inherits a domain the customer's users, and the customer's cookies, still
trust. It is a different failure from `SC-20`: that check asks whether the certificate is
valid, this one asks whether the name should still be pointed here at all.

**Live status, when the snapshot may be stale:**
`GET /{applicationId|containerId|helmId}/customDomain/{customDomainId}/status` re-reads the
same object from the API. Use it to confirm before reporting, since a domain mid-deployment
is legitimately pending for a few minutes.

**Recommendation:** for each finding, either remove the custom domain in Qovery or remove
the DNS record at the registrar. Leaving one of the two in place is what creates the
dangling half. Where `use_cdn: true`, check the CDN's origin configuration too — the
record that matters is the one in front.

---

### SC-22 — Control-plane audit logging is enabled and retained

**Severity:** High (Critical under a compliance obligation)

```bash
jq '{cp_audit_days: ."aws.cloudwatch.eks_logs_retention_days",
     flow_logs: ."aws.vpc.enable_s3_flow_logs",
     flow_days: ."aws.vpc.flow_logs_retention_days"}' \
  raw/cluster/<clusterId>/advanced-settings.json
```

**Fails when:** control-plane audit log retention is unset or zero.

**Retention is not enablement — do not read this field as a pass.** `eks_logs_retention_days`
configures how long CloudWatch keeps whatever it receives; it says nothing about whether the
EKS `audit` log type is actually switched on. A cluster with 90-day retention and audit
logging disabled produces this field and no audit log. Qovery does not expose the EKS log-type
selection, so:

- retention unset or zero → **FAIL**
- retention set, audit log type **confirmed enabled** in the AWS console → **PASS**
- retention set, enablement unconfirmed → **UNKNOWN**, with "confirm the EKS `audit` log type
  is enabled" as the action

Report the retention figure as supporting evidence, never as the verdict on its own.

**Why it matters — and why it is separate from `SC-19`.** Three different logs answer three
different questions, and teams routinely have one and assume they have all three:

| Log | Answers | Check |
|---|---|---|
| Control-plane audit | *Who called the Kubernetes API, and what did they change?* | `SC-22` |
| VPC flow | *What talked to what over the network?* | `SC-19` |
| Application (Loki) | *What did the service itself report?* | `CL-10` |

The control-plane audit log is the one an incident responder needs first and the one a
benchmark explicitly requires — it is the record of API-level actions against the cluster.
Report all three retention figures together so the customer can see which question they
cannot currently answer.

**Standards:** this is a named control in the CIS Kubernetes Benchmark's managed-service
logging section and in the NSA/CISA guide's audit-logging area. See
`standards-mapping.md` — and read its coverage caveat before citing either.

---

### SC-21 — Ownership is traceable on cloud resources

**Severity:** Info

```bash
jq -r '.results[] | .name' raw/annotations-groups.json raw/labels-groups.json
jq '."cloud_provider.container_registry.tags"' raw/cluster/<clusterId>/advanced-settings.json
```

**Observation:** annotation and label groups propagate ownership, cost-centre, and
compliance metadata onto Kubernetes and cloud objects. Without them, cloud cost
allocation and incident routing are manual.

---

### SC-23 — Kubernetes Secrets are encrypted with a customer-managed key

**Severity:** High (Critical where health, financial or regulated data is processed)

```bash
jq -r '.results[] | [.name, .cloud_provider,
  "kms_key=" + (if ((.advanced_settings["aws.eks.encrypt_secrets_kms_key_arn"] // "")|length) == 0
                then "UNSET" else "set" end),
  "pod_identity=" + (.advanced_settings["aws.eks.enable_pod_identity_addon"]|tostring),
  "object_storage_logging=" + (.advanced_settings["object_storage.enable_logging"]|tostring),
  "production=" + (.production|tostring)] | @tsv' raw/clusters.json | column -t -s$'\t'
```

**Fails when:** `aws.eks.encrypt_secrets_kms_key_arn` is unset on a production **AWS**
cluster.

**`N/A` everywhere else.** The setting is an EKS one. On a GCP, Azure, Scaleway or
on-premise cluster the field is absent because it does not exist, not because the control is
missing, and scoring that as a failure is the same false-finding pattern as `SC-03`. Filter
on `cloud_provider == "AWS"` before applying the rule, and state the equivalent control for
the other providers (GKE application-layer secrets encryption, AKS KMS etcd encryption) as
an `UNKNOWN` with an owner rather than inventing a verdict.

**What this actually changes.** Kubernetes Secrets live in etcd. Without envelope encryption
they are stored base64-encoded — which is an encoding, not encryption — protected only by
whatever the managed control plane does by default. Setting a customer-managed KMS key adds a
second layer the cloud provider cannot read on its own, and gives the customer a revocation
point and a key-usage audit trail they control. It is a named control in the CIS Kubernetes
Benchmark and one of the first things a health-data or financial auditor asks about, because
it is the difference between "the provider encrypts our data" and "we hold the key".

**Say precisely what is and is not covered.** This protects Secrets at rest in etcd. It does
nothing for a credential pasted into a plain variable (`VS-01`), nothing for one shared
between environments (`VS-09`), and nothing for a database's own disk encryption (`SC-14`).
An organization can hold this control and still have every problem those checks find —
report it alongside them, never as a substitute.

**Two adjacent settings surface in the same query, and belong to other checks:**

- `aws.eks.enable_pod_identity_addon` — when false, workloads reach cloud APIs through the
  node's role rather than a per-service identity. That is the evidence `SC-12` needs; without
  it `SC-12` stays UNKNOWN by default, which is how it has usually been reported.
- `object_storage.enable_logging` — when false there is no access record for the object
  store, which for most platforms holds the largest volume of customer data. Feed it into
  `SC-19` beside the VPC flow-log finding rather than raising it separately.
