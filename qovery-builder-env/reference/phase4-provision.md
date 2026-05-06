## PHASE 4: Provision Builder Environments

### 4.1 Strategy — One Environment Per Builder (Never Shared)

Each builder gets their **own isolated environment** cloned from the blueprint. Environments are **NEVER shared** between builders — this is a fundamental security and auditability requirement.

**How it works:**
1. The **blueprint environment** (created in Phase 3) serves as a template. It is never used directly by builders — it exists solely to be cloned.
2. Each builder gets a **clone of the blueprint** via the Qovery clone API. The clone includes all services (IDE, database, etc.) with an identical configuration.
3. Each builder connects to **their own environment** via a unique URL. They cannot see or access other builders' environments.
4. If project-per-builder isolation was chosen (Phase 1.3), each builder's environment lives in its **own Qovery project**, providing complete visibility isolation.

This ensures:
- **Isolation**: Builders can't interfere with each other's work — each has their own services, database, and data
- **Independence**: Each builder can deploy, restart, and manage their own environment without affecting others
- **Audit**: All actions are tracked per-environment, tied to the builder's identity
- **Cost tracking**: Per-builder cost visibility — you know exactly what each builder costs
- **Security**: With project-per-builder mode, builders cannot see each other's environment variables, secrets, or data

Naming convention: `builder-{name}` (e.g., `builder-alice`, `builder-bob`)

### 4.2 Clone Blueprint for Each Builder

For each builder, clone the blueprint environment into their own workspace. The exact steps depend on the isolation mode chosen in Phase 1.3.

**If project-per-builder isolation (Option B) — create the builder's project first:**

```bash
# 1. Create a dedicated project for this builder
PROJECT_ID=$(curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-{name}", "description": "Builder workspace for {name} ({team})"}' | jq -r '.id')

# 2. Create a per-builder RBAC role scoped to this project
ROLE_ID=$(curl -s -X POST "https://api.qovery.com/organization/{orgId}/customRole" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Builder-{name}", "description": "Builder role for {name} — access to builder-{name} project only"}' | jq -r '.id')

# 3. Configure the role with access to only this builder's project
curl -s -X PUT "https://api.qovery.com/organization/{orgId}/customRole/$ROLE_ID" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Builder-{name}\",
    \"cluster_permissions\": [
      {\"cluster_id\": \"{builderClusterId}\", \"permission\": \"ENV_CREATOR\"}
    ],
    \"project_permissions\": [
      {
        \"project_id\": \"$PROJECT_ID\",
        \"is_admin\": false,
        \"permissions\": [
          {\"environment_type\": \"DEVELOPMENT\", \"permission\": \"DEPLOYER\"},
          {\"environment_type\": \"STAGING\", \"permission\": \"VIEWER\"},
          {\"environment_type\": \"PRODUCTION\", \"permission\": \"NO_ACCESS\"},
          {\"environment_type\": \"PREVIEW\", \"permission\": \"DEPLOYER\"}
        ]
      }
    ]
  }"

# 4. Clone the blueprint into this builder's project
ENV_ID=$(curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"workspace\", \"cluster_id\": \"{clusterId}\", \"mode\": \"DEVELOPMENT\", \"project_id\": \"$PROJECT_ID\"}" | jq -r '.id')
```

Note: The clone API supports a `project_id` parameter that places the cloned environment into a different project than the source. This is how the blueprint (in the `builder-blueprints` project) is cloned into each builder's own project.

**If shared project (Option A) — clone directly into the shared project:**

```bash
# Clone the blueprint into the shared project (no project_id needed — it stays in the same project)
ENV_ID=$(curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-{name}", "cluster_id": "{clusterId}", "mode": "DEVELOPMENT"}' | jq -r '.id')
```

**Via CLI (shared project mode):**
```bash
qovery environment clone --environment "builder-template" --name "builder-{name}"
```

**After cloning (both modes), deploy the builder's environment:**
```bash
curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

### 4.3 Invite Builders to Qovery

For each builder, invite them to the Qovery organization with the "Builder" custom role:

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/inviteMember" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "{builder-email}",
    "role_id": "{builderRoleId}"
  }'
```

