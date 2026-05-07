## PHASE 4: Deploy via CLI + API (Quick Path)

Use this path when the user chose "CLI + API" or wants the fastest way to deploy.

IMPORTANT — Authentication for API calls: All `curl` examples below use `Authorization: Token $QOVERY_API_TOKEN`. If you don't have an API token, you can use the CLI's token directly via `qovery auth token --print`:
```bash
# With API Token (from `qovery token create` or Console):
-H "Authorization: Token $QOVERY_API_TOKEN"

# With CLI Token (from `qovery auth token`):
-H "Authorization: Bearer $(qovery auth token --print)"
```

### 4.1 Verify Organization, Project, and Cluster

Use the organization and cluster resolved during Phase 1 (Group 1, Steps 2-3). Before creating any resources, verify they are still in the expected state:

```bash
# Verify the selected organization exists and is accessible
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | select(.id == "{selectedOrgId}") | {id, name}'

# Verify the selected cluster is healthy and ready for deployments
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | select(.id == "{selectedClusterId}") | {id, name, status, cloud_provider, region}'

# List existing projects in the selected organization
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/project" | jq '.results[] | {id, name}'
```

**Pre-flight checks before proceeding:**
- The selected cluster status MUST be `DEPLOYED` or `READY`. If it is in any other state (`DEPLOYING`, `UPGRADING`, `ERROR`, etc.), do NOT proceed. Warn the user and either wait for the cluster or ask them to select a different one.
- If the user has not yet selected an organization or cluster (e.g., they jumped directly to Phase 4), resolve them now using the logic from Phase 1, Group 1, Steps 2-3.
- Confirm the selections match what was approved in the Phase 3B deployment plan summary.

### 4.2 Create Project (if needed)

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-project",
    "description": "My application project"
  }' | jq '{id, name}'
```

### 4.3 Create Environment (if needed)

Environment modes: `PRODUCTION`, `STAGING`, `DEVELOPMENT`, `PREVIEW`

```bash
curl -s -X POST "https://api.qovery.com/project/{projectId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "mode": "PRODUCTION",
    "cluster": "{clusterId}"
  }' | jq '{id, name, mode}'
```

### 4.4 Create Database (if needed)

#### Container Mode (dev/test — cheaper, on-cluster)

```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/database" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-postgres",
    "type": "POSTGRESQL",
    "version": "16",
    "mode": "CONTAINER",
    "accessibility": "PRIVATE",
    "cpu": 250,
    "memory": 512,
    "storage": 10
  }' | jq '{id, name, type, mode}'
```

#### Managed Mode (production — cloud-managed, e.g. AWS RDS)

```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/database" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-postgres",
    "type": "POSTGRESQL",
    "version": "16",
    "mode": "MANAGED",
    "accessibility": "PRIVATE",
    "instance_type": "db.t3.medium",
    "storage": 20
  }' | jq '{id, name, type, mode}'
```

Supported database types: `POSTGRESQL`, `MYSQL`, `MONGODB`, `REDIS`

### 4.5 Create Application (from Git Repository)

Detect the git provider from the remote URL:
```bash
git remote get-url origin
```
- `github.com` -> `GITHUB`
- `gitlab.com` or self-hosted GitLab -> `GITLAB`
- `bitbucket.org` -> `BITBUCKET`

```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/application" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-app",
    "git_repository": {
      "url": "https://github.com/user/repo",
      "branch": "main",
      "root_path": "/",
      "provider": "GITHUB"
    },
    "build_mode": "DOCKER",
    "dockerfile_path": "Dockerfile",
    "cpu": 500,
    "memory": 512,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {
        "internal_port": 8080,
        "external_port": 443,
        "protocol": "HTTP",
        "publicly_accessible": true,
        "name": "http"
      }
    ],
    "healthchecks": {
      "liveness_probe": {
        "type": {
          "http": {
            "port": 8080,
            "scheme": "HTTP",
            "path": "/health"
          }
        },
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    },
    "auto_deploy": true
  }' | jq '{id, name}'
