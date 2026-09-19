## Phase 5: Security & Data Protection (SC checks)

Scope note: this is a **configuration** assessment of the Qovery layer — exposure,
access control, and data protection as Qovery can observe them. It is not a
penetration test, not an application security review, and not a cloud-account audit.
Say so in the report's Limitations section so the customer does not mistake a good
score here for a clean bill of health.

Data sources: `env/<envId>/services.json`, `service/<id>/service.json`,
`service/<id>/advanced-settings.json`, `cluster/<id>/advanced-settings.json`,
`members.json`, `custom-roles.json`, `api-tokens.json`, `policy-tokens.json`,
`sso.json`, `env/<envId>/variables.json`, `env/<envId>/secret-keys.json`.

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
jq '{api_cidrs: ."k8s.api.allowed_public_access_cidrs"}' raw/cluster/<clusterId>/advanced-settings.json
```

**Fails when:** the list is empty, absent, or contains `0.0.0.0/0`.

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
jq -r '.results[] | [.name, .role_name, .last_activity_at // "unknown"] | @tsv' raw/members.json \
  | sort -k2
jq -r '.results[] | [.name, (.project_permissions | length), (.cluster_permissions | length)] | @tsv' \
  raw/custom-roles.json
```

**Assess:** how many members hold Owner or Admin; whether custom roles are used at all;
whether any member has been inactive for a long period.

**Why it matters:** blanket Admin is the default because it is easy. It also means
every account is a full-organization account, including the one that gets phished.

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

### SC-20 — Custom domains present valid certificates

**Severity:** Medium

```bash
jq -r '.results[] | [.domain, .generate_certificate, .status] | @tsv' raw/service/<id>/custom-domains.json
```

**Fails when:** a domain's certificate status is not valid, or a production domain
relies on a certificate nobody is renewing.

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