The builder will receive an email invitation. With SSO configured, they log in with their company credentials.

### 4.4 Provisioning Script — The Platform Team's Main Tool

Generate a comprehensive provisioning script that the platform team uses to onboard new builders. This is the **primary operational tool** — it reads the platform configuration, creates everything needed for a new builder, and outputs the workspace URL.

The script handles both isolation modes and includes TTL lifecycle job creation.

**Single builder provisioning (`provision-builder.sh`):**

```bash
#!/usr/bin/env bash
# provision-builder.sh — Provision a single new builder environment
# Usage: ./provision-builder.sh <name> <email> <team>
# Example: ./provision-builder.sh alice alice@company.com sales
#
# Reads platform preferences from builder-platform-config.yaml
# Creates: project (if project-per-builder), environment (cloned from blueprint),
#          TTL lifecycle job, RBAC role, member invitation

set -euo pipefail

# --- Arguments ---
BUILDER_NAME="${1:?Usage: $0 <name> <email> <team>}"
BUILDER_EMAIL="${2:?Usage: $0 <name> <email> <team>}"
BUILDER_TEAM="${3:?Usage: $0 <name> <email> <team>}"

# --- Load platform config ---
CONFIG_FILE="$(dirname "$0")/../builder-platform-config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  echo "Run the qovery-builder-env skill first to generate the platform config."
  exit 1
fi

# Parse YAML config (requires yq or fallback to grep)
parse_config() {
  if command -v yq &>/dev/null; then
    yq -r "$1" "$CONFIG_FILE"
  else
    grep -A0 "$(echo "$1" | tr '.' '\n' | tail -1):" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"'
  fi
}

ORG_ID=$(parse_config '.organization_id')
CLUSTER_ID=$(parse_config '.cluster_id')
BLUEPRINT_ENV_ID=$(parse_config '.blueprint_env_id')
ISOLATION=$(parse_config '.isolation')
TTL_STOP_AFTER=$(parse_config '.ttl.stop_after')
TTL_DELETE_AFTER=$(parse_config '.ttl.delete_after')
SHARED_PROJECT_ID=$(parse_config '.shared_project_id')
BASE_ROLE_ID=$(parse_config '.builder_role_id')

API_TOKEN="${QOVERY_API_TOKEN:?Set QOVERY_API_TOKEN environment variable}"
BASE_URL="https://api.qovery.com"

echo "========================================="
echo "Provisioning builder: $BUILDER_NAME"
echo "  Email: $BUILDER_EMAIL"
echo "  Team:  $BUILDER_TEAM"
echo "  Mode:  $ISOLATION"
echo "========================================="
echo ""

# --- Step 1: Create project (if project-per-builder) ---
if [ "$ISOLATION" = "project-per-builder" ]; then
  echo "[1/6] Creating project: builder-$BUILDER_NAME"
  PROJECT_ID=$(curl -sf -X POST "$BASE_URL/organization/$ORG_ID/project" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"builder-$BUILDER_NAME\", \"description\": \"Builder workspace for $BUILDER_NAME ($BUILDER_TEAM)\"}" | jq -r '.id')
  echo "  Project created: $PROJECT_ID"
else
  echo "[1/6] Using shared project: $SHARED_PROJECT_ID"
  PROJECT_ID="$SHARED_PROJECT_ID"
fi

# --- Step 2: Create per-builder RBAC role (if project-per-builder) ---
if [ "$ISOLATION" = "project-per-builder" ]; then
  echo "[2/6] Creating RBAC role: Builder-$BUILDER_NAME"
  ROLE_ID=$(curl -sf -X POST "$BASE_URL/organization/$ORG_ID/customRole" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"Builder-$BUILDER_NAME\", \"description\": \"Builder role for $BUILDER_NAME — access to builder-$BUILDER_NAME project only\"}" | jq -r '.id')

  curl -sf -X PUT "$BASE_URL/organization/$ORG_ID/customRole/$ROLE_ID" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Builder-$BUILDER_NAME\",
      \"cluster_permissions\": [{\"cluster_id\": \"$CLUSTER_ID\", \"permission\": \"ENV_CREATOR\"}],
      \"project_permissions\": [{
        \"project_id\": \"$PROJECT_ID\",
        \"is_admin\": false,
        \"permissions\": [
          {\"environment_type\": \"DEVELOPMENT\", \"permission\": \"DEPLOYER\"},
          {\"environment_type\": \"STAGING\", \"permission\": \"VIEWER\"},
          {\"environment_type\": \"PRODUCTION\", \"permission\": \"NO_ACCESS\"},
          {\"environment_type\": \"PREVIEW\", \"permission\": \"DEPLOYER\"}
        ]
      }]
    }" > /dev/null
  echo "  Role created: $ROLE_ID"
else
  echo "[2/6] Using shared role: $BASE_ROLE_ID"
  ROLE_ID="$BASE_ROLE_ID"
fi

# --- Step 3: Clone the blueprint environment ---
echo "[3/6] Cloning blueprint into builder-$BUILDER_NAME"
CLONE_BODY="{\"name\": \"workspace\", \"cluster_id\": \"$CLUSTER_ID\", \"mode\": \"DEVELOPMENT\""
if [ "$ISOLATION" = "project-per-builder" ]; then
  CLONE_BODY="$CLONE_BODY, \"project_id\": \"$PROJECT_ID\""
else
  CLONE_BODY="{\"name\": \"builder-$BUILDER_NAME\", \"cluster_id\": \"$CLUSTER_ID\", \"mode\": \"DEVELOPMENT\""
fi
CLONE_BODY="$CLONE_BODY}"

ENV_ID=$(curl -sf -X POST "$BASE_URL/environment/$BLUEPRINT_ENV_ID/clone" \
  -H "Authorization: Token $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CLONE_BODY" | jq -r '.id')
echo "  Environment cloned: $ENV_ID"

# --- Step 4: Create TTL lifecycle job (auto-stop/delete) ---
if [ "$TTL_STOP_AFTER" != "null" ] && [ "$TTL_STOP_AFTER" != "none" ]; then
  echo "[4/6] Creating TTL lifecycle job (stop after $TTL_STOP_AFTER)"

  # Generate a shutdown token for this builder
  SHUTDOWN_TOKEN=$(curl -sf -X POST "$BASE_URL/organization/$ORG_ID/apiToken" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"builder-ttl-$BUILDER_NAME\", \"description\": \"Auto-shutdown token for builder-$BUILDER_NAME\"}" | jq -r '.token')

  # Calculate cron schedule based on TTL
  # For simplicity, this uses a relative approach — the cron job runs periodically
  # and checks if the environment has been running longer than the TTL
  CRON_SCHEDULE="0 */1 * * *"  # Check every hour

  # Create the TTL cron job
  TTL_JOB_ID=$(curl -sf -X POST "$BASE_URL/environment/$ENV_ID/job" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"ttl-auto-shutdown\",
      \"description\": \"Automatically stops this environment after $TTL_STOP_AFTER of uptime\",
      \"cpu\": 250,
      \"memory\": 256,
      \"max_nb_restart\": 0,
      \"max_duration_seconds\": 60,
      \"auto_preview\": false,
      \"auto_deploy\": false,
      \"healthchecks\": {},
      \"source\": {
        \"docker\": {
          \"dockerfile_raw\": \"FROM curlimages/curl:8.11.1\nENTRYPOINT [\\\"sh\\\", \\\"-c\\\"]\"
        }
      },
      \"schedule\": {
        \"cronjob\": {
          \"entrypoint\": \"sh\",
          \"arguments\": [\"-c\", \"curl -sf -X POST https://api.qovery.com/environment/$ENV_ID/stop -H 'Authorization: Token '\\''\$SHUTDOWN_TOKEN'\\'' && echo 'Environment stopped by TTL job' || echo 'Stop request failed or already stopped'\"],
          \"scheduled_at\": \"$CRON_SCHEDULE\",
          \"timezone\": \"Etc/UTC\"
        }
      }
    }" | jq -r '.id')

  # Set the shutdown token as a secret on the job
  curl -sf -X POST "$BASE_URL/application/$TTL_JOB_ID/secret" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"SHUTDOWN_TOKEN\", \"value\": \"$SHUTDOWN_TOKEN\"}" > /dev/null
  echo "  TTL job created: $TTL_JOB_ID"
else
  echo "[4/6] No TTL configured — skipping lifecycle job"
fi

# --- Step 5: Invite the builder ---
echo "[5/6] Inviting $BUILDER_EMAIL with role $ROLE_ID"
curl -sf -X POST "$BASE_URL/organization/$ORG_ID/inviteMember" \
  -H "Authorization: Token $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$BUILDER_EMAIL\", \"role_id\": \"$ROLE_ID\"}" > /dev/null 2>&1 || echo "  (already invited)"
echo "  Invitation sent"

# --- Step 6: Deploy the environment ---
echo "[6/6] Deploying builder-$BUILDER_NAME"
curl -sf -X POST "$BASE_URL/environment/$ENV_ID/deploy" \
  -H "Authorization: Token $API_TOKEN" > /dev/null
echo "  Deployment triggered"

echo ""
echo "========================================="
echo "Builder provisioned successfully!"
echo "  Name:        $BUILDER_NAME"
echo "  Email:       $BUILDER_EMAIL"
echo "  Team:        $BUILDER_TEAM"
echo "  Project:     $PROJECT_ID"
echo "  Environment: $ENV_ID"
echo "  Isolation:   $ISOLATION"
echo "  TTL:         ${TTL_STOP_AFTER:-none}"
echo ""
echo "  Console: https://console.qovery.com/organization/$ORG_ID/project/$PROJECT_ID/environment/$ENV_ID"
echo ""
echo "  The workspace URL will be available once deployment completes."
echo "  Check status: curl -s -H 'Authorization: Token \$QOVERY_API_TOKEN' \\"
echo "    'https://api.qovery.com/environment/$ENV_ID/statuses' | jq '.environment.state'"
echo "========================================="
```

