## Phase 3: Provision Builders

Each builder gets their own isolated environment cloned from the blueprint. Environments are NEVER shared between builders. The `qovery rde create` command handles everything in one step: project creation, RBAC role, blueprint clone, TTL job update, member invitation, and deployment.

### 3.1 Ask for builders

> "Who are the first builders? Give me names and emails, e.g.:
> alice alice@company.com
> bob bob@company.com"

If the user provides names without emails, ask for emails — they're needed for the Qovery invitation.

### 3.2 Ask about git repository

Ask the user:

> "Will these builders work on an **existing git repository**, or start with an **empty project**?"

**If a git repo is involved**, gather the details:

> "I'll configure each workspace to auto-clone the repo on startup. I need a few details:
> 1. **Git repo URL** (HTTPS) — e.g. `https://github.com/org/project.git`
> 2. **Is the repo private?** If yes, I'll need a git personal access token (stored as a Qovery secret — builders never see it)
> 3. **Branch** to use (default: `main`)
> 4. **Should builders be able to commit?** If yes, what **name** and **email** should git use for their commits?"

Store the answers — they'll be set as environment variables after each `qovery rde create` in step 3.3.

| User answer | Variable | Secret? |
|---|---|---|
| Git repo URL | `GIT_REPO_URL` | No |
| Access token (private repo) | `GIT_TOKEN` | Yes |
| Branch | `GIT_BRANCH` | No |
| Git author name | `GIT_USER_NAME` | No |
| Git author email | `GIT_USER_EMAIL` | No |

The workspace [entrypoint.sh](https://github.com/evoxmusic/remote-dev-env-template/blob/main/entrypoint.sh) reads these at startup. It auto-detects the git provider from the URL (GitHub/GitLab/Bitbucket) and configures credentials accordingly. It also auto-installs dependencies (`npm install` / `pip install`) and auto-starts the dev server if detected.

**If starting with an empty project**, skip this step — no env vars needed. The workspace will start with an empty directory.

### 3.3 Create RDEs

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

**If a git repo was configured in step 3.2**, set the environment variables on each builder's environment after creation. First, get the environment ID from the `qovery rde create` output or via `qovery rde list -o org --json`. Then set the variables:

```bash
# Get the environment ID for the builder
ENV_ID=$(qovery rde list -o "{org-name}" --json | jq -r '.[] | select(.name == "alice") | .environment_id')

# Set git repo URL (not a secret)
curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/environmentVariable" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"key": "GIT_REPO_URL", "value": "https://github.com/org/project.git", "scope": "ENVIRONMENT", "is_secret": false}'

# Set git token (secret — if repo is private)
curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/environmentVariable" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"key": "GIT_TOKEN", "value": "{token}", "scope": "ENVIRONMENT", "is_secret": true}'

# Set branch (if not main)
curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/environmentVariable" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"key": "GIT_BRANCH", "value": "develop", "scope": "ENVIRONMENT", "is_secret": false}'

# Set git identity (if builders commit)
curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/environmentVariable" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"key": "GIT_USER_NAME", "value": "Alice Smith", "scope": "ENVIRONMENT", "is_secret": false}'

curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/environmentVariable" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"key": "GIT_USER_EMAIL", "value": "alice@company.com", "scope": "ENVIRONMENT", "is_secret": false}'
```

Only set the variables the user provided — skip any that were left blank. After setting env vars, redeploy the environment so the workspace picks them up:

```bash
qovery rde start -n alice -o "{org-name}"
```

**Tip:** If all builders share the same repo, set `GIT_REPO_URL`, `GIT_TOKEN`, and `GIT_BRANCH` at the **project level** (scope `PROJECT`) on the blueprint project instead, so every cloned environment inherits them automatically. Per-builder variables like `GIT_USER_NAME` and `GIT_USER_EMAIL` should still be set at the environment level.

### 3.4 Verify

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

### 3.5 Share workspace URLs

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

### 3.6 Provide the quick reference

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

### 3.7 Next steps

> **Your builder environments are ready!**
>
> Optional next steps:
> - **Upgrade all builders** after template changes: `qovery rde upgrade -o org -s image`
> - **Add a visual builder**: see the [customization guide](customization.md) to add a Lovable-like service to the blueprint
> - **Customize TTL, resources, isolation**: see the [customization guide](customization.md)
> - **Terraformize**: run `/qovery-terraform` to convert this setup to Terraform manifests (coming soon)
