## Phase 3: Provision Builders

Each builder gets their own isolated environment cloned from the blueprint. Environments are NEVER shared between builders.

### 3.1 Ask for builders

> "Who are the first builders? Give me names and emails, e.g.:
> alice alice@company.com
> bob bob@company.com"

If the user provides names without emails, ask for emails — they're needed for the Qovery invitation.

### 3.2 For each builder, execute these steps

Use the provisioning script at `templates/scripts/provision-builder.sh` or execute the steps manually via the API.

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

# Configure: DEPLOYER on DEV, NO_ACCESS on PRODUCTION
curl -s -X PUT "https://api.qovery.com/organization/{orgId}/customRole/$ROLE_ID" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Builder-{name}",
    "cluster_permissions": [{"cluster_id": "{clusterId}", "permission": "ENV_CREATOR"}],
    "project_permissions": [{
      "project_id": "{builderProjectId}",
      "is_admin": false,
      "permissions": [
        {"environment_type": "DEVELOPMENT", "permission": "DEPLOYER"},
        {"environment_type": "STAGING", "permission": "VIEWER"},
        {"environment_type": "PRODUCTION", "permission": "NO_ACCESS"}
      ]
    }]
  }'
```

**Step 3: Clone the blueprint into this builder's project**

```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "workspace", "cluster_id": "{clusterId}", "mode": "DEVELOPMENT", "project_id": "{builderProjectId}"}'
```

The `project_id` parameter places the cloned environment into the builder's own project (not the blueprint's project).

**Step 4: Create TTL cron job** (same pattern as blueprint Phase 2.6)

Generate a shutdown token, create the cron job, set the token as a secret on the job. Default: 24h auto-stop.

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

### 3.5 Provide provisioning script

Copy `templates/scripts/provision-builder.sh` and fill in the IDs at the top (org, cluster, blueprint env). The script handles all 6 steps above in one command.

Tell the user:
> "I've provided the provisioning script with your IDs filled in. Save it and use it to onboard new builders in the future."

### 3.6 Next steps

> **Your builder environments are ready!**
>
> Optional next steps:
> - **Self-service portal**: say *"Set up a builder portal"* or run `/qovery-builder-portal` to give builders a web UI for creating their own environments
> - **Add a visual builder**: see the [customization guide](customization.md) to add a Lovable-like service to the blueprint
> - **Customize TTL, resources, isolation**: see the [customization guide](customization.md)
> - **Terraformize**: run `/qovery-terraform` to convert this setup to Terraform manifests (coming soon)
