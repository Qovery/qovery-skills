## PHASE 3C: Blueprint Catalog Check

A **Blueprint** is a pre-built infrastructure component — a managed RDS PostgreSQL/MySQL instance, a Redis deployment, an S3 bucket, and similar pieces — published in the public `Qovery/service-catalog` GitHub repository. Deploying a blueprint reuses a maintained Terraform/OpenTofu module or Helm chart instead of hand-writing one from scratch. A single `serviceFamily` in the catalog can ship both cloud-managed and container-based variants (check the specific blueprint's `majorVersions`/manifest rather than assuming a family is only offered one way) — blueprints are not exclusively "the cloud-managed option."

This is distinct from Qovery's built-in **native container database** service (`qovery_database` resource in CONTAINER mode, Phase 4.4 / 5.6) — that is a first-class Qovery resource, not something sourced from the catalog.

**MANDATORY rule: whenever any infrastructure piece is needed — a database (dev/test or production), cache, queue, storage bucket, or any other cloud resource — check the blueprint catalog FIRST, before deciding between a native `qovery_database` resource (CONTAINER or MANAGED mode) or a hand-rolled Terraform service.** This applies regardless of environment (dev/test/staging/production). Never skip straight to Phase 4/5 for an infrastructure piece without checking 3C.1 first.

- **Blueprint match found** -> deploy the blueprint (3C.2 onward). A matching blueprint can itself be container-based, so this doesn't force cloud/managed infra onto a dev/test environment — check the specific blueprint's shape via its manifest (3C.3) and pick the option (or variable overrides) that fits dev/test vs. production sizing.
- **No blueprint match** -> fall back to the native resource: CONTAINER mode for dev/test, MANAGED mode or a hand-rolled Terraform service for production (Phase 4/5).
- **User explicitly asks to skip the catalog** (e.g. wants full control over Terraform code, or just says "use a container database") -> honor that and go straight to Phase 4/5, but only when it's an explicit ask, not a default.

### 3C.1 Fetch the Catalog

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization/{organizationId}/blueprint/catalog" \
  | jq '.blueprints[] | {name, provider, serviceFamily, categories, majorVersions: [.majorVersions[].serviceVersion]}'
```

Cache this list for the conversation — do not re-fetch it per service. Match the user's need (e.g. "I need Postgres in prod", "add a Redis cache") against `serviceFamily` + `provider` + `categories`. If the target cloud provider isn't obvious, use the same provider as the user's cluster (resolved in Phase 1) — but this only works if the cluster itself was properly resolved and confirmed with the user in Phase 1, not guessed. If a cloud resource (S3 bucket, managed database, etc.) is needed and the cluster hasn't been explicitly confirmed yet (e.g. more than one cluster exists and the user hasn't picked one), stop and go back to Phase 1 Step 3 to ask — do not infer the cluster from a name pattern just to unblock the blueprint provider match.

- **Match found** -> continue with 3C.2.
- **No match** -> tell the user no blueprint exists for this component yet, and fall back to Phase 4 (native database) or Phase 5/8 (hand-written Terraform service).

### 3C.2 Pick a Version and Resolve the Tag

Each `BlueprintItem` has one or more `majorVersions`, each with a `serviceVersion` (e.g. `"17"`) and a `latestTag` (e.g. `aws/postgres/17/1.0.1`). Ask the user which major version they want if more than one is available, otherwise use the only one. The `latestTag` is what you pass as `tag` when creating the service — do not hand-construct this string.

Optionally show the blueprint's README before proceeding, especially if the user wants to understand what the module provisions:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization/{organizationId}/blueprint/catalog/{provider}/{serviceFamily}/{serviceVersion}/readme" \
  | jq -r '.content'
```

### 3C.3 Fetch the Manifest (Form Fields)

Before creating the blueprint, fetch its manifest to learn which variables are required, which are optional, and what the engine defaults are. `environmentId` is required — use the environment resolved/created in Phase 1.

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization/{organizationId}/blueprint/catalog/{provider}/{serviceFamily}/{serviceVersion}/manifest?environmentId={environmentId}" \
  | jq '.'
```

The response's `results` array mixes two field kinds:
- `kind: "variable"` — user-editable input (e.g. `db_password`, instance size). Respect `required`, `is_secret`, `allowed_values`, `default_value`, and the type constraints in `type` (pattern/min_length/max_length for strings, min/max for numbers). Only ask the user about fields with no `default_value`, or where they may want to override the default.
- `kind: "contextVariable"` — read-only, auto-sourced from the cluster/environment (e.g. `region`). Never ask the user for these or pass them in `variables` — they resolve automatically.

The manifest also returns `engine` — the discriminated `terraform` / `opentofu` / `helm` spec with catalog defaults for version, credentials, backend, timeout, and resources. Use these defaults unless the user asks to override (see 3C.5).

### 3C.4 Create the Blueprint

```bash
curl -s -X POST "https://api.qovery.com/environment/{environmentId}/blueprint?deploy=false" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  -d '{
    "name": "my-postgres",
    "tag": "aws/postgres/17/1.0.1",
    "icon": "https://cdn.qovery.com/icons/postgresql.svg",
    "variables": [
      { "name": "instance_class", "value": "db.t3.medium", "is_secret": false },
      { "name": "db_password", "value": "REPLACE_ME", "is_secret": true }
    ]
  }' | jq '{id, tag, environment_id, catalog_url}'
