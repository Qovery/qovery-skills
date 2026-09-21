## Phase 1: Scope, Auth & Read-Only Inventory Snapshot

The assessment is only as good as the snapshot it runs on. Collect everything
first, analyse second — so every finding in Phases 2–6 cites data from the same
point in time.

### 1.0 Restate the read-only contract

Before touching the API, say this out loud to the user (one line, not a lecture):

> "This is a read-only assessment — I'll only issue GET calls and won't change
> anything in your organization."

Then hold to it. See the READ-ONLY table in `SKILL.md`. In particular, never call
`/database/{databaseId}/masterCredentials` or `.../kubeconfig`, and never print a
secret value.

### 1.1 Authenticate

Resolve a credential in this order, and stop at the first that works. The Auth row of
`SKILL.md`'s reference table holds the full rules; the three that govern this phase are
stated here so it stands on its own:

```bash
# 1. An API token already in the environment. Resolve ONE variable and reuse it.
QOVERY_TOKEN="${QOVERY_API_TOKEN:-${QOVERY_CLI_ACCESS_TOKEN:-}}"
test -n "$QOVERY_TOKEN" && echo "Token found"          # header: Authorization: Token $QOVERY_TOKEN

# 2. An authenticated CLI. Let it state its own scheme rather than assuming Bearer.
qovery auth token --json 2>/dev/null | jq -e -r '.token_type' >/dev/null && echo "CLI authenticated"
# header: Authorization: $(qovery auth token --print --authorization-header)
```

- **Never print a token.** Use it inline; never echo it, never store it in a file.
- **Never create one.** `qovery token create` is a write, and a first `qovery auth` login
  creates an account. If neither route above works, stop and ask the user to authenticate
  themselves, then rerun.
- Every request to `api.qovery.com` carries the skill's `User-Agent` header.

**The snapshot is sensitive, and one common phrasing about it is wrong.** Log and event
bodies are redacted in the stream. `variables.json` is not — it holds plain-variable values
verbatim, because `VS-01`, `VS-05` and `VS-09` cannot work without them. Those are values
the API returns to any member with read access, and a credential among them is the finding,
not a collection mistake. So: never commit the snapshot, delete it when the assessment is
delivered, and in the report write "log and event bodies were redacted at collection time"
rather than "no secret value was written to disk".

Quickest check that auth works and the org is reachable:

```bash
QOVERY_SKILLS_VERSION="__QOVERY_SKILLS_VERSION__"
UA="QoverySkill/qovery-assess (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)"

curl -s -H "Authorization: Token $QOVERY_API_TOKEN" -H "User-Agent: $UA" \
  "https://api.qovery.com/organization" | jq '.results[] | {id, name, plan}'
```

If the token has no access to the target organization, stop and say so — do not
silently assess a different org.

### 1.2 Resolve the scope

**From a Console URL** — the fastest path. Extract IDs with
[console-url-detection.md](console-url-detection.md). An organization overview URL
(`/organization/{orgId}/overview`) gives the org ID, which is all this skill needs
to assess everything below it.

**Otherwise** ask which organization, and confirm the name before proceeding:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" -H "User-Agent: $UA" \
  "https://api.qovery.com/organization/{orgId}" | jq '{id, name, plan, billing_deployment_restriction}'
