#!/usr/bin/env bash
# provision-builder.sh — Provision a new builder environment
# Usage: ./provision-builder.sh <name> <email>
# Example: ./provision-builder.sh alice alice@company.com
#
# Clones the blueprint, creates a per-builder project + RBAC role,
# updates the inherited TTL job, invites the builder, and deploys.
#
# Idempotent: safe to run multiple times — reuses existing resources
# on 409 conflicts instead of failing.

set -euo pipefail

NAME="${1:?Usage: $0 <name> <email>}"
EMAIL="${2:?Usage: $0 <name> <email>}"

# --- Fill these in after running the skill (Phase 2) ---
ORG_ID="FILL_IN_ORG_ID"
CLUSTER_ID="FILL_IN_CLUSTER_ID"
BLUEPRINT_ENV_ID="FILL_IN_BLUEPRINT_ENV_ID"
DOCKER_HUB_REGISTRY_ID="FILL_IN_DOCKER_HUB_REGISTRY_ID"
# --------------------------------------------------------

API_TOKEN="${QOVERY_API_TOKEN:?Set QOVERY_API_TOKEN environment variable}"
BASE="https://api.qovery.com"
SKILLS_VERSION=$(cat "$(dirname "$0")/../_version.txt" 2>/dev/null || echo "unknown")
UA="QoverySkill/qovery-builder-env (version:$SKILLS_VERSION; https://github.com/Qovery/qovery-skills)"

# Helper: make API calls with proper error handling
# Returns the response body on success; prints error and returns 1 on failure.
api() {
  local method="$1" endpoint="$2"
  shift 2
  local response http_code body

  response=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE$endpoint" \
    -H "Authorization: Token $API_TOKEN" \
    -H "User-Agent: $UA" \
    -H "Content-Type: application/json" \
    "$@")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: $method $endpoint returned HTTP $http_code" >&2
    echo "$body" | jq '.' 2>/dev/null || echo "$body" >&2
    return 1
  fi

  echo "$body"
}

echo "Provisioning builder: $NAME ($EMAIL)"
echo ""

# 1. Create project (or reuse if it already exists)
echo "Step 1: Creating project builder-$NAME..."
PROJECT_RESPONSE=$(api POST "/organization/$ORG_ID/project" \
  -d "{\"name\":\"builder-$NAME\",\"description\":\"Builder workspace for $NAME\"}" 2>&1) || {
  # Check if it's a 409 conflict (already exists) — reuse it
  if echo "$PROJECT_RESPONSE" | grep -qi "409\|already exists\|already used\|Conflict"; then
    echo "  Project builder-$NAME already exists, reusing..."
    PROJECT_ID=$(api GET "/organization/$ORG_ID/project" | jq -r ".results[] | select(.name == \"builder-$NAME\") | .id")
  else
    echo "  Failed to create project:" >&2
    echo "$PROJECT_RESPONSE" >&2
    exit 1
  fi
}
PROJECT_ID="${PROJECT_ID:-$(echo "$PROJECT_RESPONSE" | jq -r '.id')}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "  ERROR: Could not get project ID" >&2
  exit 1
fi
echo "  Project: $PROJECT_ID"

# 2. Create RBAC role (or reuse if it already exists)
echo "Step 2: Creating RBAC role Builder-$NAME..."
ROLE_RESPONSE=$(api POST "/organization/$ORG_ID/customRole" \
  -d "{\"name\":\"Builder-$NAME\",\"description\":\"Access to builder-$NAME only\"}" 2>&1) || {
  if echo "$ROLE_RESPONSE" | grep -qi "409\|already exists\|already used\|Conflict"; then
    echo "  Role Builder-$NAME already exists, reusing..."
    ROLE_ID=$(api GET "/organization/$ORG_ID/customRole" | jq -r ".results[] | select(.name == \"Builder-$NAME\") | .id")
  else
    echo "  Failed to create role:" >&2
    echo "$ROLE_RESPONSE" >&2
    exit 1
  fi
}
ROLE_ID="${ROLE_ID:-$(echo "$ROLE_RESPONSE" | jq -r '.id')}"
if [[ -z "$ROLE_ID" || "$ROLE_ID" == "null" ]]; then
  echo "  ERROR: Could not get role ID" >&2
  exit 1
fi

# IMPORTANT: The Qovery API requires a permission entry for EVERY cluster
# and EVERY project in the org — not just the target ones. Omitting any
# cluster or project causes the API to reject the request.
#
# Build cluster_permissions: ENV_CREATOR on target cluster, VIEWER on all others
CLUSTER_PERMS=$(api GET "/organization/$ORG_ID/cluster" | jq -c --arg target "$CLUSTER_ID" \
  '[.results[] | {cluster_id: .id, permission: (if .id == $target then "ENV_CREATOR" else "VIEWER" end)}]')

