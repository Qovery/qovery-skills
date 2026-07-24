## PHASE 6: Environment Variables — Scopes, Aliases, Interpolation & Overrides

Qovery has a powerful environment variable system with three mechanisms that AVOID duplicating variables and keep configuration DRY. You MUST understand and use these properly.

### 6.1 Three Core Mechanisms

| Mechanism | What it does | When to use |
|---|---|---|
| **Alias** | Creates a live *reference* (pointer) to another variable. If the source changes, the alias auto-updates. | Renaming built-in variables to match what your app expects (e.g., `DATABASE_URL` as alias of `QOVERY_DATABASE_..._CONNECTION_URI`) |
| **Interpolation** | Substitutes `{{VAR_NAME}}` placeholders with variable values at deploy time. Allows composing values from multiple variables. | Building connection strings, composing URLs, embedding env names in bucket names |
| **Override** | Changes the value of a variable defined at a broader scope (project/environment) for a specific narrower scope (environment/service). | Different config per environment or service (e.g., `LOG_LEVEL=warn` at project, overridden to `debug` for one service) |

Key distinctions:
- **Alias** = "This variable IS that variable" (a live pointer — stays in sync)
- **Interpolation** = "This variable's value CONTAINS that variable's value" (string substitution at deploy time)
- **Override** = "This variable REPLACES the inherited value from a broader scope"

### 6.2 Variable Scopes & Override Hierarchy

Variables can be defined at three scopes. Narrower scopes automatically override broader ones:

```
Project Scope (broadest — shared across ALL environments)
  └── LOG_LEVEL=warn
  └── APP_NAME=myapp
  └── SUPPORT_EMAIL=support@acme.com

  Environment Scope (shared across all services in ONE environment)
    └── LOG_LEVEL=info              ← overrides project's "warn" for this env
    └── API_URL=https://staging.api.com

    Service Scope (narrowest — specific to ONE service)
      └── LOG_LEVEL=debug           ← overrides environment's "info" for this service
      └── PORT=8080
```

**Rule: Define variables at the BROADEST scope possible, override only where needed.**

In Terraform, use `environment_variable_overrides` to override a variable from a broader scope:

```hcl
# Set at environment level (applies to all services)
resource "qovery_environment" "main" {
  environment_variables = [
    { key = "LOG_LEVEL", value = "info" },
    { key = "NODE_ENV", value = "production" }
  ]
}

# Override at service level (only this service gets "debug")
resource "qovery_application" "backend" {
  # Regular service-specific variables
  environment_variables = [
    { key = "PORT", value = "8080" }
  ]

  # Override a variable from environment or project scope
  environment_variable_overrides = [
    { key = "LOG_LEVEL", value = "debug" }
  ]
}
```

Via CLI:
```bash
# Create at environment scope (shared by all services)
qovery environment env create --key LOG_LEVEL --value info --scope ENVIRONMENT

# Create at service scope (overrides the environment-level value for this service)
qovery application env create --key LOG_LEVEL --value debug

# Create a secret at service scope
qovery application env create --key JWT_SECRET --value "..." --secret
```

Via API:
```bash
# Create at project scope
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "warn"}'

# Create at environment scope
curl -s -X POST "https://api.qovery.com/environment/{envId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "info"}'

# Create at service scope (overrides broader scopes)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "debug"}'
```

### 6.3 Built-in Variables (Auto-Generated)

Qovery automatically generates and injects variables for databases, applications, and system info. These are read-only and always available in all services within the same environment.

#### Database Connection Variables

Pattern: `QOVERY_DATABASE_{TYPE}_{NAME}_{PROPERTY}`

The NAME is your database name with hyphens replaced by underscores and uppercased.

| Variable | Example (DB named "postgres") | Description |
|---|---|---|
| `..._HOST` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST` | External hostname |
| `..._HOST_INTERNAL` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL` | Internal hostname (use this for in-cluster communication) |
| `..._PORT` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_PORT` | Port number |
| `..._LOGIN` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_LOGIN` | Username |
| `..._PASSWORD` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD` | Password (secret) |
| `..._CONNECTION_URI` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI` | Full external connection URI |
| `..._CONNECTION_URI_INTERNAL` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL` | Internal connection URI (preferred) |
| `..._DEFAULT_DATABASE_NAME` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_DEFAULT_DATABASE_NAME` | Default database name |

#### Application Connection Variables

Pattern: `QOVERY_APPLICATION_{NAME}_{PROPERTY}`

| Variable | Description |
|---|---|
| `QOVERY_APPLICATION_{NAME}_HOST_INTERNAL` | Internal hostname (cluster network) |
| `QOVERY_APPLICATION_{NAME}_HOST_EXTERNAL` | Public hostname (if publicly accessible) |
| `QOVERY_APPLICATION_{NAME}_PORT` | Service port |

#### System Variables

