## Phase 3: Provision Builders

Each builder gets their own isolated environment cloned from the blueprint. Environments are NEVER shared between builders. The `qovery rde create` command handles everything in one step: project creation, RBAC role, blueprint clone, TTL job update, member invitation, and deployment.

### 3.1 Ask for builders

> "Who are the first builders? Give me names and emails, e.g.:
> alice alice@company.com
> bob bob@company.com"

If the user provides names without emails, ask for emails — they're needed for the Qovery invitation.

### 3.2 Create RDEs

For each builder, run one command:

```bash
qovery rde create \
  -n alice \
  -e alice@company.com \
  -b rde-blueprint \
  -c "{cluster-name}" \
  -o "{org-name}"
```

This single command:
1. Creates project `rde-alice`
2. Creates RBAC role `RDE-alice` with scoped permissions (DEPLOYER on this project only, NO_ACCESS everywhere else)
3. Clones the blueprint environment into the new project
4. Updates the inherited TTL job to target the cloned environment (not the blueprint)
5. Invites alice@company.com with the `RDE-alice` role
6. Triggers deployment

Repeat for each builder. The command is idempotent — safe to run again if something fails.

Optional flags:
- `--skip-rbac` — skip RBAC role creation (if using shared roles)
- `--skip-invite` — skip member invitation
- `--skip-deploy` — skip deployment (deploy manually later)

### 3.3 Verify

List all RDEs:
```bash
qovery rde list -o "{org-name}"
```

Output shows name, blueprint, status, uptime, and workspace URL for each RDE.

For JSON output (useful for scripting):
```bash
qovery rde list -o "{org-name}" --json
```

List workspace URLs only:
```bash
qovery rde urls -o "{org-name}"
```

Check a specific builder:
```bash
qovery rde status -n alice -o "{org-name}"
```

### 3.4 Share workspace URLs

Present the URLs to the platform team:

> **Builder environments are live!**
>
> | Builder | Workspace URL | Status |
> |---------|--------------|--------|
> | alice | https://rde-alice-workspace.{domain} | DEPLOYED |
> | bob | https://rde-bob-workspace.{domain} | DEPLOYED |
>
> Each workspace auto-stops after 24 hours to save costs.
>
> **What builders see:**
> - Open the workspace URL in any browser
> - VS Code loads — familiar, visual interface for non-tech users
> - For AI-powered coding: open the terminal (Ctrl+`) and run `opencode` or `claude`
> - Qovery CLI is pre-installed for deploying apps

### 3.5 Provide the quick reference

Tell the user:

> "Here's the `qovery rde` quick reference for managing builder environments:
> ```bash
> # Create more builders
> qovery rde create -n name -e email -b rde-blueprint -c cluster -o org
>
> # List all
> qovery rde list -o org
>
> # Lifecycle
> qovery rde stop -n alice -o org
> qovery rde start -n alice -o org
> qovery rde stop-all -o org
> qovery rde start-all -o org
>
> # Upgrade after blueprint changes
> qovery rde upgrade -o org -s image        # Redeploy all (fast)
> qovery rde upgrade -o org -s reclone      # Re-clone all (clean slate)
>
> # Delete (full cleanup: env + project + RBAC role + TTL token)
> qovery rde delete -n alice -o org
>
> # Platform overview
> qovery rde info -o org
> ```"

### 3.6 Next steps

> **Your builder environments are ready!**
>
> Optional next steps:
> - **Upgrade all builders** after template changes: `qovery rde upgrade -o org -s image`
> - **Add a visual builder**: see the [customization guide](customization.md) to add a Lovable-like service to the blueprint
> - **Customize TTL, resources, isolation**: see the [customization guide](customization.md)
> - **Terraformize**: run `/qovery-terraform` to convert this setup to Terraform manifests (coming soon)
