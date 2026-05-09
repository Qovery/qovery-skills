#!/usr/bin/env bash
# builder-manager.sh — Unified management for builder environments
#
# Usage: ./builder-manager.sh <command> [options]
#
# Builder Operations:
#   provision <name> <email>      Create a new builder environment
#   provision-bulk <csv>          Provision multiple builders from CSV (name,email)
#   list [--json]                 List all builder environments (status, uptime, URLs)
#   status <name>                 Detailed status of one builder
#   stop <name>                   Stop a builder's environment
#   stop-all                      Stop ALL builder environments
#   start <name>                  Start (deploy) a stopped environment
#   start-all                     Start ALL builder environments
#   delete <name>                 Delete environment + project + role + token
#   delete-all --confirm          Delete ALL builder environments
#   upgrade [name] [--strategy S] Upgrade from updated blueprint (S: reclone|image)
#   urls                          List workspace URLs for running builders
#   logs <name>                   Stream workspace logs
#
# Blueprint Operations:
#   blueprint deploy              Deploy the blueprint for validation
#   blueprint stop                Stop the blueprint
#   blueprint status              Show blueprint status
#
# Platform Info:
#   info                          Platform overview (org, cluster, counts)
#   help                          Show this message

set -euo pipefail

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

# ── API helper ───────────────────────────────────────────────────────────────
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

# ── Helpers ──────────────────────────────────────────────────────────────────

# Find a builder's project ID by name
find_project_id() {
  local name="$1"
  api GET "/organization/$ORG_ID/project" | jq -r ".results[] | select(.name == \"builder-$name\") | .id"
}

# Find a builder's environment ID (first env in their project)
find_env_id() {
  local project_id="$1"
  api GET "/project/$project_id/environment" | jq -r '.results[0].id'
}

# Get environment status
get_env_status() {
  local env_id="$1"
  api GET "/environment/$env_id/statuses" 2>/dev/null | jq -r '.environment.state' 2>/dev/null || echo "UNKNOWN"
}

# Get workspace URL for an environment
get_workspace_url() {
  local env_id="$1"
  local app_id
  app_id=$(api GET "/environment/$env_id/application" 2>/dev/null | jq -r '.results[0].id' 2>/dev/null || echo "")
  if [[ -n "$app_id" && "$app_id" != "null" ]]; then
    api GET "/application/$app_id/link" 2>/dev/null | jq -r '.results[0].url // empty' 2>/dev/null || echo ""
  fi
}

# Get last deployment timestamp for an environment
get_last_deploy() {
  local env_id="$1"
  api GET "/environment/$env_id/deploymentHistory?version=v2" 2>/dev/null \
    | jq -r '.results[0].created_at // empty' 2>/dev/null || echo ""
}

# Format uptime from a deployment timestamp to human-readable
format_uptime() {
  local timestamp="$1"
  if [[ -z "$timestamp" ]]; then echo "—"; return; fi
  local now deploy_epoch diff
  now=$(date +%s)
  deploy_epoch=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%%.*}" +%s 2>/dev/null || echo "0")
  if [[ "$deploy_epoch" == "0" ]]; then echo "—"; return; fi
  diff=$((now - deploy_epoch))
  if [[ $diff -lt 60 ]]; then echo "${diff}s"
  elif [[ $diff -lt 3600 ]]; then echo "$((diff / 60))m"
  elif [[ $diff -lt 86400 ]]; then echo "$((diff / 3600))h $((diff % 3600 / 60))m"
  else echo "$((diff / 86400))d $((diff % 86400 / 3600))h"
  fi
}

# List all builder-* projects (returns JSON array of {id, name})
list_builder_projects() {
  api GET "/organization/$ORG_ID/project" | jq -c '[.results[] | select(.name | startswith("builder-")) | select(.name != "builder-blueprints" and .name != "builder-workspaces" and .name != "builder-blueprint") | {id, name}]'
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  exit 0
}

