## Phase 3: Provision Builders

Each builder gets their own isolated environment cloned from the blueprint. Environments are NEVER shared between builders.

### 3.1 Ask for builders

> "Who are the first builders? Give me names and emails, e.g.:
> alice alice@company.com
> bob bob@company.com"

If the user provides names without emails, ask for emails — they're needed for the Qovery invitation.

### 3.2 For each builder, execute these steps

Use the builder manager script at `templates/scripts/builder-manager.sh` or execute the steps manually via the API.

```bash
./builder-manager.sh provision alice alice@company.com
```

**Step 1: Create a project for this builder** (project-per-builder isolation)

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-{name}", "description": "Builder workspace for {name}"}'
```

**Step 2: Create a per-builder RBAC role**

```bash
# Create role
ROLE_ID=$(curl -s -X POST "https://api.qovery.com/organization/{orgId}/customRole" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "Builder-{name}", "description": "Access to builder-{name} project only"}' | jq -r '.id')
```

IMPORTANT: The Qovery API requires a permission entry for **EVERY cluster** and **EVERY project** in the organization — not just the target ones. Omitting any cluster or project causes the API to reject the request.

```bash
# Build cluster permissions: ENV_CREATOR on target cluster, VIEWER on all others
CLUSTER_PERMS=$(curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq -c --arg target "{clusterId}" \
  '[.results[] | {cluster_id: .id, permission: (if .id == $target then "ENV_CREATOR" else "VIEWER" end)}]')

# Build project permissions: DEPLOYER on builder's project, NO_ACCESS on all others
# All 4 environment types (DEVELOPMENT, STAGING, PRODUCTION, PREVIEW) are required
PROJECT_PERMS=$(curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/project" | jq -c --arg target "{builderProjectId}" \
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

# Configure role with complete permissions for all clusters and projects
curl -s -X PUT "https://api.qovery.com/organization/{orgId}/customRole/$ROLE_ID" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\":\"Builder-{name}\",
    \"cluster_permissions\":$CLUSTER_PERMS,
    \"project_permissions\":$PROJECT_PERMS
  }"
```

**Step 3: Clone the blueprint into this builder's project**

```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "workspace", "cluster_id": "{clusterId}", "mode": "DEVELOPMENT", "project_id": "{builderProjectId}"}'
```

The `project_id` parameter places the cloned environment into the builder's own project (not the blueprint's project).

**Step 4: Update the inherited TTL job**

When the blueprint is cloned, the TTL cron job is cloned too — but its curl command still points at the **blueprint's** environment ID. Update it to target the **cloned** environment instead:

```bash
# Find the inherited TTL job
TTL_JOB_ID=$(curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{clonedEnvId}/job" | jq -r '.results[] | select(.name == "ttl-auto-shutdown") | .id')

# Update it to target the cloned environment (not the blueprint)
curl -s -X PUT "https://api.qovery.com/job/$TTL_JOB_ID" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-shutdown",
    "description": "Stops environment after 24h to save costs",
    "cpu": 250, "memory": 256,
    "max_nb_restart": 0, "max_duration_seconds": 60,
    "auto_preview": false, "auto_deploy": false, "healthchecks": {},
    "source": {"image": {"image_name": "curlimages/curl", "tag": "8.11.1", "registry_id": "{DOCKER_HUB_REGISTRY_ID}"}},
    "schedule": {"cronjob": {
      "entrypoint": "sh",
      "arguments": ["-c", "curl -sf -H '\''User-Agent: QoverySkill/qovery-builder-env-ttl'\'' -X POST https://api.qovery.com/environment/{clonedEnvId}/stop -H \"Authorization: Token $SHUTDOWN_TOKEN\" || true"],
      "scheduled_at": "0 */24 * * *", "timezone": "Etc/UTC"
    }}
  }'
```

The `SHUTDOWN_TOKEN` secret is inherited from the blueprint — no need to create a new one.

**Step 5: Invite the builder**

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/inviteMember" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"email": "{builder-email}", "role_id": "{builderRoleId}"}'
```

**Step 6: Deploy**

```bash
curl -s -X POST "https://api.qovery.com/environment/{clonedEnvId}/deploy" \
  -H "Authorization: Bearer $(qovery auth token --print)"
```

### 3.3 Watch deployments and collect URLs

Poll statuses for each builder environment. When deployed, collect workspace URLs:

```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{workspaceAppId}/link" | jq '.results[0].url'
```

### 3.4 Present results

> **Builder environments are live!**
>
> | Builder | Workspace URL | Status |
> |---------|--------------|--------|
> | alice | https://builder-alice-workspace.{domain} | DEPLOYED |
> | bob | https://builder-bob-workspace.{domain} | DEPLOYED |
>
> Each workspace auto-stops after 24 hours to save costs.
>
> **What builders see:**
> - Open the workspace URL in any browser
> - VS Code loads — familiar, visual interface for non-tech users
> - For AI-powered coding: open the terminal (Ctrl+`) and run `opencode` or `claude`
> - Qovery CLI is pre-installed for deploying apps: `qovery deploy`
>
> **To add more builders later:**
> ```bash
> ./provision-builder.sh <name> <email>
> ```

### 3.5 Provide the builder manager script

Copy `templates/scripts/builder-manager.sh` and fill in the IDs at the top (ORG_ID, CLUSTER_ID, BLUEPRINT_ENV_ID, DOCKER_HUB_REGISTRY_ID). The script handles provisioning plus all lifecycle operations (list, stop, start, delete, upgrade).

Tell the user:
> "I've provided the builder-manager.sh script with your IDs filled in. Use it to manage builder environments:
> ```bash
> ./builder-manager.sh provision <name> <email>   # Add a builder
> ./builder-manager.sh list                        # See all builders
> ./builder-manager.sh stop-all                    # Stop all (end of day)
> ./builder-manager.sh start-all                   # Start all (morning)
> ./builder-manager.sh upgrade --strategy image    # Apply template changes
> ./builder-manager.sh delete <name>               # Full cleanup
> ./builder-manager.sh blueprint deploy            # Validate blueprint changes
> ./builder-manager.sh info                        # Platform overview
> ```"

### 3.6 Next steps

> **Your builder environments are ready!**
>
> Optional next steps:
> - **Self-service portal**: say *"Set up a builder portal"* or run `/qovery-builder-portal` to give builders a web UI for creating their own environments
> - **Upgrade all builders** after template changes: `./builder-manager.sh upgrade --strategy image` (redeploy) or `--strategy reclone` (full re-clone)
> - **Add a visual builder**: see the [customization guide](customization.md) to add a Lovable-like service to the blueprint
> - **Customize TTL, resources, isolation**: see the [customization guide](customization.md)
> - **Terraformize**: run `/qovery-terraform` to convert this setup to Terraform manifests (coming soon)