```

IMPORTANT: Adapt these values based on the user's project:
- `provider`: `GITHUB`, `GITLAB`, or `BITBUCKET` (detect from git remote URL)
- `root_path`: `/` for single-app repos, `/backend` or `/frontend` for monorepos
- `internal_port`: The port the application actually listens on
- `protocol`: `HTTP` for web apps, `GRPC` for gRPC services, `TCP`/`UDP` for raw protocols
- `healthchecks`: Set a real health check path if the app has one (e.g., `/health`, `/api/health`, `/api/v1/health`). If the app has no health endpoint, use a TCP probe instead:
  ```json
  "healthchecks": {
    "liveness_probe": {
      "type": { "tcp": { "port": 8080 } },
      "initial_delay_seconds": 30,
      "period_seconds": 10,
      "timeout_seconds": 5,
      "success_threshold": 1,
      "failure_threshold": 3
    }
  }
  ```
- For static frontends (React/Vite with nginx), use port `80` and path `/`

### 4.6 Create Container Service (from Container Registry)

If the user has a pre-built image in a registry instead of source code:

```bash
# First, find the registry ID
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/containerRegistry" | jq '.results[] | {id, name, kind}'

# Then create the container service
curl -s -X POST "https://api.qovery.com/environment/{envId}/container" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-container",
    "registry_id": "{registryId}",
    "image_name": "my-image",
    "tag": "v1.0.0",
    "cpu": 500,
    "memory": 512,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {
        "internal_port": 8080,
        "external_port": 443,
        "protocol": "HTTP",
        "publicly_accessible": true,
        "name": "http"
      }
    ],
    "healthchecks": {}
  }' | jq '{id, name}'
```

### 4.7 Set Environment Variables

IMPORTANT: Use the right scope and mechanism to avoid duplication. See Phase 6 for the full guide on aliases, interpolation, and overrides.

**Set variables at the appropriate scope:**

```bash
# SERVICE scope — specific to one application (most common for quick path)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "PORT", "value": "8080"}'

# ENVIRONMENT scope — shared by ALL services in the environment
curl -s -X POST "https://api.qovery.com/environment/{envId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "NODE_ENV", "value": "production"}'

# PROJECT scope — shared across ALL environments in the project
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "warn"}'
```

**Add secrets (encrypted at rest, cannot be retrieved via API):**

```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "JWT_SECRET", "value": "super-secret-value"}'
```

**Create aliases for database connections (preferred — stays in sync automatically):**

For connecting to Qovery-managed databases (PostgreSQL, MySQL, MongoDB, Redis), ALWAYS prefer aliases over interpolation. An alias is a live pointer — if the database is redeployed and the host changes, the alias auto-updates.

```bash
# Create an alias: DATABASE_URL points to the built-in connection URI
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "alias_parent_id": "{sourceVariableId}"}'
```

**Use interpolation only when composing or transforming values (NOT for simple DB connections):**

```bash
# Compose a URL from multiple variables — valid use of interpolation
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "BACKEND_API_URL", "value": "https://{{BACKEND_HOST}}/api/v1"}'

# Add custom query params to a DB connection — valid use of interpolation
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "value": "{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL}}?sslmode=require&pool_size=20"}'
```

**Bulk import from .env file via CLI:**

```bash
qovery env import
```

Or via CLI commands:
```bash
# List current variables
qovery application env list

# Create at service scope
qovery application env create --key PORT --value 8080

# Create at environment scope
qovery environment env create --key NODE_ENV --value production --scope ENVIRONMENT

# Create a secret
qovery application env create --key JWT_SECRET --value "..." --secret
```

### 4.8 Deploy the Environment

```bash
# Deploy all services in the environment at once
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json"

# OR deploy a single application via CLI
qovery application deploy --application "my-app"

# OR deploy via CLI (whole environment)
qovery environment deploy
```

### 4.9 Monitor Deployment

```bash
# Check status (with live updates)
qovery status --watch

# View application logs
qovery log --application "my-app"

# List all services and their statuses
qovery service list

# Get application public URLs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/link" | jq '.results'
```

---
