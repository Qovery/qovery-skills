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