```
QOVERY_PROJECT_ID              — Project UUID
QOVERY_ENVIRONMENT_ID          — Environment UUID
QOVERY_ENVIRONMENT_NAME        — Environment name (e.g., "production")
QOVERY_CLOUD_PROVIDER          — Cloud provider (AWS, GCP, AZURE, SCW)
QOVERY_CLOUD_PROVIDER_REGION   — Cloud region (e.g., "us-east-1")
QOVERY_KUBERNETES_CLUSTER_VPC_ID — VPC ID of the cluster (useful for Terraform services)
```

### 6.4 Aliases — Renaming Built-in Variables

Aliases create a **live reference** to another variable. Unlike interpolation, an alias is a pointer — if the source variable changes (e.g., database host changes on redeploy), the alias automatically reflects the new value.

Use aliases to make Qovery's built-in variable names match what your application expects.

In Terraform — use `environment_variable_aliases`:
```hcl
resource "qovery_application" "backend" {
  # ... other config ...

  # Aliases: create friendly names pointing to built-in variables
  environment_variable_aliases = [
    {
      key   = "DATABASE_URL"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL"
    },
    {
      key   = "DATABASE_HOST"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL"
    },
    {
      key   = "DATABASE_PASSWORD"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD"
    },
    {
      key   = "REDIS_URL"
      value = "QOVERY_CONTAINER_REDIS_HOST_INTERNAL"
    }
  ]
}
```

For referencing another application's host (the ID-based pattern):
```hcl
  environment_variable_aliases = [
    {
      key   = "BACKEND_HOST"
      value = "QOVERY_APPLICATION_Z${upper(element(split("-", qovery_application.backend.id), 0))}_HOST_EXTERNAL"
    }
  ]
```

IMPORTANT: The `value` in an alias is the **name** of the source variable (NOT its value, and NOT wrapped in `{{}}`). It's a reference, not interpolation.

Via API:
```bash
# Create an alias
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "DATABASE_URL",
    "alias_parent_id": "{sourceVariableId}"
  }'
```

### 6.5 Interpolation — Composing Values

Interpolation uses `{{VARIABLE_NAME}}` syntax inside a variable value. The placeholders are resolved at deploy time.

Use interpolation when you need to **compose** a value from multiple variables, or embed a variable value inside a larger string.

IMPORTANT: For simple database connections (no custom parameters), use an **alias** instead (see 6.4). Only use interpolation for database connections when you need to add custom query parameters or compose a connection string from parts.

```hcl
resource "qovery_application" "backend" {
  environment_variables = [
    # Compose a custom connection string WITH extra parameters — valid use of interpolation
    # (For simple DB connections without params, use an alias in environment_variable_aliases instead!)
    {
      key   = "DATABASE_URL_WITH_PARAMS"
      value = "postgresql://{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_LOGIN}}:{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD}}@{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL}}:{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_PORT}}/{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_DEFAULT_DATABASE_NAME}}?sslmode=require&pool_size=20"
    },
    # Compose a URL from an alias or another variable
    {
      key   = "NEXT_PUBLIC_API_URL"
      value = "https://{{BACKEND_HOST}}/api/v1"
    },
    # Embed environment name in resource names
    {
      key   = "S3_BUCKET_NAME"
      value = "myapp-{{QOVERY_ENVIRONMENT_NAME}}-storage"
    },
    # Use system variables for cloud-aware configuration
    {
      key   = "AWS_REGION"
      value = "{{QOVERY_CLOUD_PROVIDER_REGION}}"
    }
  ]
}
```

Via API — interpolation works the same way in the `value` field:
```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "BACKEND_API_URL",
    "value": "https://{{BACKEND_HOST}}:{{BACKEND_PORT}}/api"
  }'
```

For Helm charts, use the `qovery.env.VARIABLE_NAME` macro in chart values instead of `{{...}}`:
```yaml
# In Helm values_override
database:
  host: "qovery.env.DATABASE_HOST"
  port: "qovery.env.DATABASE_PORT"
  password: "qovery.env.DATABASE_PASSWORD"
```

### 6.6 Alias vs Interpolation — When to Use Which

| Scenario | Use Alias | Use Interpolation |
|---|---|---|
| `DATABASE_URL` for PostgreSQL/MySQL/MongoDB/Redis (no custom params) | YES — alias on `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL` | NO |
| `DATABASE_URL` with custom query params (`?sslmode=require&pool_size=20`) | NO | YES — compose from parts |
| `REDIS_HOST` pointing to a Qovery-managed Redis | YES — alias on `QOVERY_CONTAINER_REDIS_HOST_INTERNAL` | NO |
| `DATABASE_HOST`, `DATABASE_PASSWORD` individually | YES — alias each to the built-in variable | NO |
| `API_URL` = `https://{host}/api/v1` | | YES — compose URL with path |
| `S3_BUCKET` = `myapp-{env-name}-storage` | | YES — embed env name |
| Frontend `NEXT_PUBLIC_API_URL` pointing to backend's external host | Use alias for the host, then interpolation for the full URL | |

General rule: **For Qovery-managed database connections, ALWAYS use aliases. Use interpolation only when you need to compose, transform, or add parameters.**

### 6.7 Variable as File

Qovery supports mounting an environment variable's value as a file at a specific path in the container filesystem. This is useful for config files, certificates, and SSH keys.

