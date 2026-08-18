# Phase 2 — Author the Rego Policy

Translate the Phase 1 allow-list into the smallest Rego policy that permits exactly those requests and denies the rest. Present it to the user with a plain-English explanation of every rule, and get sign-off before Phase 4 (the policy is immutable after creation).

## 2.1 The shape of every policy

```rego
default allow := false        # fail-closed: deny unless a rule below says otherwise

allow if <rule_1>
allow if <rule_2>
```

- Start with `default allow := false`. Never write `allow := true` unconditionally — a policy token is org-admin narrowed only by its policy, so that grants full access.
- Each `allow if { ... }` body is **AND**. Multiple `allow` rules are **OR**.
- **No `package` line** — Qovery adds one per token; including one returns `400`.
- Keep it ≤ 65,536 characters.
- OPA 1.19 / rego v1: `if`, `in`, `contains`, and stdlib (`startswith`, `endswith`, `count`, `regex.match`, `sprintf`) are available without imports.

## 2.2 What to branch on

Match against the input document (full field list in SKILL.md):

- **By method** — `input.request.method in {"GET", "HEAD"}` for read-only; `!= "DELETE"` to forbid deletes.
- **By targeted resource** — `input.qovery_metadata.environment_id == "<env-uuid>"`, `...service_id == "<svc-uuid>"`, `...project_id`, `...cluster_id`. These are resolved by Qovery from the path, so they work regardless of the exact route.
- **By exact path** — `input.request.path == ["api","environment","<env-uuid>","service","deploy"]` for a specific action. The policy sees the raw decoded path segments, not a route template.
- **By body** — `startswith(input.request.body.key, "FEATURE_")` to constrain payloads.
- **By service type** — `input.qovery_metadata.service_type == "DATABASE"`.

Prefer `qovery_metadata` scoping (environment_id/service_id) over hand-matching `request.path` when you want "anything targeting this resource" — it is more robust than enumerating every route. Use exact `request.path` when you want to allow one specific action (like deploy) and nothing else.

## 2.3 Documented patterns (copy from templates/, then adapt)

Pick the closest starter under `templates/policies/` and substitute the confirmed UUIDs. These mirror the official docs.

**Read-only access to one environment** — `templates/policies/read-only-env.rego`:

```rego
default allow := false

allowed_environment_id := "<ENV_UUID>"

allow if {
	input.request.method in {"GET", "HEAD"}
	input.qovery_metadata.environment_id == allowed_environment_id
}
```

**Deploy, and nothing else** — `templates/policies/deploy-only.rego`:

```rego
default allow := false

allowed_environment_id := "<ENV_UUID>"
allowed_application_id := "<APP_UUID>"

allow if input.request.path == ["api", "environment", allowed_environment_id, "service", "deploy"]
allow if input.request.path == ["api", "application", allowed_application_id, "deploy"]
```

**Change one service, never delete** — `templates/policies/modify-one-service-never-delete.rego`:

```rego
default allow := false

allowed_application_id := "<APP_UUID>"

allow if {
	input.request.method != "DELETE"
	input.qovery_metadata.service_id == allowed_application_id
}
```

**Constrain the request body** — `templates/policies/body-constrained-env-var.rego`:

```rego
default allow := false

allowed_application_id := "<APP_UUID>"

allow if {
	input.request.method == "POST"
	input.request.path == ["api", "application", allowed_application_id, "environmentVariable"]
	startswith(input.request.body.key, "FEATURE_")
}
```

Combine rules with multiple `allow if` blocks (OR) to build "read this env AND deploy this service AND modify that service but never delete" — see the composite starter policy in the API Policy Token docs.

## 2.3b Capability → Rego building-block library

This is how you turn the Phase 1 interview into a **complete** policy: pick a **scope predicate** (from Step B) and one block per **capability** (from Step C), substitute the confirmed UUIDs, and OR them together under a single `default allow := false`.

**Scope predicate `<SCOPE>`** — the same line goes into every block:

| Step B answer | `<SCOPE>` line |
|---|---|
| one service | `input.qovery_metadata.service_id == allowed_service_id` |
| one environment | `input.qovery_metadata.environment_id == allowed_environment_id` |
| one project | `input.qovery_metadata.project_id == allowed_project_id` |
| whole org | *(omit — no resource scope; broad, confirm twice)* |

