# Phase 1 — Capture Intent and Resolve Resource IDs

The policy is only as good as the intent behind it. This phase turns a vague ask into an explicit **allow-list + deny-list**, and resolves every UUID the policy will hard-reference. That allow/deny list becomes the test matrix used in Phase 3 and Phase 5 — write it down precisely.

## 1.1 Confirm prerequisites (Phase 0 carryover)

- **Owner/admin token.** Creating a policy token requires org Owner or Admin. If `POST .../policyApiToken` later returns `403`, the caller isn't an admin — surface this now, not after authoring a policy.
- **organizationId.** Resolve it (MCP `list_organizations`, or `GET /organization` → `.results[0].id`). Confirm with the user if they belong to more than one org.
- **OPA CLI** (`opa version`) for local testing — best-effort; see `phase3-local-testing.md` if missing.

## 1.2 Guided interview — build the intent with the user

**Do not guess the policy.** Walk the user through the interview below, asking one topic at a time and offering concrete menus (use your interactive question UI if you have one). Each answer maps directly to a Rego building block in [phase2-authoring-rego.md](phase2-authoring-rego.md) §2.3b. Skip a step only when the user has already answered it.

**Step A — Purpose & principal.** "Who or what will use this token?" — an AI agent, a CI/CD pipeline, a teammate, an external partner, a one-off script. This sets how tight to be and whether to recommend an expiry (Step G). Agent/partner tokens should be the tightest.

**Step B — Blast radius (scope).** "What is the widest boundary this token may ever act within?" Offer:
- **one service** → scope rules on `input.qovery_metadata.service_id`
- **one environment** → scope on `environment_id`
- **one project** (any environment/service under it) → scope on `project_id`
- **whole organization** → no resource scope (rare; flag it as broad and confirm twice)

Resolve the chosen boundary's real UUID(s) in §1.3. Everything the token can do will be *and*-ed with this scope.

**Step C — Capabilities (the allow-list).** "Which actions should it be able to perform?" Present this menu and let the user pick as many as apply — each maps to a building block in §2.3b:
- Read / observe (GET) — dashboards, logs, config, statuses
- Deploy / redeploy environments
- Clone environments
- Stop / restart environments
- Cancel a running deployment
- Deploy a specific service (application / container / job / database / helm)
- Manage environment variables (optionally constrained — Step E)
- Scale or update resources (CPU/RAM/instances)
- Create new services
- Delete resources

For each picked capability, confirm the granularity: does it apply to the *whole scope* from Step B, or only to one named resource inside it?

**Step D — Hard denials (safety double-check).** "Is there anything it must NEVER do, even by accident?" e.g. never delete, never touch production, never read secrets, never modify another project. With `default allow := false` these are already denied unless a capability in Step C grants them — but naming them explicitly turns each into a **deny test case** (Phase 3) that proves the boundary holds. Always capture at least one.

**Step E — Value/body constraints (optional).** If a capability touches request bodies (e.g. creating env vars), ask for limits: "only keys starting with `FEATURE_`", "only these allowed values", etc. Maps to the body-constraint block in §2.3b.

**Step F — Usability reads.** Many actions need a preceding read (a CLI/Console lists environments before cloning; a deploy tool reads status). Ask: "Does the tool need to list or read resources in this scope to function?" If yes and Step C didn't already include reads, add a **scoped GET** block so the token isn't so strict it can't be used. If the user truly wants *only* the write verbs, note that reads will return `401`.

**Step G — Expiry.** "Should the token expire?" Optional `expires_at` (RFC 3339). Recommend one for agent, CI, and partner tokens.

Then **restate the answers as two explicit lists** and get agreement before writing Rego:

```
SCOPE: project <proj-uuid> (Lifecycle Demo)
ALLOW:
  - POST clone any environment in the project
  - POST deploy any environment in the project
DENY (must be blocked — becomes test cases):
  - any DELETE in the project
  - clone/deploy in any OTHER project
  - any GET/read (token is write-only by request)
EXPIRES: none
```

If the ask is broad ("a token to manage staging"), narrow it with follow-ups — a policy that allows more than needed defeats the purpose. When in doubt start smaller: adding a capability later means delete + recreate, which is safer than over-granting.

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