```

### 1.3 Ask the four scoping questions

Keep it to four. This is an audit, not a discovery workshop — most of the answer is
in the API. Ask them together, and proceed with stated assumptions if the user is
not available to answer.

1. **Which environments are business-critical?** Qovery's `mode` field
   (`PRODUCTION` / `STAGING` / `DEVELOPMENT` / `PREVIEW`) is the default signal, but
   customers sometimes run production workloads in a `DEVELOPMENT`-mode environment.
   Confirm the real-world criticality — it drives every severity rating.
2. **What is the availability target?** ("best effort", "business hours",
   "99.9%", "99.99%"). A 99.9% target makes single-replica services a Critical
   finding; "best effort" makes them Medium.
3. **Any compliance or regulatory obligation?** (SOC 2, ISO 27001, HIPAA, PCI DSS,
   GDPR data residency, financial regulation.) This promotes audit-logging,
   retention, encryption, SSO, and network-restriction checks by one severity level.
4. **Who is the audience for the report?** (engineering team / CTO / board /
   customer's own auditor.) Changes the tone of the executive summary, not the findings.

If the user does not answer, assume: mode-based criticality, a 99.9% production
target, no formal compliance obligation, engineering audience. **State the
assumptions in the report's Scope section** so the customer can correct them.

### 1.3b Ask which output format to produce

One more question, and it is not an assumption you may make silently — the three
formats are different artifacts, not three renderings of one file, and picking wrong
means writing the deliverable twice.

> **How would you like the report? HTML, Markdown, or raw?**
>
> - **HTML** — one self-contained file. Qovery-branded, light and dark, filterable
>   control appendix, prints to PDF. The one to send or present.
> - **Markdown** — plain `.md`. Best when it goes into a repo, a wiki, a Notion page,
>   or through review with diffs.
> - **Raw** — the findings CSV and the JSON snapshot, no prose. For piping into
>   another tool, a dashboard, or a spreadsheet.

**Default to HTML if there is no answer**, and say that you are defaulting. It is the
only one of the three that is useful without a second step, and the Markdown is
recoverable from it in seconds if the choice turns out wrong.

Ask now rather than at Phase 8: the answer costs nothing here and changes which
template gets filled once forty findings are already written. More than one is a
legitimate answer — the CSV ships alongside HTML or Markdown anyway.

### 1.4 Collect the snapshot

Run the collector — it issues GET calls only and writes one JSON file per resource:

```bash
bash templates/scripts/collect-snapshot.sh <orgId> ./qovery-assessment
```

It produces (run every `jq` command in the phase files from inside `qovery-assessment/`,
since they use `raw/...` paths):

```
qovery-assessment/
├── raw/
│   ├── organization.json          members.json            custom-roles.json
│   ├── available-roles.json       api-tokens.json         policy-tokens.json
│   ├── sso.json                   webhooks.json           alert-receivers.json
│   ├── alert-rules.json           container-registries.json  helm-repositories.json
│   ├── git-tokens.json            annotations-groups.json    labels-groups.json
│   ├── current-cost.json          projects.json           environments.json
│   ├── services.json              clusters.json           cluster-status.json
│   ├── cloud-credentials.json     pending-invitations.json
│   ├── events.ndjson              one redacted audit event per line — the OP phase reads this
│   ├── default/{application,cluster,container,job,helm,terraform}-advanced-settings.json
│   ├── cluster/<clusterId>/{advanced-settings,routing-table,cloud-provider-info,
│   │                        deployment-history,analyses}.json
│   ├── project/<projectId>/{environments,overview,deployment-rules}.json
│   ├── env/<envId>/{environment,statuses,services,deployment-stages,deployment-rule,
│   │                variables,secret-keys,deployment-history}.json
│   ├── env/<envId>/deployment-logs/<executionId>.json   redacted deployment logs (LG phase)
│   └── service/<serviceId>/{advanced-settings,deployment-restriction,custom-domains,
│                            backups,git-webhook-status,commits}.json
│                           (+ runtime-logs.json when WITH_RUNTIME_LOGS=1, redacted)
└── collect.log
```

One of those files is filtered at collection time: `pending-invitations.json` has its
`invitation_link` removed in the stream, because that link is a usable credential.
`cloud-credentials.json` is **written verbatim**, `access_key_id` included — `SC-24` needs
the credential type that sits beside it, and the key ID is an identifier rather than a
secret. The constraint on it is report-time, not collection-time: it is on disk, it is in
the snapshot you must treat as sensitive, and it must never be copied into the document. `git-webhook-status.json` and `commits.json` appear only for services
that have a git source.

`env/<envId>/services.json` already carries each service's full configuration —
replicas, health checks, ports, resources, storage — so the per-service files hold only
the sub-resources. Endpoints that returned a non-2xx status are written as
`{"_unreadable": true, "_status": <code>}`; treat those checks as `UNKNOWN`.

If the script cannot run (no bash, restricted environment), issue the same GETs by
hand from the allowlist in `SKILL.md`. Two calls carry most of the inventory:
`GET /organization/{orgId}/services` and `GET /organization/{orgId}/environments`.

### 1.5 Build the topology map

From `services.json` + `environments.json` + `clusters.json`, build the pivot table
that every later phase indexes into:

```bash
jq -r '.results[] | [.cluster_id, .project_name, .environment_name, .service_type, .name] | @tsv' \
  raw/services.json | sort | column -t
```

Produce a single in-memory model per service:

| Field | Source |
|---|---|
| `service_id`, `name`, `service_type` | `services.json` |
| `environment_id`, `environment_name`, `mode` | `environments.json` |
| `project_id`, `project_name` | `services.json` |
| `cluster_id`, `cluster_name`, `production` flag | `clusters.json` |
| `criticality` | user answer from 1.3, else `mode` |

**`criticality` is the field that drives severity in every subsequent check.** Set it
once, here.

### 1.6 Record coverage honestly

Track what could not be read — a 403 on `alert-rules`, a cluster in
`INVALID_CREDENTIALS` state, a self-managed cluster with no metrics. Those become
`UNKNOWN` checks, excluded from scoring and disclosed in the report's Limitations
section. A confident score built on missing data is worse than no score.

### 1.7 Present the inventory before analysing

Show the user what was found and let them correct it:

> "Assessed **{org-name}** ({plan} plan):
> - {N} clusters — {names, cloud providers, regions}
> - {N} projects, {N} environments ({N} production, {N} staging, {N} development, {N} preview)
> - {N} services — {N} applications, {N} containers, {N} databases, {N} jobs, {N} helm, {N} terraform
> - {N} members, {N} API tokens, SSO {enabled|not enabled}
>
> Running {N} checks across 6 pillars. Nothing will be modified."