```

- `name`, `tag`, and `icon` are required. Use the `icon` URL and `latestTag` from the catalog entry (3C.1) — do not invent one.
- `variables` only needs entries for fields you're overriding or that have no default; omit anything you're leaving at its manifest default.
- Set `is_secret: true` for any variable the manifest marked `is_secret: true` (passwords, API keys, connection secrets) — these are encrypted at rest and excluded from plan/diff output.
- Set the query param `deploy=true` instead of `false` to trigger deployment immediately on creation — but per this skill's Phase 3B rule, only do this after the user has confirmed the deployment plan. Prefer `deploy=false` here and trigger deployment explicitly in Phase 4/9 alongside the rest of the environment.
- `409` means a service with this name already exists in the environment — ask the user for a different name or reuse the existing service.
- `422` means the `tag` is malformed — re-fetch the catalog (3C.1) and use the exact `latestTag` string.

### 3C.5 Engine Overrides (Advanced)

Pass `spec_overrides` only when the user wants non-default engine behavior. Only fields the manifest marked `overridable: true` are accepted — anything else returns `422`.

```json
{
  "name": "my-postgres",
  "tag": "aws/postgres/17/1.0.1",
  "icon": "https://cdn.qovery.com/icons/postgresql.svg",
  "variables": [],
  "spec_overrides": {
    "engine_version": "1.13.3",
    "credentials": "cluster",
    "backend": "qovery",
    "cpu": "500m",
    "ram": "512Mi"
  }
}
```

- **Terraform/OpenTofu blueprints**: `engine_version` is REQUIRED on create — pick one of `spec.engine.terraform.allowedValues` (or `opentofu.allowedValues`) from the manifest. `credentials: cluster` (default, reuses cluster cloud credentials) vs `env` (user supplies provider credentials as env vars on the service). `backend: qovery` (default, state in a Kubernetes secret) vs `user_provided` (state in a user-controlled remote backend declared in the manifest).
- **Helm blueprints**: `engine_version`, `credentials`, and `backend` are ignored — only `timeout` and the resource fields (`cpu`, `ram`, `storage`) apply.

### 3C.6 Wiring the Blueprint into the Rest of the Environment (MANDATORY)

A blueprint that's created and deployed but never connected to the application(s) that need it is an incomplete deployment. Every application depending on a blueprint MUST have its environment variables wired to it before the task is considered done:

- List the blueprint's exposed variables and **alias** them into the dependent application(s) — never hardcode the blueprint's host/port/password/endpoint. Full step-by-step in [phase6-env-vars.md](phase6-env-vars.md) section 6.10.
- Place blueprint services in the **Infrastructure** deployment stage, same as native databases and Terraform services (see [phase5-terraform.md](phase5-terraform.md) 5.5), so they deploy before applications that depend on them. Blueprints created via API are not currently stage-assignable through this endpoint — if strict ordering is required, deploy the blueprint first and confirm it's healthy before deploying dependent applications (Phase 9).
- This wiring must show up explicitly in the Phase 3B deployment plan (as a "Blueprints to deploy" row plus an "Environment variables to set" alias entry) before the user confirms.

### 3C.7 Checking for and Applying Updates

If the user already has a blueprint-based service and wants to check for a newer catalog version:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/blueprint/{blueprintId}/update" | jq '.'
```

This returns `is_up_to_date`, `current_tag`, `latest_tag`, and diffs (`new_required_values`, `new_optional_values`, `now_required_values`, `updated_values`, `removed_values`, `engine_diff`, `new_major_versions`). Always show this diff to the user before updating — new required values or breaking `engine_diff` changes need explicit review.

Preview the update as a dry run first (no persisted changes):

```bash
curl -s -X POST "https://api.qovery.com/blueprint/{blueprintId}/update/preview" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  -d '{"variables": {"instance_class": {"value": "db.t3.large"}}, "spec_overrides": null}'
```

`variables` and `spec_overrides` follow JSON Merge Patch (RFC 7396) semantics: a non-null value upserts that key, `null` removes it, an absent key is left untouched. Once the user confirms the preview, persist it — `name`, `tag`, and `icon` are required on every call even though only the diffed fields actually change:

```bash
curl -s -X PATCH "https://api.qovery.com/blueprint/{blueprintId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  -d '{
    "name": "my-postgres",
    "tag": "aws/postgres/17/1.1.0",
    "icon": "https://cdn.qovery.com/icons/postgresql.svg",
    "variables": {"instance_class": {"value": "db.t3.large"}},
    "spec_overrides": null
  }' | jq '{id, tag}'
```

### 3C.8 When NOT to Use a Blueprint

The catalog check (3C.1) always runs first, but the blueprint itself is skipped when:

- **No blueprint exists** yet for the requested component/provider/version combination — fall back to the native database resource (Phase 4.4/5.6/5.7) or a hand-rolled Terraform service (Phase 5.8/5.15) or Helm chart (Phase 5.12).
- **The user explicitly asks for the native/bare resource** — e.g. "just use a container database", "I don't need a managed anything, keep it simple", or wants full control over hand-written Terraform code rather than a catalog-maintained module.
- **The user needs Terraform-file-based, version-controlled infrastructure as code committed to their own repo** — blueprints are created and managed through the API/Console, not through the user's `qovery.tf`. Mention this trade-off if they're on the Terraform deployment path (Phase 5).

Never skip the catalog check itself just because the environment is dev/test — a container-based blueprint may still be the best fit; only skip the *blueprint* (not the check) when one of the above applies.

---
