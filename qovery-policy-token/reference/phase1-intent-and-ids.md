# Phase 1 — Capture Intent and Resolve Resource IDs

The policy is only as good as the intent behind it. This phase turns a vague ask into an explicit **allow-list + deny-list**, and resolves every UUID the policy will hard-reference. That allow/deny list becomes the test matrix used in Phase 3 and Phase 5 — write it down precisely.

## 1.1 Confirm prerequisites (Phase 0 carryover)

- **Owner/admin token.** Creating a policy token requires org Owner or Admin. If `POST .../policyApiToken` later returns `403`, the caller isn't an admin — surface this now, not after authoring a policy.
- **organizationId.** Resolve it (MCP `list_organizations`, or `GET /organization` → `.results[0].id`). Confirm with the user if they belong to more than one org.
- **OPA CLI** (`opa version`) for local testing — best-effort; see `phase3-local-testing.md` if missing.

## 1.2 Elicit the intent

Ask the user, concretely:

1. **Who/what will use the token?** (an AI agent, a CI job, a partner script) — this sets how tight it must be.
2. **What must it be able to do?** Verbs + targets: "read", "deploy", "restart", "set env vars", "scale". For each, *which* resource.
3. **What must it NEVER do?** Especially "never delete", "never touch production", "never read secrets".
4. **Scope boundaries.** One environment? One project? One service? A whole org (rarely appropriate)?
5. **Expiry?** Optional `expires_at` (RFC 3339). Recommend one for agent tokens.

Restate the answer as two explicit lists before writing any Rego:

```
ALLOW:
  - GET/HEAD anything in environment <env-uuid> (read-only staging)
  - POST deploy service <svc-uuid>
DENY (must be blocked):
  - any DELETE anywhere
  - any write to environment <prod-env-uuid>
  - reading/writing any other environment
```

If the user's ask is broad ("a token for our agent to manage staging"), narrow it with follow-ups — a policy that allows more than needed defeats the purpose. When in doubt, start smaller; adding a rule later means delete + recreate, but that is safer than over-granting.

## 1.3 Resolve the real UUIDs (never guess)

Every `environment_id`, `service_id`, `project_id`, or `cluster_id` a rule references must be a real UUID from this org. A wrong or invented UUID makes the rule silently never fire (fail-closed) — the token then does *less* than intended, or nothing.

**Priority order: MCP → CLI → API.**

**MCP Server** (preferred — no token in the shell). Check availability with `list_organizations`; then chain top-down:

| Tool | Params | Resolves |
|---|---|---|
| `list_organizations` | — | organization_id |
| `list_projects` | `organization_id` | project_id |
| `list_environments` | `project_id` | environment_id |
| `list_services` | `environment_id` | service_id (+ service_type) for every app/container/job/db/helm |

**CLI fallback:**

```bash
qovery project list                                  # project ids
qovery environment list --project "<project-id>"     # environment ids
qovery service list --environment "<env-id>"         # service ids + types
```

**API fallback** (add the standard `Authorization: Token` + `User-Agent` headers — see `auth.md`):

```bash
curl -s "https://api.qovery.com/organization/{organizationId}/project" | jq '.results[] | {id, name}'
curl -s "https://api.qovery.com/project/{projectId}/environment"        | jq '.results[] | {id, name}'
# Services are listed per type — there is no /environment/{id}/service endpoint (it 404s):
for t in application container database job helm; do
  curl -s "https://api.qovery.com/environment/{environmentId}/$t" | jq --arg t "$t" '.results[]? | {id, name, service_type: $t}'
done
```

If the user gave a **Console URL**, extract IDs from it first (see `console-url-detection.md`) and confirm the names match what they intend.

## 1.4 Confirm before authoring

Show the user the resolved mapping — name → UUID — and the allow/deny lists, and get explicit agreement. Because the policy will be immutable once the token is created, this confirmation is the cheapest place to catch a wrong environment or an over-broad rule.

Output of this phase, carried into Phase 2 and Phase 3:
- `organizationId`
- the confirmed allow-list and deny-list
- a name → UUID table for every resource a rule will reference
- optional `expires_at`