# ── Subcommand: provision ────────────────────────────────────────────────────
cmd_provision() {
  local name="${1:?Usage: builder-manager.sh provision <name> <email>}"
  local email="${2:?Usage: builder-manager.sh provision <name> <email>}"

  echo "Provisioning builder: $name ($email)"
  echo ""

  # 1. Create project (or reuse)
  echo "Step 1: Creating project builder-$name..."
  local project_response project_id
  project_response=$(api POST "/organization/$ORG_ID/project" \
    -d "{\"name\":\"builder-$name\",\"description\":\"Builder workspace for $name\"}" 2>&1) || {
    if echo "$project_response" | grep -qi "409\|already exists\|already used\|Conflict"; then
      echo "  Project already exists, reusing..."
      project_id=$(find_project_id "$name")
    else
      echo "  Failed to create project:" >&2; echo "$project_response" >&2; exit 1
    fi
  }
  project_id="${project_id:-$(echo "$project_response" | jq -r '.id')}"
  [[ -z "$project_id" || "$project_id" == "null" ]] && { echo "ERROR: Could not get project ID" >&2; exit 1; }
  echo "  Project: $project_id"

  # 2. Create RBAC role (or reuse)
  echo "Step 2: Creating RBAC role Builder-$name..."
  local role_response role_id
  role_response=$(api POST "/organization/$ORG_ID/customRole" \
    -d "{\"name\":\"Builder-$name\",\"description\":\"Access to builder-$name only\"}" 2>&1) || {
    if echo "$role_response" | grep -qi "409\|already exists\|already used\|Conflict"; then
      echo "  Role already exists, reusing..."
      role_id=$(api GET "/organization/$ORG_ID/customRole" | jq -r ".results[] | select(.name == \"Builder-$name\") | .id")
    else
      echo "  Failed to create role:" >&2; echo "$role_response" >&2; exit 1
    fi
  }
  role_id="${role_id:-$(echo "$role_response" | jq -r '.id')}"
  [[ -z "$role_id" || "$role_id" == "null" ]] && { echo "ERROR: Could not get role ID" >&2; exit 1; }

  # RBAC: permissions for ALL clusters and ALL projects (Qovery API requirement)
  local cluster_perms project_perms
  cluster_perms=$(api GET "/organization/$ORG_ID/cluster" | jq -c --arg target "$CLUSTER_ID" \
    '[.results[] | {cluster_id: .id, permission: (if .id == $target then "ENV_CREATOR" else "VIEWER" end)}]')
  project_perms=$(api GET "/organization/$ORG_ID/project" | jq -c --arg target "$project_id" \
    '[.results[] | {
      project_id: .id, is_admin: false,
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

  api PUT "/organization/$ORG_ID/customRole/$role_id" \
    -d "{\"name\":\"Builder-$name\",\"cluster_permissions\":$cluster_perms,\"project_permissions\":$project_perms}" > /dev/null
  echo "  Role: $role_id"

  # 3. Clone blueprint (or reuse existing env)
  echo "Step 3: Cloning blueprint..."
  local clone_response env_id
  clone_response=$(api POST "/environment/$BLUEPRINT_ENV_ID/clone" \
    -d "{\"name\":\"workspace\",\"cluster_id\":\"$CLUSTER_ID\",\"mode\":\"DEVELOPMENT\",\"project_id\":\"$project_id\"}" 2>&1) || {
    if echo "$clone_response" | grep -qi "409\|already exists\|already used\|Conflict"; then
      echo "  Environment already exists, reusing..."
      env_id=$(find_env_id "$project_id")
    else
      echo "  Clone failed:" >&2; echo "$clone_response" >&2; exit 1
    fi
  }
  env_id="${env_id:-$(echo "$clone_response" | jq -r '.id')}"
  [[ -z "$env_id" || "$env_id" == "null" ]] && { echo "ERROR: Could not get environment ID" >&2; exit 1; }
  echo "  Environment: $env_id"

  # 4. Update inherited TTL job to target the cloned environment
  echo "Step 4: Updating TTL job..."
  local ttl_job_id
  ttl_job_id=$(api GET "/environment/$env_id/job" | jq -r '.results[] | select(.name == "ttl-auto-shutdown") | .id')
  if [[ -n "$ttl_job_id" && "$ttl_job_id" != "null" ]]; then
    local ttl_body
    ttl_body=$(cat <<EOF
{
  "name": "ttl-auto-shutdown",
  "description": "Stops environment after 24h to save costs",
  "cpu": 250, "memory": 256,
  "max_nb_restart": 0, "max_duration_seconds": 60,
  "auto_preview": false, "auto_deploy": false, "healthchecks": {},
  "source": {"image": {"image_name": "curlimages/curl", "tag": "8.11.1", "registry_id": "$DOCKER_HUB_REGISTRY_ID"}},
  "schedule": {"cronjob": {
    "entrypoint": "sh",
    "arguments": ["-c", "curl -sf -H 'User-Agent: QoverySkill/qovery-builder-env-ttl' -X POST https://api.qovery.com/environment/$env_id/stop -H \"Authorization: Token \$SHUTDOWN_TOKEN\" || true"],
    "scheduled_at": "0 */24 * * *", "timezone": "Etc/UTC"
  }}
}
EOF
    )
    api PUT "/job/$ttl_job_id" -d "$ttl_body" > /dev/null \
      && echo "  TTL job updated: $ttl_job_id" \
      || echo "  WARNING: Could not update TTL job (non-critical)"
  else
    echo "  WARNING: No TTL job found (non-critical)"
  fi

  # 5. Invite builder
  echo "Step 5: Inviting $email..."
  api POST "/organization/$ORG_ID/inviteMember" \
    -d "{\"email\":\"$email\",\"role_id\":\"$role_id\"}" > /dev/null 2>&1 \
    && echo "  Invited: $email" \
    || echo "  Already invited or failed (non-critical)"

  # 6. Deploy
  echo "Step 6: Deploying..."
  api POST "/environment/$env_id/deploy" > /dev/null \
    && echo "  Deployment triggered" \
    || echo "  WARNING: Deploy failed — deploy from Console" >&2

  echo ""
  echo "Done! Builder: $name"
  echo "  Project:     $project_id"
  echo "  Environment: $env_id"
  echo "  Console:     https://console.qovery.com/organization/$ORG_ID/project/$project_id/environment/$env_id"
  echo "  Workspace URL available once deployment completes."
}

# ── Subcommand: provision-bulk ───────────────────────────────────────────────
cmd_provision_bulk() {
  local csv="${1:?Usage: builder-manager.sh provision-bulk <builders.csv>}"
  local count=0
  while IFS=, read -r name email; do
    [[ "$name" == "name" ]] && continue
    [[ -z "$name" ]] && continue
    count=$((count + 1))
    echo "=== Builder $count: $name ==="
    cmd_provision "$name" "$email"
    echo ""
  done < "$csv"
  echo "Bulk provisioning complete: $count builders."
}

# ── Subcommand: list ─────────────────────────────────────────────────────────
cmd_list() {
  local json_mode=false
  [[ "${1:-}" == "--json" ]] && json_mode=true

  local projects
  projects=$(list_builder_projects)
  local count
  count=$(echo "$projects" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    echo "No builder environments found."
    return
  fi

  local results="[]"
  local running=0 stopped=0 errors=0

  for row in $(echo "$projects" | jq -r '.[] | @base64'); do
    local proj_id proj_name builder_name env_id status url last_deploy uptime
    proj_id=$(echo "$row" | base64 -d | jq -r '.id')
    proj_name=$(echo "$row" | base64 -d | jq -r '.name')
    builder_name="${proj_name#builder-}"

    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")
    if [[ -z "$env_id" || "$env_id" == "null" ]]; then
      status="NO_ENV"; url=""; uptime="—"
    else
      status=$(get_env_status "$env_id")
      if [[ "$status" == "DEPLOYED" ]]; then
        url=$(get_workspace_url "$env_id" || echo "")
        last_deploy=$(get_last_deploy "$env_id" || echo "")
        uptime=$(format_uptime "$last_deploy")
        running=$((running + 1))
      elif [[ "$status" == "STOPPED" ]]; then
        url=""; uptime="—"
        stopped=$((stopped + 1))
      else
        url=""; uptime="—"
        errors=$((errors + 1))
      fi
    fi

    results=$(echo "$results" | jq --arg n "$builder_name" --arg s "$status" --arg u "${url:-}" --arg up "$uptime" \
      '. + [{"name": $n, "status": $s, "url": $u, "uptime": $up}]')
  done

  if $json_mode; then
    echo "$results" | jq '.'
  else
    printf "%-15s %-12s %-10s %s\n" "NAME" "STATUS" "UPTIME" "WORKSPACE URL"
    echo "$results" | jq -r '.[] | "\(.name)\t\(.status)\t\(.uptime)\t\(.url // "—")"' \
      | while IFS=$'\t' read -r n s up u; do
          printf "%-15s %-12s %-10s %s\n" "$n" "$s" "$up" "${u:-—}"
        done
    echo ""
    echo "Total: $count builders ($running running, $stopped stopped, $errors error/other)"
    echo ""
    echo "For cost analysis, run: /qovery-optimize"
  fi
}

# ── Subcommand: status ───────────────────────────────────────────────────────
cmd_status() {
  local name="${1:?Usage: builder-manager.sh status <name>}"
  local proj_id env_id

  proj_id=$(find_project_id "$name")
  [[ -z "$proj_id" || "$proj_id" == "null" ]] && { echo "Builder '$name' not found."; exit 1; }
  env_id=$(find_env_id "$proj_id")

  echo "Builder: $name"
  echo "  Project:     $proj_id"
  echo "  Environment: $env_id"
  echo "  Status:      $(get_env_status "$env_id")"

  local url
  url=$(get_workspace_url "$env_id" || echo "")
  [[ -n "$url" ]] && echo "  Workspace:   $url"

  local last_deploy uptime
  last_deploy=$(get_last_deploy "$env_id" || echo "")
  uptime=$(format_uptime "$last_deploy")
  echo "  Uptime:      $uptime"
  echo "  Console:     https://console.qovery.com/organization/$ORG_ID/project/$proj_id/environment/$env_id"

  echo ""
  echo "  Services:"
  api GET "/environment/$env_id/statuses" 2>/dev/null | jq -r '
    [(.applications // [])[] | "    \(.name) (\(.state))"],
    [(.jobs // [])[] | "    \(.name) (\(.state))"],
    [(.databases // [])[] | "    \(.name) (\(.state))"] | .[]' 2>/dev/null || echo "    (could not retrieve)"
}

# ── Subcommand: stop / start ────────────────────────────────────────────────
cmd_stop() {
  local name="${1:?Usage: builder-manager.sh stop <name>}"
  local proj_id env_id
  proj_id=$(find_project_id "$name")
  [[ -z "$proj_id" || "$proj_id" == "null" ]] && { echo "Builder '$name' not found."; exit 1; }
  env_id=$(find_env_id "$proj_id")
  echo "Stopping builder $name..."
  api POST "/environment/$env_id/stop" > /dev/null && echo "  Stop triggered." || echo "  Stop failed."
}

cmd_start() {
  local name="${1:?Usage: builder-manager.sh start <name>}"
  local proj_id env_id
  proj_id=$(find_project_id "$name")
  [[ -z "$proj_id" || "$proj_id" == "null" ]] && { echo "Builder '$name' not found."; exit 1; }
  env_id=$(find_env_id "$proj_id")
  echo "Starting builder $name..."
  api POST "/environment/$env_id/deploy" > /dev/null && echo "  Deploy triggered." || echo "  Deploy failed."
}

# ── Subcommand: stop-all / start-all ────────────────────────────────────────
cmd_stop_all() {
  echo "Stopping all builder environments..."
  local projects
  projects=$(list_builder_projects)
  for row in $(echo "$projects" | jq -r '.[] | @base64'); do
    local proj_id proj_name builder_name env_id
    proj_id=$(echo "$row" | base64 -d | jq -r '.id')
    proj_name=$(echo "$row" | base64 -d | jq -r '.name')
    builder_name="${proj_name#builder-}"
    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")
    if [[ -n "$env_id" && "$env_id" != "null" ]]; then
      api POST "/environment/$env_id/stop" > /dev/null 2>&1 \
        && echo "  Stopped: $builder_name" \
        || echo "  Failed to stop: $builder_name"
    fi
  done
  echo "Done."
}

cmd_start_all() {
  echo "Starting all builder environments..."
  local projects
  projects=$(list_builder_projects)
  for row in $(echo "$projects" | jq -r '.[] | @base64'); do
    local proj_id proj_name builder_name env_id
    proj_id=$(echo "$row" | base64 -d | jq -r '.id')
    proj_name=$(echo "$row" | base64 -d | jq -r '.name')
    builder_name="${proj_name#builder-}"
    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")
    if [[ -n "$env_id" && "$env_id" != "null" ]]; then
      api POST "/environment/$env_id/deploy" > /dev/null 2>&1 \
        && echo "  Started: $builder_name" \
        || echo "  Failed to start: $builder_name"
    fi
  done
  echo "Done."
}

# ── Subcommand: delete ───────────────────────────────────────────────────────
cmd_delete() {
  local name="${1:?Usage: builder-manager.sh delete <name>}"
  local proj_id env_id role_id token_id

  echo "Deleting builder: $name"

  proj_id=$(find_project_id "$name")
  if [[ -z "$proj_id" || "$proj_id" == "null" ]]; then
    echo "  Builder '$name' not found (no project). Checking for orphaned role/token..."
  else
    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")
    if [[ -n "$env_id" && "$env_id" != "null" ]]; then
      echo "  Stopping environment..."
      api POST "/environment/$env_id/stop" > /dev/null 2>&1 || true
      sleep 2
      echo "  Deleting environment..."
      api DELETE "/environment/$env_id" > /dev/null 2>&1 || true
    fi
    echo "  Deleting project builder-$name..."
    api DELETE "/project/$proj_id" > /dev/null 2>&1 || true
  fi

  # Delete RBAC role
  role_id=$(api GET "/organization/$ORG_ID/customRole" 2>/dev/null \
    | jq -r ".results[] | select(.name == \"Builder-$name\") | .id" 2>/dev/null || echo "")
  if [[ -n "$role_id" && "$role_id" != "null" ]]; then
    echo "  Deleting role Builder-$name..."
    api DELETE "/organization/$ORG_ID/customRole/$role_id" > /dev/null 2>&1 || true
  fi

  # Delete TTL API token
  token_id=$(api GET "/organization/$ORG_ID/apiToken" 2>/dev/null \
    | jq -r ".results[] | select(.name == \"ttl-$name\") | .id" 2>/dev/null || echo "")
  if [[ -n "$token_id" && "$token_id" != "null" ]]; then
    echo "  Deleting TTL token ttl-$name..."
    api DELETE "/organization/$ORG_ID/apiToken/$token_id" > /dev/null 2>&1 || true
  fi

  echo ""
  echo "Builder $name fully removed."
}

# ── Subcommand: delete-all ───────────────────────────────────────────────────
cmd_delete_all() {
  if [[ "${1:-}" != "--confirm" ]]; then
    echo "ERROR: This will delete ALL builder environments permanently."
    echo "Run with --confirm to proceed: builder-manager.sh delete-all --confirm"
    exit 1
  fi

  echo "Deleting ALL builder environments..."
  echo ""
  local projects
  projects=$(list_builder_projects)
  for row in $(echo "$projects" | jq -r '.[] | @base64'); do
    local proj_name builder_name
    proj_name=$(echo "$row" | base64 -d | jq -r '.name')
    builder_name="${proj_name#builder-}"
    cmd_delete "$builder_name"
    echo ""
  done
  echo "All builder environments deleted."
}

# ── Subcommand: upgrade ─────────────────────────────────────────────────────
cmd_upgrade() {
  local target_name=""
  local strategy="reclone"

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strategy) strategy="$2"; shift 2 ;;
      *) target_name="$1"; shift ;;
    esac
  done

  if [[ "$strategy" != "reclone" && "$strategy" != "image" ]]; then
    echo "ERROR: Unknown strategy '$strategy'. Use 'reclone' or 'image'."
    exit 1
  fi

  upgrade_one() {
    local name="$1"
    local proj_id env_id
    proj_id=$(find_project_id "$name")
    [[ -z "$proj_id" || "$proj_id" == "null" ]] && { echo "  Builder '$name' not found."; return 1; }
    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")

    if [[ "$strategy" == "image" ]]; then
      # Image-only: just redeploy (re-pulls/rebuilds the image)
      echo "  Upgrading $name (strategy: image — redeploy only)..."
      api POST "/environment/$env_id/deploy" > /dev/null 2>&1 \
        && echo "  Deploy triggered for $name." \
        || echo "  WARNING: Deploy failed for $name."
    else
      # Reclone: delete env, re-clone from blueprint, update TTL, redeploy
      echo "  Upgrading $name (strategy: reclone — full re-clone from blueprint)..."
      echo "    WARNING: Uncommitted changes will be lost. Code in git is safe."

      # Stop and delete the current environment
      api POST "/environment/$env_id/stop" > /dev/null 2>&1 || true
      sleep 2
      api DELETE "/environment/$env_id" > /dev/null 2>&1 || true
      sleep 2

      # Re-clone from blueprint
      local new_env_id
      new_env_id=$(api POST "/environment/$BLUEPRINT_ENV_ID/clone" \
        -d "{\"name\":\"workspace\",\"cluster_id\":\"$CLUSTER_ID\",\"mode\":\"DEVELOPMENT\",\"project_id\":\"$proj_id\"}" \
        | jq -r '.id')

      if [[ -z "$new_env_id" || "$new_env_id" == "null" ]]; then
        echo "    ERROR: Re-clone failed for $name."
        return 1
      fi

      # Update TTL job to target new env
      local ttl_job_id
      ttl_job_id=$(api GET "/environment/$new_env_id/job" 2>/dev/null \
        | jq -r '.results[] | select(.name == "ttl-auto-shutdown") | .id' 2>/dev/null || echo "")
      if [[ -n "$ttl_job_id" && "$ttl_job_id" != "null" ]]; then
        local ttl_body
        ttl_body=$(cat <<EOF
{
  "name": "ttl-auto-shutdown",
  "description": "Stops environment after 24h to save costs",
  "cpu": 250, "memory": 256,
  "max_nb_restart": 0, "max_duration_seconds": 60,
  "auto_preview": false, "auto_deploy": false, "healthchecks": {},
  "source": {"image": {"image_name": "curlimages/curl", "tag": "8.11.1", "registry_id": "$DOCKER_HUB_REGISTRY_ID"}},
  "schedule": {"cronjob": {
    "entrypoint": "sh",
    "arguments": ["-c", "curl -sf -H 'User-Agent: QoverySkill/qovery-builder-env-ttl' -X POST https://api.qovery.com/environment/$new_env_id/stop -H \"Authorization: Token \$SHUTDOWN_TOKEN\" || true"],
    "scheduled_at": "0 */24 * * *", "timezone": "Etc/UTC"
  }}
}
EOF
        )
        api PUT "/job/$ttl_job_id" -d "$ttl_body" > /dev/null 2>&1 || true
      fi

      # Deploy
      api POST "/environment/$new_env_id/deploy" > /dev/null 2>&1 \
        && echo "    Re-cloned and deploying: $new_env_id" \
        || echo "    WARNING: Deploy failed after re-clone."
    fi
  }

  if [[ -n "$target_name" ]]; then
    upgrade_one "$target_name"
  else
    echo "Upgrading ALL builder environments (strategy: $strategy)..."
    local projects
    projects=$(list_builder_projects)
    for row in $(echo "$projects" | jq -r '.[] | @base64'); do
      local proj_name builder_name
      proj_name=$(echo "$row" | base64 -d | jq -r '.name')
      builder_name="${proj_name#builder-}"
      upgrade_one "$builder_name"
    done
    echo ""
    echo "All builders upgraded."
  fi
}

# ── Subcommand: urls ─────────────────────────────────────────────────────────
cmd_urls() {
  local projects
  projects=$(list_builder_projects)
  printf "%-15s %s\n" "NAME" "WORKSPACE URL"
  for row in $(echo "$projects" | jq -r '.[] | @base64'); do
    local proj_id proj_name builder_name env_id status url
    proj_id=$(echo "$row" | base64 -d | jq -r '.id')
    proj_name=$(echo "$row" | base64 -d | jq -r '.name')
    builder_name="${proj_name#builder-}"
    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")
    if [[ -n "$env_id" && "$env_id" != "null" ]]; then
      status=$(get_env_status "$env_id")
      if [[ "$status" == "DEPLOYED" ]]; then
        url=$(get_workspace_url "$env_id" || echo "—")
        printf "%-15s %s\n" "$builder_name" "${url:-—}"
      fi
    fi
  done
}

# ── Subcommand: logs ─────────────────────────────────────────────────────────
cmd_logs() {
  local name="${1:?Usage: builder-manager.sh logs <name>}"
  local proj_id env_id app_id
  proj_id=$(find_project_id "$name")
  [[ -z "$proj_id" || "$proj_id" == "null" ]] && { echo "Builder '$name' not found."; exit 1; }
  env_id=$(find_env_id "$proj_id")
  app_id=$(api GET "/environment/$env_id/application" | jq -r '.results[0].id')

  echo "Fetching logs for builder $name (workspace)..."
  api GET "/application/$app_id/log" | jq -r '.results[-50:] | .[] | .message // empty'
}

# ── Subcommand: blueprint ───────────────────────────────────────────────────
cmd_blueprint() {
  local subcmd="${1:?Usage: builder-manager.sh blueprint <deploy|stop|status>}"

  case "$subcmd" in
    deploy)
      echo "Deploying blueprint for validation..."
      api POST "/environment/$BLUEPRINT_ENV_ID/deploy" > /dev/null \
        && echo "Blueprint deployment triggered." \
        || echo "Blueprint deployment failed."
      ;;
    stop)
      echo "Stopping blueprint..."
      api POST "/environment/$BLUEPRINT_ENV_ID/stop" > /dev/null \
        && echo "Blueprint stopped." \
        || echo "Blueprint stop failed."
      ;;
    status)
      echo "Blueprint: $BLUEPRINT_ENV_ID"
      local status
      status=$(get_env_status "$BLUEPRINT_ENV_ID")
      echo "  Status: $status"
      echo "  Services:"
      api GET "/environment/$BLUEPRINT_ENV_ID/statuses" 2>/dev/null | jq -r '
        [(.applications // [])[] | "    \(.name) (\(.state))"],
        [(.jobs // [])[] | "    \(.name) (\(.state))"],
        [(.databases // [])[] | "    \(.name) (\(.state))"] | .[]' 2>/dev/null || echo "    (could not retrieve)"
      ;;
    *)
      echo "Unknown blueprint command: $subcmd"
      echo "Usage: builder-manager.sh blueprint <deploy|stop|status>"
      exit 1
      ;;
  esac
}

# ── Subcommand: info ─────────────────────────────────────────────────────────
cmd_info() {
  local org_name cluster_name cluster_status blueprint_status
  org_name=$(api GET "/organization" | jq -r ".results[] | select(.id == \"$ORG_ID\") | .name" 2>/dev/null || echo "unknown")
  cluster_name=$(api GET "/organization/$ORG_ID/cluster" | jq -r ".results[] | select(.id == \"$CLUSTER_ID\") | .name" 2>/dev/null || echo "unknown")
  cluster_status=$(api GET "/organization/$ORG_ID/cluster" | jq -r ".results[] | select(.id == \"$CLUSTER_ID\") | .status" 2>/dev/null || echo "unknown")
  blueprint_status=$(get_env_status "$BLUEPRINT_ENV_ID")

  local projects running=0 stopped=0 errors=0
  projects=$(list_builder_projects)
  local total
  total=$(echo "$projects" | jq 'length')

  for row in $(echo "$projects" | jq -r '.[] | @base64'); do
    local proj_id env_id status
    proj_id=$(echo "$row" | base64 -d | jq -r '.id')
    env_id=$(find_env_id "$proj_id" 2>/dev/null || echo "")
    if [[ -n "$env_id" && "$env_id" != "null" ]]; then
      status=$(get_env_status "$env_id")
      case "$status" in
        DEPLOYED) running=$((running + 1)) ;;
        STOPPED)  stopped=$((stopped + 1)) ;;
        *)        errors=$((errors + 1)) ;;
      esac
    fi
  done

  echo ""
  echo "Builder Environment Platform"
  echo "  Organization:  $org_name ($ORG_ID)"
  echo "  Cluster:       $cluster_name ($cluster_status)"
  echo "  Blueprint:     $BLUEPRINT_ENV_ID ($blueprint_status)"
  echo ""
  echo "  Builders:      $total total"
  echo "    Running:     $running"
  echo "    Stopped:     $stopped"
  echo "    Error/Other: $errors"
  echo ""
  echo "  Config:"
  echo "    ORG_ID:              $ORG_ID"
  echo "    CLUSTER_ID:          $CLUSTER_ID"
  echo "    BLUEPRINT_ENV_ID:    $BLUEPRINT_ENV_ID"
  echo "    DOCKER_HUB_REG_ID:  $DOCKER_HUB_REGISTRY_ID"
  echo ""
}

# ── Main dispatcher ──────────────────────────────────────────────────────────
case "${1:-help}" in
  provision)      shift; cmd_provision "$@" ;;
  provision-bulk) shift; cmd_provision_bulk "$@" ;;
  list)           shift; cmd_list "$@" ;;
  status)         shift; cmd_status "$@" ;;
  stop)           shift; cmd_stop "$@" ;;
  stop-all)       shift; cmd_stop_all ;;
  start)          shift; cmd_start "$@" ;;
  start-all)      shift; cmd_start_all ;;
  delete)         shift; cmd_delete "$@" ;;
  delete-all)     shift; cmd_delete_all "$@" ;;
  upgrade)        shift; cmd_upgrade "$@" ;;
  urls)           shift; cmd_urls ;;
  logs)           shift; cmd_logs "$@" ;;
  blueprint)      shift; cmd_blueprint "$@" ;;
  info)           shift; cmd_info ;;
  help|--help|-h) usage ;;
  *)              echo "Unknown command: $1"; echo "Run '$0 help' for usage."; exit 1 ;;
esac
