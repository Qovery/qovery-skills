## PHASE 1: Context Gathering

Before creating anything, gather all the information needed to build the preview environment.

### 1.1 Authenticate

Use the same authentication flow as the other Qovery skills:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set in the environment
2. If not, try `qovery auth token --print` — if the CLI is authenticated, this outputs a valid token (auto-refreshed if expired). Use it directly with `Authorization: Bearer $(qovery auth token --print)` or generate a named API token via `qovery token create --name "preview-skill" --duration 24h`.
3. If the CLI is not authenticated, run `qovery auth` for interactive login, then use step 2.
- Only ask the user to manually create a token at Qovery Console > Organization Settings > API Tokens if none of the above options work

### 1.2 Detect PR / Branch Context

Auto-detect the pull request or branch from the local git workspace and user input:

**From the local workspace:**
```bash
# Current branch name
git branch --show-current

# Git remote URL (to match services in the environment)
git remote get-url origin

# PR metadata (if GitHub CLI is available)
gh pr view --json number,title,headRefName,baseRefName,url 2>/dev/null
```

**From user input:**
- `"PR-123"` or `"#123"` → fetch PR details via `gh pr view 123 --json number,title,headRefName,baseRefName`
- `"feat/my-feature"` → branch name directly, detect base branch from git: `git log --oneline --merges --first-parent main..feat/my-feature` or ask the user
- A GitHub/GitLab PR URL → parse the PR number and fetch details
- A Qovery Console URL → extract IDs using URL Detection rules above

**What to resolve:**
- **PR branch** (the feature branch to deploy) — e.g., `feat/my-feature`
- **Base branch** (what the PR targets) — e.g., `main`, `staging`, `develop`
- **Git repository URL** (to match against services in the environment)
- **PR number** (for naming the preview environment) — e.g., `123`
- **PR title** (for display) — e.g., `"Add user dashboard"`

If auto-detection fails, ask the user:
> "Which branch or PR should I create a preview environment for? You can provide:
> - A branch name (e.g., `feat/my-feature`)
> - A PR number (e.g., `PR-123`)
> - A PR URL"

### 1.3 Resolve Organization & Cluster

**Shortcut:** If the user provided a Qovery Console URL, extract the organization ID and any other IDs from it using the URL Detection rules above.

After authenticating, **proactively list all organizations** the user has access to:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | {id, name}'
```

- **If 1 organization**: Confirm and move on.
- **If multiple organizations**: Present the list and ask which one to use. Do NOT silently pick the first one.

After selecting the organization, **list all clusters**:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'
```

- **If 1 cluster**: Confirm the cluster.
- **If multiple clusters**: Present the list and ask which one to deploy the preview to.
  - Recommend using a non-production cluster for preview environments (cheaper, no risk to production workloads).
- Verify the selected cluster is in `DEPLOYED` or `READY` status before proceeding.

### 1.4 Check for Existing Blueprint Environment

Search all projects in the organization for a blueprint environment:

```bash
# List all projects
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/project" | jq '.results[] | {id, name}'

# For each project, list environments
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '.results[] | {id, name, mode, cluster_id}'
```

Look for:
- An environment named `blueprint` or containing `blueprint` in the name (case-insensitive)
- An environment with services that match the same git repository as the PR

**If a blueprint is found:**
1. Show the user what was found:
   > "I found an existing blueprint environment: **{name}** in project **{project}** with {N} services."
2. List the services in the blueprint:
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/environment/{blueprintEnvId}/statuses" | jq '{
       applications: [.applications[] | {id, name: .name, state}],
       containers: [.containers[] | {id, name: .name, state}],
       databases: [.databases[] | {id, name: .name, state}],
       jobs: [.jobs[] | {id, name: .name, state}]
     }'
   ```
3. Confirm with the user: "Should I use this as the blueprint for the preview environment?"
4. If confirmed → **skip to Phase 3**

**If NO blueprint is found:**
1. Tell the user: "No blueprint environment found. I'll create one for you."
2. → Go to **Phase 2**

---

