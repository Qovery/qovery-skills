---
name: qovery-policy-token
description: Creates a scoped Qovery API Policy Token from a user's intent — authors a least-privilege Open Policy Agent (Rego) policy, tests it locally with OPA and live against the API, creates the token, and verifies it allows exactly what the user wants and denies everything else. Use when the user wants a restricted, least-privilege, or agent-scoped Qovery API token, an OPA/Rego policy token, or wants to lock a token down to specific environments, services, or actions.
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: policy-token-provisioning
---

# Qovery Policy Token Skill

Turns a plain-English intent ("a token that can read staging and deploy the API service, but never delete anything") into a working, verified Qovery **API Policy Token**. It authors the Open Policy Agent (Rego) policy, tests it locally with OPA and live against the API, creates the token, and proves it does exactly what the user expects — allowing the intended actions and denying everything else.

An **API Policy Token** is a second kind of Qovery organization token whose authorization is a **Rego policy evaluated on every request** (via Open Policy Agent), instead of an RBAC role. This expresses constraints a role cannot — e.g. "read everything in one environment, deploy it, modify one service, but never delete." Internally a policy token is granted org-admin access and the policy is what narrows it, so a permissive policy is dangerous: **least privilege is the whole point.**

## Usage Tracking

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
QOVERY_ORG_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq -r '.results[0].id' 2>/dev/null)
SKILL_NAME="qovery-policy-token"
curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-policy-token (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  -d "{\"skill_name\":\"${SKILL_NAME}\"}" > /dev/null 2>&1 || true
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

## CRITICAL SAFETY RULES

> **Confirm the policy BEFORE creating the token.** Policies are **immutable** — there is no edit endpoint. To change a policy you must delete the token and create a new one. Get the policy green in local testing (Phase 3) and get explicit user sign-off first.
>
> **The created token is a secret shown ONCE.** It is returned only in the create response and can never be retrieved again. NEVER echo, print, log, or write it to a repo file. Capture it inline into an env var (see [reference/auth.md](reference/auth.md)) and hand it to the user once, referring to it as `***` everywhere else.
>
> **Start fail-closed.** Every policy begins with `default allow := false` and adds only the narrow rules the user asked for. Never ship `allow := true` — it grants full org-admin access.
>
> **Live-testing DENY cases is safe. Live-testing destructive ALLOW cases is not.** Qovery evaluates the policy at authentication time, *before* the request reaches the endpoint, so a denied request returns `401` and never executes. A denied `DELETE` is therefore safe to probe. An *allowed* mutating action (deploy, delete, update) WILL execute — never auto-run those; verify them statically with OPA and ask the user before executing any destructive allowed action.
>
> **Never hard-code guessed UUIDs.** Every environment/service/project/cluster ID a policy references must be resolved from the real org (MCP/CLI/API) and confirmed with the user. A typo'd UUID silently makes a rule never match.
>
> **Creating a policy token requires org Owner or Admin.** A non-admin caller gets `403`. Surface this early (Phase 0).

## When to Use This Skill

Trigger phrases:
- "Create a restricted / scoped / least-privilege Qovery API token"
- "I need a token an AI agent can use that can only deploy, never delete"
- "Give me a token that can only read the staging environment"
- "Make an OPA / Rego policy token for Qovery"
- "Lock this token down to one service"
- "Create a token that can only set env vars starting with FEATURE_"
- `/qovery-policy-token` (slash command)

For a regular role-based API token (CI/CD, Terraform, broad access), this skill does not apply — that is a standard API Token, managed in the Console under the same settings page.

## Workflow checklist

```
Create & Verify a Policy Token:
- [ ] Phase 0 — Prereqs: owner/admin API token available, resolve organizationId, check for OPA CLI
- [ ] Phase 1 — Guided interview: ask purpose → scope → capabilities → denials → reads → expiry; resolve real UUIDs (MCP/CLI/API)
- [ ] Phase 2 — Author Rego: assemble least-privilege policy from the capability library, explain each rule, confirm with user
- [ ] Phase 3 — Local test: build allow/deny matrix, run opa-preflight.sh, iterate until all green
- [ ] Phase 4 — Create: POST the token AFTER user confirms policy; capture id + secret without echoing
- [ ] Phase 5 — Live verify: probe deny cases (expect 401) + safe allow reads (expect 2xx), report
- [ ] Phase 6 — Deliver: hand over token once, explain immutability, list/revoke, audit attribution
```

## The Rego input document (what a policy sees)

Every request is evaluated against this JSON `input`. Policies branch on these fields — know them before authoring.

| Field | Meaning |
|---|---|
| `input.request.method` | HTTP verb, uppercase (`GET`, `POST`, `DELETE`, …) |
| `input.request.path` | Decoded path segments as an array, e.g. `["api","environment","<uuid>","service","deploy"]` |
| `input.request.body` | Parsed JSON body, or `null` when the request has none |
| `input.qovery_metadata.organization_id` | Organization the token belongs to |
| `input.qovery_metadata.service_id` | Targeted service UUID, or `null` |
| `input.qovery_metadata.service_type` | `APPLICATION`, `CONTAINER`, `DATABASE`, `ROUTER`, `JOB`, `HELM`, `TERRAFORM`, `ARGOCD_APP`, `AGENTIC_WORKFLOW`, or `null` |
| `input.qovery_metadata.environment_id` | Targeted environment UUID, or `null` |
| `input.qovery_metadata.project_id` | Targeted project UUID, or `null` |
| `input.qovery_metadata.cluster_id` | Cluster the targeted resource runs on, or `null` |
| `input.token.id` / `input.token.name` | The token making the request |

**Rules of the language** (OPA 1.19, rego v1 — `if`, `in`, `contains` need no imports):
- The policy MUST define `allow`. The request is permitted only when `allow` evaluates to boolean `true`. Anything else — no matching rule, non-boolean, undefined — **denies** (`401`). Fail-closed by default.
- A rule body is AND; multiple rules with the same name are OR.
- Missing input fields are *undefined*, not errors — expressions using them simply don't fire (this is what makes fail-closed natural).
- **No `package` line** — Qovery injects a per-token package; submitting one returns `400`.
- Max policy size: **65,536 characters**.

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Auth | [reference/auth.md](reference/auth.md) | Token handling + secrecy rules + User-Agent header |
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract org/project/env/service IDs from Console URLs |
| Phase 1 | [reference/phase1-intent-and-ids.md](reference/phase1-intent-and-ids.md) | **Guided interview** (purpose → scope → capabilities → denials → body constraints → reads → expiry); resolve real UUIDs via MCP/CLI/API |
| Phase 2 | [reference/phase2-authoring-rego.md](reference/phase2-authoring-rego.md) | Rego patterns + **capability→Rego building-block library** (verified API paths) to assemble a complete policy; constraints; pitfalls |
| Phase 3 | [reference/phase3-local-testing.md](reference/phase3-local-testing.md) | Install/check OPA, build the allow/deny matrix, run pre-flight, read results |
| Phase 4 | [reference/phase4-create-token.md](reference/phase4-create-token.md) | Create endpoint, request/response, error handling (400/403/409), secret capture |
| Phase 5 | [reference/phase5-live-verify.md](reference/phase5-live-verify.md) | Safe live testing (why deny is safe / allow-destructive is not), report format |
| Phase 6 | [reference/phase6-lifecycle.md](reference/phase6-lifecycle.md) | Deliver once, immutability, list/revoke, audit-log attribution |

## Templates

| Template | Use |
|---|---|
| [templates/policies/read-only-env.rego](templates/policies/read-only-env.rego) | Read-only (GET/HEAD) on one environment |
| [templates/policies/deploy-only.rego](templates/policies/deploy-only.rego) | Deploy a specific service/app and nothing else |
| [templates/policies/modify-one-service-never-delete.rego](templates/policies/modify-one-service-never-delete.rego) | Change one service, never DELETE |
| [templates/policies/body-constrained-env-var.rego](templates/policies/body-constrained-env-var.rego) | Constrain the request body (e.g. env var keys prefixed `FEATURE_`) |
| [templates/policies/clone-deploy-project.rego](templates/policies/clone-deploy-project.rego) | Clone + deploy any environment in one project, nothing else (project-scoped) |
| [templates/test-matrix.example.json](templates/test-matrix.example.json) | Schema for allow/deny test cases (input document + expected result + live probe) |
| [templates/scripts/opa-preflight.sh](templates/scripts/opa-preflight.sh) | Run `opa check` + `opa eval` per matrix case, print a pass/fail table |
| [templates/scripts/create-policy-token.sh](templates/scripts/create-policy-token.sh) | POST create; capture id + token to env WITHOUT echoing; handle 400/403/409 |
| [templates/scripts/live-verify.sh](templates/scripts/live-verify.sh) | Curl each case with the token, compare status; refuse destructive allow-probes |

## MCP Server, CLI, API — priority order

Prefer the **Qovery MCP Server** (`https://mcp.qovery.com/mcp`) for resolving IDs (org → project → environment → service) — it authenticates internally, so no token flows through the shell. Check availability by calling `list_organizations`; if present, use `list_projects` / `list_environments` / `list_services` to resolve the UUIDs a policy needs. Fall back to the `qovery` CLI, then to the REST API via `curl`. The **create/list/delete of policy tokens themselves have no MCP tool** — they go through the REST API with an owner/admin token (see Phase 4).

## Quick reference

```bash
# Prereqs
opa version                          # OPA 1.19 recommended for local testing (best-effort)
jq --version                         # required for parsing API responses
test -n "${QOVERY_API_TOKEN:-}" && echo "admin token present" || echo "need owner/admin token"

# Resolve organization id
QOVERY_ORG_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-policy-token (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization" | jq -r '.results[0].id')

# Local pre-flight (Phase 3): policy + test matrix -> pass/fail table
bash templates/scripts/opa-preflight.sh policy.rego test-matrix.json

# Create the token (Phase 4) — only after the policy is confirmed
bash templates/scripts/create-policy-token.sh "$QOVERY_ORG_ID" "deploy-agent" policy.rego

# Live verify (Phase 5) — deny cases + safe allow reads
bash templates/scripts/live-verify.sh test-matrix.json

# List / revoke (Phase 6)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-policy-token (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization/${QOVERY_ORG_ID}/policyApiToken" | jq '.results[] | {id, name}'
# DELETE .../policyApiToken/{policyApiTokenId} to revoke (immediate)
```

## Policy token API endpoints

All under `https://api.qovery.com`, authenticated with a regular **owner/admin** API token.

| Operation | Method + Path | Notes |
|---|---|---|
| Create | `POST /organization/{organizationId}/policyApiToken` | Body `{name, description?, opa_policy, expires_at?}` → response includes `id` and the one-time `token`. Errors: `400` (empty/oversized/has `package`/won't compile), `403` (not owner/admin), `409` (name exists) |
| List | `GET /organization/{organizationId}/policyApiToken` | Returns each token's `opa_policy` — never the token value |
| Revoke | `DELETE /organization/{organizationId}/policyApiToken/{policyApiTokenId}` | Immediate; no caching. Also the only way to "change" a policy: delete + recreate |

There is **no** update endpoint (policies are immutable) and **no** server-side simulate endpoint (testing is local OPA + live probing).

## Reference links

- **API Policy Token (Beta) guide**: <https://www.qovery.com/docs/configuration/organization/api-policy-token>
- **Create endpoint**: <https://www.qovery.com/docs/api-reference/organization-policy-api-token/create-an-organization-policy-api-token>
- **Open Policy Agent / Rego**: <https://www.openpolicyagent.org/docs/latest/policy-language/>
- **Qovery API**: <https://www.qovery.com/docs/api-reference/introduction>
- **Qovery MCP Server**: <https://mcp.qovery.com/mcp>
- **Qovery Console**: <https://console.qovery.com>