Qovery resolves `qovery_metadata` (including `project_id`) from the request path for action routes too — this is verified live: a project-scoped clone/deploy policy correctly permits those actions and denies the same actions in other projects.

**Capability blocks** — the API paths below are verified against the live API. `<SCOPE>` = the line from the table above.

| Capability | Block |
|---|---|
| **Read / observe** | `allow if { input.request.method in {"GET","HEAD"}; <SCOPE> }` |
| **Deploy / lifecycle an environment** (pick the actions you want from the set) | `env_actions := {"deploy","redeploy","stop","restart","cancelDeployment"}`<br>`allow if { input.request.method == "POST"; <SCOPE>; input.request.path[1] == "environment"; input.request.path[3] in env_actions; count(input.request.path) == 4 }` |
| **Clone an environment** | `allow if { input.request.method == "POST"; <SCOPE>; input.request.path[1] == "environment"; input.request.path[3] == "clone"; count(input.request.path) == 4 }` |
| **Deploy a specific service** (app/container/job/database/helm) | `service_kinds := {"application","container","job","database","helm"}`<br>`allow if { input.request.method == "POST"; input.qovery_metadata.service_id == allowed_service_id; input.request.path[1] in service_kinds; input.request.path[3] == "deploy"; count(input.request.path) == 4 }` |
| **Deploy selected services in an env** | `allow if { input.request.method == "POST"; <SCOPE>; input.request.path == ["api","environment", input.request.path[2], "service","deploy"] }` |
| **Manage env vars, constrained** | `allow if { input.request.method == "POST"; input.qovery_metadata.service_id == allowed_service_id; input.request.path[3] == "environmentVariable"; startswith(input.request.body.key, "FEATURE_") }` |
| **Everything except delete** on a scope | `allow if { input.request.method != "DELETE"; <SCOPE> }` |

**Assembly procedure:**
1. Emit `default allow := false` and one constant per resolved UUID (`allowed_project_id := "…"`, etc.).
2. For each capability the user picked, paste its block and substitute `<SCOPE>` and the constant names.
3. Keep the `env_actions` / `service_kinds` set to only the actions the user actually asked for (trim the set).
4. Multiple blocks = OR, which is exactly "can do A **or** B". Run Phase 3 to prove the whole thing.

**Worked example** — "clone and deploy any environment in one project, and nothing else" (verified end-to-end live) — `templates/policies/clone-deploy-project.rego`:

```rego
default allow := false

allowed_project_id := "<PROJECT_UUID>"

allow if {   # deploy any environment in the project
	input.request.method == "POST"
	input.qovery_metadata.project_id == allowed_project_id
	input.request.path[1] == "environment"
	input.request.path[3] == "deploy"
	count(input.request.path) == 4
}

allow if {   # clone any environment in the project
	input.request.method == "POST"
	input.qovery_metadata.project_id == allowed_project_id
	input.request.path[1] == "environment"
	input.request.path[3] == "clone"
	count(input.request.path) == 4
}
```

## 2.4 Common pitfalls

- **Over-broad reads.** `method == "GET"` with no resource scope lets the token read the *entire org*. Always pair a method check with an environment/service scope unless org-wide read is truly intended.
- **DELETE hiding in a different verb.** Some destructive actions are `POST` (e.g. a deploy). "Never delete" (`method != "DELETE"`) does not block a destructive `POST`. If the user means "never change production", scope by environment, not just method.
- **Guessed UUIDs.** A wrong UUID never matches — the rule silently does nothing. Use only the Phase 1 confirmed IDs.
- **`package` line.** Do not add one to `opa_policy`. (The local test harness adds a temporary one only for `opa eval`; the submitted policy must not have it — the harness strips/omits it on create.)

## 2.5 Present and confirm

Show the final policy plus a one-line explanation per rule, e.g.:

```
Rule 1 (read_only): allows GET/HEAD on environment staging (<uuid>) — read dashboards, logs, config
Rule 2 (deploy):    allows POST .../service/deploy on staging — trigger a deploy
Everything else:    denied (default allow := false) — no writes, no deletes, no other environments
```

Get explicit "yes, create it" before Phase 4. Carry the final policy string into Phase 3 for local testing.
