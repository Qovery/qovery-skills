#!/usr/bin/env bash
# provision-builder.sh — Provision a new builder environment
# Usage: ./provision-builder.sh <name> <email>
# Example: ./provision-builder.sh alice alice@company.com
#
# Clones the blueprint, creates a per-builder project + RBAC role,
# adds a TTL auto-stop job, invites the builder, and deploys.

set -euo pipefail

NAME="${1:?Usage: $0 <name> <email>}"
EMAIL="${2:?Usage: $0 <name> <email>}"

# --- Fill these in after running the skill (Phase 2) ---
ORG_ID="FILL_IN_ORG_ID"
CLUSTER_ID="FILL_IN_CLUSTER_ID"
BLUEPRINT_ENV_ID="FILL_IN_BLUEPRINT_ENV_ID"
# --------------------------------------------------------

API_TOKEN="${QOVERY_API_TOKEN:?Set QOVERY_API_TOKEN environment variable}"
BASE="https://api.qovery.com"
SKILLS_VERSION=$(cat "$(dirname "$0")/../../_version.txt" 2>/dev/null || echo "unknown")
UA="QoverySkill/qovery-builder-env (version:$SKILLS_VERSION; https://github.com/Qovery/qovery-skills)"

echo "Provisioning builder: $NAME ($EMAIL)"

# 1. Create project
PROJECT_ID=$(curl -sf -X POST "$BASE/organization/$ORG_ID/project" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"builder-$NAME\",\"description\":\"Builder workspace for $NAME\"}" | jq -r '.id')
echo "  Project: $PROJECT_ID"

# 2. Create RBAC role
ROLE_ID=$(curl -sf -X POST "$BASE/organization/$ORG_ID/customRole" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Builder-$NAME\",\"description\":\"Access to builder-$NAME only\"}" | jq -r '.id')

curl -sf -X PUT "$BASE/organization/$ORG_ID/customRole/$ROLE_ID" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\":\"Builder-$NAME\",
    \"cluster_permissions\":[{\"cluster_id\":\"$CLUSTER_ID\",\"permission\":\"ENV_CREATOR\"}],
    \"project_permissions\":[{
      \"project_id\":\"$PROJECT_ID\",\"is_admin\":false,
      \"permissions\":[
        {\"environment_type\":\"DEVELOPMENT\",\"permission\":\"DEPLOYER\"},
        {\"environment_type\":\"STAGING\",\"permission\":\"VIEWER\"},
        {\"environment_type\":\"PRODUCTION\",\"permission\":\"NO_ACCESS\"}
      ]
    }]
  }" > /dev/null
echo "  Role: $ROLE_ID"

# 3. Clone blueprint
ENV_ID=$(curl -sf -X POST "$BASE/environment/$BLUEPRINT_ENV_ID/clone" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"workspace\",\"cluster_id\":\"$CLUSTER_ID\",\"mode\":\"DEVELOPMENT\",\"project_id\":\"$PROJECT_ID\"}" | jq -r '.id')
echo "  Environment: $ENV_ID"

# 4. Create TTL auto-stop job (24h)
SHUTDOWN_TOKEN=$(curl -sf -X POST "$BASE/organization/$ORG_ID/apiToken" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"ttl-$NAME\"}" | jq -r '.token')

JOB_ID=$(curl -sf -X POST "$BASE/environment/$ENV_ID/job" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\":\"ttl-auto-shutdown\",\"cpu\":250,\"memory\":256,
    \"max_nb_restart\":0,\"max_duration_seconds\":60,
    \"auto_preview\":false,\"auto_deploy\":false,\"healthchecks\":{},
    \"source\":{\"docker\":{\"dockerfile_raw\":\"FROM curlimages/curl:8.11.1\nENTRYPOINT [\\\"sh\\\",\\\"-c\\\"]\"}},
    \"schedule\":{\"cronjob\":{
      \"entrypoint\":\"sh\",
      \"arguments\":[\"-c\",\"curl -sf -H 'User-Agent: QoverySkill/qovery-builder-env-ttl' -X POST $BASE/environment/$ENV_ID/stop -H 'Authorization: Token '\\''\$SHUTDOWN_TOKEN'\\'' || true\"],
      \"scheduled_at\":\"0 */24 * * *\",\"timezone\":\"Etc/UTC\"
    }}
  }" | jq -r '.id')

curl -sf -X POST "$BASE/application/$JOB_ID/secret" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"SHUTDOWN_TOKEN\",\"value\":\"$SHUTDOWN_TOKEN\"}" > /dev/null
echo "  TTL job: $JOB_ID"

# 5. Invite builder
curl -sf -X POST "$BASE/organization/$ORG_ID/inviteMember" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"role_id\":\"$ROLE_ID\"}" > /dev/null 2>&1 || true
echo "  Invited: $EMAIL"

# 6. Deploy
curl -sf -X POST "$BASE/environment/$ENV_ID/deploy" \
  -H "Authorization: Token $API_TOKEN" -H "User-Agent: $UA" > /dev/null
echo "  Deployment triggered"

echo ""
echo "Done! Builder: $NAME"
echo "  Project: $PROJECT_ID"
echo "  Environment: $ENV_ID"
echo "  Console: https://console.qovery.com/organization/$ORG_ID/project/$PROJECT_ID/environment/$ENV_ID"
echo "  Workspace URL will be available once deployment completes."