**Bulk provisioning (`bulk-provision.sh`):**

```bash
#!/usr/bin/env bash
# bulk-provision.sh — Provision multiple builder environments from CSV
# Usage: ./bulk-provision.sh builders.csv
#
# CSV format: name,email,team
# Example:
#   alice,alice@company.com,sales
#   bob,bob@company.com,finance
#   carol,carol@company.com,ops

set -euo pipefail

CSV_FILE="${1:?Usage: $0 <builders.csv>}"
SCRIPT_DIR="$(dirname "$0")"

echo "Bulk provisioning from: $CSV_FILE"
echo ""

count=0
while IFS=, read -r name email team; do
  # Skip header row if present
  [[ "$name" == "name" ]] && continue
  # Skip empty lines
  [[ -z "$name" ]] && continue

  count=$((count + 1))
  echo "--- Builder $count: $name ---"
  "$SCRIPT_DIR/provision-builder.sh" "$name" "$email" "$team"
  echo ""
done < "$CSV_FILE"

echo "========================================="
echo "Bulk provisioning complete: $count builders provisioned."
echo "========================================="
```

### 4.5 Share Access URLs and Quick Start

After all environments are deployed, collect the workspace URLs:

```bash
# For each builder environment, get the workspace URL
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{workspaceAppId}/link" | jq '.results[0].url'
```

Present a summary to the platform engineer:

> **Builder Environments Provisioned**
>
> | Builder | Team | Environment | Workspace URL | Status |
> |---------|------|-------------|--------------|--------|
> | Alice | Sales | builder-alice | https://builder-alice-workspace.{domain} | DEPLOYED |
> | Bob | Finance | builder-bob | https://builder-bob-workspace.{domain} | DEPLOYING |
> | Carol | Ops | builder-carol | https://builder-carol-workspace.{domain} | DEPLOYED |
>
> **Console:** https://console.qovery.com/organization/{orgId}/project/{projectId}
>
> Share the workspace URLs with each builder along with the onboarding guide (Phase 9).

---