# Build project_permissions: DEPLOYER on builder's project, NO_ACCESS on all others
# NOTE: All 4 environment types (DEVELOPMENT, STAGING, PRODUCTION, PREVIEW) are required
PROJECT_PERMS=$(api GET "/organization/$ORG_ID/project" | jq -c --arg target "$PROJECT_ID" \
  '[.results[] | {
    project_id: .id,
    is_admin: false,
    permissions: (if .id == $target then
      [{environment_type:"DEVELOPMENT",permission:"DEPLOYER"},
       {environment_type:"STAGING",permission:"VIEWER"},
       {environment_type:"PRODUCTION",permission:"NO_ACCESS"},
       {environment_type:"PREVIEW",permission:"DEPLOYER"}]
    else
      [{environment_type:"DEVELOPMENT",permission:"NO_ACCESS"},
       {environment_type:"STAGING",permission:"NO_ACCESS"},
       {environment_type:"PRODUCTION",permission:"NO_ACCESS"},
       {environment_type:"PREVIEW",permission:"NO_ACCESS"}]
    end)
  }]')

# Configure role permissions
api PUT "/organization/$ORG_ID/customRole/$ROLE_ID" \
  -d "{
    \"name\":\"Builder-$NAME\",
    \"cluster_permissions\":$CLUSTER_PERMS,
    \"project_permissions\":$PROJECT_PERMS
  }" > /dev/null
echo "  Role: $ROLE_ID"

# 3. Clone blueprint into the builder's project (or reuse existing)
echo "Step 3: Cloning blueprint..."
CLONE_RESPONSE=$(api POST "/environment/$BLUEPRINT_ENV_ID/clone" \
  -d "{\"name\":\"workspace\",\"cluster_id\":\"$CLUSTER_ID\",\"mode\":\"DEVELOPMENT\",\"project_id\":\"$PROJECT_ID\"}" 2>&1) || {
  if echo "$CLONE_RESPONSE" | grep -qi "409\|already exists\|already used\|Conflict"; then
    echo "  Environment 'workspace' already exists in this project, reusing..."
    ENV_ID=$(api GET "/project/$PROJECT_ID/environment" | jq -r '.results[] | select(.name == "workspace") | .id')
  else
    echo "  ERROR: Clone failed" >&2
    echo "$CLONE_RESPONSE" >&2
    exit 1
  fi
}
ENV_ID="${ENV_ID:-$(echo "$CLONE_RESPONSE" | jq -r '.id')}"
if [[ -z "$ENV_ID" || "$ENV_ID" == "null" ]]; then
  echo "  ERROR: Could not get environment ID" >&2
  exit 1
fi
echo "  Environment: $ENV_ID"

# 4. Update the inherited TTL job to target the cloned environment
# When the blueprint is cloned, the TTL cron job is cloned too — but its
# curl command still points at the blueprint's environment ID. We need to
# update it to stop THIS environment instead.
echo "Step 4: Updating TTL job to target cloned environment..."
TTL_JOB_ID=$(api GET "/environment/$ENV_ID/job" | jq -r '.results[] | select(.name == "ttl-auto-shutdown") | .id')
if [[ -n "$TTL_JOB_ID" && "$TTL_JOB_ID" != "null" ]]; then
  # Build the JSON body — $ENV_ID expands but $SHUTDOWN_TOKEN stays literal
  TTL_BODY=$(cat <<EOF
{
  "name": "ttl-auto-shutdown",
  "description": "Stops environment after 24h to save costs",
  "cpu": 250, "memory": 256,
  "max_nb_restart": 0, "max_duration_seconds": 60,
  "auto_preview": false, "auto_deploy": false, "healthchecks": {},
  "source": {"image": {"image_name": "curlimages/curl", "tag": "8.11.1", "registry_id": "$DOCKER_HUB_REGISTRY_ID"}},
  "schedule": {"cronjob": {
    "entrypoint": "sh",
    "arguments": ["-c", "curl -sf -H 'User-Agent: QoverySkill/qovery-builder-env-ttl' -X POST https://api.qovery.com/environment/$ENV_ID/stop -H \"Authorization: Token \$SHUTDOWN_TOKEN\" || true"],
    "scheduled_at": "0 */24 * * *", "timezone": "Etc/UTC"
  }}
}
EOF
  )
  api PUT "/job/$TTL_JOB_ID" -d "$TTL_BODY" > /dev/null \
    && echo "  TTL job updated: $TTL_JOB_ID" \
    || echo "  WARNING: Could not update TTL job (non-critical)"
else
  echo "  WARNING: No TTL job found in cloned environment (non-critical)"
fi

# 5. Invite builder
echo "Step 5: Inviting $EMAIL..."
api POST "/organization/$ORG_ID/inviteMember" \
  -d "{\"email\":\"$EMAIL\",\"role_id\":\"$ROLE_ID\"}" > /dev/null 2>&1 \
  && echo "  Invited: $EMAIL" \
  || echo "  Already invited or invite failed (non-critical)"

# 6. Deploy
echo "Step 6: Deploying..."
api POST "/environment/$ENV_ID/deploy" > /dev/null \
  && echo "  Deployment triggered" \
  || echo "  WARNING: Deploy request failed — deploy manually from Console" >&2

echo ""
echo "========================================="
echo "Done! Builder: $NAME"
echo "  Project:     $PROJECT_ID"
echo "  Environment: $ENV_ID"
echo "  Role:        $ROLE_ID"
echo "  Console:     https://console.qovery.com/organization/$ORG_ID/project/$PROJECT_ID/environment/$ENV_ID"
echo "  Workspace URL will be available once deployment completes."
echo "========================================="