Via API:
```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "APP_CONFIG",
    "value": "server:\n  port: 8080\n  host: 0.0.0.0\n  log_level: info",
    "mount_path": "/etc/config/app.yaml"
  }'
```

Use cases:
- TLS certificates and private keys
- Application config files (YAML, JSON, TOML)
- SSH keys for private git access
- Nginx/Apache config snippets

### 6.8 CLI Commands for Variable Management

```bash
# === Import / Export ===

# Import .env file into a service (bulk import)
qovery env import

# Export current variables to .env file (for local development)
qovery env parse

# === Service-level variables ===

# List all variables for a service
qovery application env list

# Create a variable
qovery application env create --key PORT --value 8080

# Create a secret
qovery application env create --key JWT_SECRET --value "my-secret" --secret

# Update a variable
qovery application env update --key PORT --value 3000

# Delete a variable
qovery application env delete --key PORT

# === Environment-level variables ===

# List environment variables
qovery environment env list

# Create at environment scope (shared by all services)
qovery environment env create --key LOG_LEVEL --value info --scope ENVIRONMENT

# === Other service types ===
qovery container env list
qovery container env create --key MY_VAR --value my_value
qovery cronjob env list
qovery lifecycle env list
```

### 6.9 Best Practices — Avoid Duplication

Follow these rules to keep environment variables clean and DRY:

1. **Shared config → Project scope**: Variables identical across all environments (company name, support email, CDN URL). Define once, inherit everywhere.

2. **Environment-specific config → Environment scope**: Variables that differ per environment (API URLs, feature flags, log levels). Define at environment scope, not duplicated on every service.

3. **Service-unique config → Service scope**: Variables truly unique to one service (PORT, WORKERS, service-specific API keys). Only use service scope when the variable is NOT shared.

4. **NEVER duplicate built-in variables**: Use **aliases** instead. Don't create `DATABASE_URL` with a hardcoded copy of the connection string — create an alias pointing to `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL`. The alias stays in sync automatically.

5. **Use interpolation for composed values**: Don't copy-paste connection strings. Compose them from built-in variable parts using `{{...}}` syntax.

6. **Use overrides to customize per-environment or per-service**: If most environments need `LOG_LEVEL=warn` but staging needs `debug`, set `warn` at project scope and override it at the staging environment scope. Don't set `LOG_LEVEL` independently on every environment.

7. **Prefer `_INTERNAL` variants for in-cluster communication**: Always use `HOST_INTERNAL` and `CONNECTION_URI_INTERNAL` for services communicating within the same cluster. External variants route through the internet, adding latency and cost.

8. **Secrets are scoped too**: Secret overrides work the same way as regular variable overrides. Define a secret at project scope and override its value at environment scope for different environments.

### 6.10 Wiring Applications to a Blueprint-Provisioned Resource (MANDATORY)

Whenever an infrastructure piece was deployed as a **Blueprint** (Phase 3C) instead of a native database, any application that needs to reach it MUST be wired up here — creating the blueprint alone does NOT connect it to your app. Do not leave a blueprint deployed with no application referencing it, and never hardcode its connection details.

1. **List the blueprint service's exposed variables** once it's created (and ideally after its first successful deploy, since some values like a generated password or endpoint resolve only post-apply):
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
     "https://api.qovery.com/environment/{environmentId}/environmentVariable" \
     | jq '.results[] | select(.service_id == "{blueprintServiceId}") | {id, key, scope}'
   ```
   Terraform/OpenTofu-engine blueprints expose their module's `output` blocks as environment variables on the service (e.g. a generated `endpoint`, `port`, `username`, `password`); Helm-engine blueprints expose whatever the chart's notes/values surface the same way native Helm services do. Names vary by blueprint — there's no fixed `QOVERY_DATABASE_*` pattern like native databases have, so always list them rather than guessing.

2. **Alias each variable the application needs**, exactly like you would for a native database (6.4) — never hardcode the blueprint's host/port/password into the application's own variables:
   ```bash
   curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -H "User-Agent: QoverySkill/qovery-deploy (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
     -d '{"key": "DATABASE_URL", "alias_parent_id": "{blueprintEndpointVariableId}"}'
   ```
   If the blueprint doesn't expose one composed connection-string variable (common for Terraform-engine blueprints, which tend to expose host/port/user/password separately), alias each part individually and compose the final URL with **interpolation** (6.5) the same way you would compose a custom-params `DATABASE_URL` from a native database's parts.

3. **Confirm in the Phase 3B plan**: the "Environment variables to set" section must list the alias/interpolation wiring from each application to each blueprint it depends on — this is exactly as required as wiring to a native database, and must be present before the user confirms the plan.

4. **Verify after deploy** (Phase 9): once both the blueprint and the dependent application are healthy, confirm the application can actually resolve and use the aliased variables (e.g. check logs for a successful DB connection, or exec into the pod and inspect the env). A blueprint that deployed successfully but whose variables were never wired into the consuming service is an incomplete deployment — treat it as a failure to fix (Phase 10), not a done task.

---

