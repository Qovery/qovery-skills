---
name: qovery-preview
description: Create temporary preview environments from pull requests using Qovery. Detects or creates a blueprint environment, clones it for each PR, switches git branches, configures auto-shutdown, and provides cleanup. Supports full-stack and single-service previews.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: preview-environments
---

# Qovery Preview Environment Skill

You are an expert at creating preview environments on Kubernetes using Qovery. When a user asks you to create a preview environment for a pull request or branch, follow this skill to detect context, find or create a blueprint environment, clone it, switch branches, configure auto-shutdown, and deploy.

## When to Use This Skill

Use this skill when the user says anything like:
- "Create a preview environment for the current branch"
- "Create a PR environment for PR-123"
- "Set up preview environments for my project"
- "Clone my environment for this feature branch"
- "I want to test my PR in isolation"
- "Preview this branch on Qovery"
- "Create a temporary environment for my feature"
- `/qovery-preview` (slash command)

---

## Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or `new-console.qovery.com`), extract the resource IDs directly from the URL path. This is especially useful for preview environments — the user may paste a URL to the environment they want to use as a blueprint, or to a service they want to preview.

**URL format:**
```
https://{console.qovery.com|new-console.qovery.com}/organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}[/{page}]
```

**Extraction rules:**
- `orgId` — UUID after `/organization/`
- `projectId` — UUID after `/project/`
- `envId` — UUID after `/environment/`
- `serviceId` — UUID after `/service/`
- `page` — optional suffix gives context about the user's intent

Not every URL contains all segments. Use whatever IDs are present:
- URL with `orgId` + `projectId` -> organization and project are known
- URL with `envId` -> the user may be pointing to the blueprint or source environment
- URL with `serviceId` -> the user may want to preview only that specific service

**After extracting IDs, resolve names and status via the API:**
```bash
# Get organization name
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | select(.id == "{orgId}") | {id, name}'

# Get environment name + all service names/statuses in one call
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, name: .name, state}],
    containers: [.containers[] | {id, name: .name, state}],
    databases: [.databases[] | {id, name: .name, state}],
    jobs: [.jobs[] | {id, name: .name, state}],
    helms: [.helms[] | {id, name: .name, state}]
  }'

# Get cluster ID from the environment
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}" | jq '{cluster_id: .cluster_id}'
```

**Use the extracted IDs directly** in all subsequent API calls — skip discovery questions for resources already identified by the URL.

---

## PHASE 1: Context Gathering

Before creating anything, gather all the information needed to build the preview environment.

### 1.1 Authenticate

Use the same authentication flow as the other Qovery skills:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set in the environment
2. If not, check if the CLI is authenticated: look for `~/.qovery/context.json` with a valid `access_token`
3. If the CLI is authenticated, you can generate a token via `qovery token --name "preview-skill"` (see Phase 4 for the shutdown token)
4. As a fallback, the CLI's JWT token from `~/.qovery/context.json` can be used directly with `Authorization: Bearer <jwt>` instead of `Authorization: Token <api-token>`
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

## PHASE 2: Create Blueprint Environment

A blueprint environment is a fully working template of your application stack. It is cloned to create each preview environment. The blueprint is created once and reused for all future PRs.

### 2.1 Find a Source Environment to Clone

Look for an existing deployed environment that can serve as the source for the blueprint:

```bash
# List all environments with their statuses
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '.results[] | {id, name, mode}'
```

For each environment, check its status:
```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '.environment.state'
```

Look for an environment that:
- Has `DEPLOYED` or `STOPPED` status (it was successfully deployed at least once)
- Contains services from the same git repository as the PR
- Ideally is in `STAGING` or `DEVELOPMENT` mode (not production)

**If multiple candidates exist**: Present them and ask the user:
> "I found these deployed environments that could serve as a blueprint source:
> 1. **staging** (DEPLOYED, 4 services)
> 2. **development** (STOPPED, 4 services)
> 3. **production** (DEPLOYED, 4 services)
>
> Which one should I clone to create the blueprint? I recommend using a non-production environment."

**If NO deployed environment exists**: The user needs to deploy first. Tell them:
> "No deployed environment found in this project. You need a working environment before creating preview environments.
>
> Say **'Deploy my application with Qovery'** to set up your first deployment using the qovery-deploy skill, then come back to create preview environments."

STOP here if no source environment exists. Do NOT try to create an environment from scratch — that's the deploy skill's job.

### 2.2 Clone to Create the Blueprint

Clone the source environment to create the blueprint:

**Via API:**
```bash
curl -s -X POST "https://api.qovery.com/environment/{sourceEnvId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "blueprint",
    "cluster_id": "{clusterId}",
    "mode": "DEVELOPMENT"
  }' | jq '{id, name, mode}'
```

**Via CLI:**
```bash
qovery environment clone --environment "{source-env-name}" --name "blueprint"
```

IMPORTANT: Use `DEVELOPMENT` mode for the blueprint, not `PREVIEW`. The blueprint is a template, not a preview itself. Preview environments cloned from it will use `PREVIEW` mode.

### 2.3 Configure the Blueprint

After cloning, configure the blueprint for preview use:

**1. Set the base branch on all git-based services:**

The base branch should match the branch that PRs are created against (e.g., `main`, `staging`, `develop`). This was detected in Phase 1.2.

```bash
# Get all applications in the blueprint
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{blueprintEnvId}/application" | jq '.results[] | {id, name, git_repository}'

# For each application, update the branch and enable auto_preview
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "{current-name}",
    "git_repository": {
      "url": "{current-url}",
      "branch": "{base-branch}",
      "root_path": "{current-root-path}",
      "provider": "{current-provider}"
    },
    "auto_preview": true,
    "auto_deploy": false,
    "healthchecks": {}
  }'
```

Do the same for containers with git sources. Jobs and Helm charts should also have `auto_preview` set if they should be included in previews.

IMPORTANT: When calling `PUT /application/{appId}`, you must include ALL required fields from the current configuration, not just the ones you're changing. Fetch the current config first with `GET /application/{appId}` and modify only the fields you need to change.

**2. Turn off auto-deploy on the blueprint:**

The blueprint should NOT auto-deploy on git push — it's a static template.

**3. Enable auto_preview on all services:**

This ensures that when the blueprint is cloned, all services are included.

### 2.4 Validate the Blueprint

The blueprint must be validated before it can be used to create preview environments. This only needs to happen once — on first creation.

**1. Deploy the blueprint:**
```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Or via CLI:
```bash
qovery environment deploy --environment "blueprint"
```

**2. Watch the deployment:**

Poll the environment statuses until all services are deployed:
```bash
# Poll every 15-30 seconds until environment state is DEPLOYED or an error state
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{blueprintEnvId}/statuses" | jq '{
    environment: .environment.state,
    services: [
      (.applications[] | {name: .name, state, type: "application"}),
      (.databases[] | {name: .name, state, type: "database"}),
      (.jobs[] | {name: .name, state, type: "job"}),
      (.containers[] | {name: .name, state, type: "container"})
    ]
  }'
```

- **All services DEPLOYED** → continue to step 3
- **Any service in error state** → fetch logs, diagnose. If the blueprint can't be deployed, the source environment may have issues. Reference the qovery-troubleshoot skill: "Say 'My Qovery deployment is failing' for help troubleshooting."

**3. Run health checks:**
```bash
# Get public URLs for applications
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/link" | jq '.results'

# Test each health endpoint
curl -s https://{app-url}/health
```

**4. Stop the blueprint to save resources:**
```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/stop" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Or via CLI:
```bash
qovery environment stop --environment "blueprint"
```

**5. Confirm to the user:**
> "Blueprint environment **blueprint** validated successfully and stopped. It will be used as the template for all future preview environments. No resources are being consumed while it's stopped."

---

## PHASE 3: Create Preview Environment from Blueprint

### 3.1 Ask the User — Scope of Preview

Ask the user what they want to preview:

> "Do you want to preview the **full environment** (all services cloned) or just switch the branch on **specific services** that changed in this PR?"
>
> 1. **Full clone** (recommended) — clones all services, databases, and configuration. Fully isolated preview.
> 2. **Selective branch switch** — clones everything, but only switches the branch on services from the same git repository as the PR. Other services stay on the base branch. All services are still cloned for isolation.

Default to **full clone** if the user doesn't have a preference — it's the safest option and ensures complete isolation.

### 3.2 Clone the Blueprint

Name the preview environment based on the PR or branch:
- From PR: `preview-pr-{number}` (e.g., `preview-pr-123`)
- From branch: `preview-{sanitized-branch-name}` (e.g., `preview-feat-my-feature`)
  - Sanitize the branch name: replace `/` with `-`, remove special characters, truncate to 50 characters

**Via API:**
```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "preview-pr-{number}",
    "cluster_id": "{clusterId}",
    "mode": "PREVIEW"
  }' | jq '{id, name, mode}'
```

**Via CLI:**
```bash
qovery environment clone --environment "blueprint" --name "preview-pr-{number}"
```

Store the new environment ID — it will be used for all subsequent operations.

### 3.3 Switch Branch on Relevant Services

After cloning, list all services in the new preview environment and switch branches on the ones that match the PR's git repository:

**1. List all applications in the preview environment:**
```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{previewEnvId}/application" | jq '.results[] | {id, name, git_repository: {url: .git_repository.url, branch: .git_repository.branch}}'
```

**2. For each application from the same git repo as the PR, switch the branch:**
```bash
# First, GET the full current config
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}" > /tmp/app-config.json

# Then PUT with the updated branch
# IMPORTANT: include ALL required fields from the current config, only changing the branch
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "{current-name}",
    "git_repository": {
      "url": "{current-url}",
      "branch": "{pr-branch}",
      "root_path": "{current-root-path}",
      "provider": "{current-provider}"
    },
    "auto_preview": false,
    "auto_deploy": false,
    "healthchecks": { ... current healthchecks ... }
  }'
```

**3. Do the same for containers** that use git sources from the same repository.

**4. Leave unchanged:**
- Services from different git repositories (shared libraries, external services)
- Databases (cloned with config but empty data — no branch to switch)
- Jobs that don't need branch-specific code

**5. Remind about database seeding** if the environment has databases:
> "Note: Databases are cloned with their configuration but NOT their data. If your application needs seed data, you may need to run migrations or seed scripts after deployment."
>
> See https://github.com/qovery/lifecycle-job-examples/tree/main/examples/seed-postgres-database-with-sql-script for a database seeding example using a Qovery lifecycle job.

---

## PHASE 4: Auto-Shutdown Configuration

Preview environments should be temporary to avoid wasting resources. Configure an automatic lifecycle management strategy.

### 4.1 Ask the User — Lifecycle Strategy

Ask the user how the preview environment should be managed:

> "How should this preview environment be managed when no longer needed?"
>
> 1. **Auto-stop after a duration** — stops all services to save compute costs. The environment can be restarted later if needed. Good for active development.
> 2. **Auto-delete after a duration** — completely removes the environment after the specified time. No resources remain. Good for one-time reviews.
> 3. **Recycle** — stops after an initial duration, then deletes only if not restarted within a second window. Faster to restart than creating a new preview, but keeps some resources allocated (e.g., managed databases, persistent volumes). Good for PRs that need multiple rounds of review.
> 4. **Manual cleanup only** — no auto-shutdown. You manage the lifecycle manually.
> 5. **Delete when PR is merged/closed** — requires a CI/CD integration (GitHub Actions, GitLab CI, etc.). I'll generate the workflow file for you.

Also ask:
> "How long should the environment stay alive before the first action? (e.g., 4h, 24h, 48h, 1 week)"

For the **recycle** option, also ask:
> "How long after stopping should it wait before auto-deleting? (e.g., 3 days, 7 days)"

### 4.2 Create Auto-Shutdown Job

For options 1, 2, and 3, create a cron job inside the preview environment that calls the Qovery API at the scheduled time. The job uses a raw Dockerfile (no git repo needed) with `curlimages/curl`.

**Step 1: Generate an API token for the shutdown job**

The cron job needs a Qovery API token to call the stop/delete endpoint. Generate one:
```bash
qovery token --name "preview-shutdown-pr-{number}-$(date +%Y%m%d)"
```

Store the returned token — it will be set as a secret on the job.

**Step 2: Calculate the cron schedule**

Convert the user's duration into a one-time cron expression based on the current time.

Example: If now is 2024-01-15 10:00 UTC and the user wants 24h:
- Stop cron: `0 10 16 1 *` (10:00 UTC on Jan 16)

For the **recycle** option with "stop after 24h, delete after 7 days":
- Stop cron: `0 10 16 1 *` (Jan 16)
- Delete cron: `0 10 22 1 *` (Jan 22)

IMPORTANT: Cron expressions for one-time execution should use specific day-of-month and month values. The job will execute once at the scheduled time. After execution, it won't run again (unless the same day/month pattern repeats next year, but the environment will be gone by then).

**Step 3: Create the stop/delete cron job**

**For auto-stop (option 1):**
```bash
curl -s -X POST "https://api.qovery.com/environment/{previewEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "auto-shutdown",
    "description": "Automatically stops this preview environment after the configured duration",
    "cpu": 250,
    "memory": 256,
    "max_nb_restart": 0,
    "max_duration_seconds": 120,
    "auto_preview": false,
    "auto_deploy": false,
    "healthchecks": {},
    "source": {
      "docker": {
        "dockerfile_raw": "FROM curlimages/curl:8.11.1\nENTRYPOINT [\"sh\", \"-c\"]"
      }
    },
    "schedule": {
      "cronjob": {
        "entrypoint": "sh",
        "arguments": ["-c", "curl -sf -X POST \"https://api.qovery.com/environment/{previewEnvId}/stop\" -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo 'Environment stop requested successfully' || echo 'Failed to stop environment'"],
        "scheduled_at": "{cron_expression}",
        "timezone": "Etc/UTC"
      }
    }
  }' | jq '{id, name}'
```

**For auto-delete (option 2):**
Replace the curl command with:
```bash
"arguments": ["-c", "curl -sf -X DELETE \"https://api.qovery.com/environment/{previewEnvId}\" -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo 'Environment delete requested successfully' || echo 'Failed to delete environment'"]
```

**For recycle (option 3):**
Create TWO cron jobs:
1. `auto-stop` — stops after the initial duration (same as option 1)
2. `auto-cleanup` — deletes after the extended window (same as option 2, but later cron schedule)

**Step 4: Set the shutdown token as a secret on the job(s)**
```bash
curl -s -X POST "https://api.qovery.com/application/{jobId}/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "SHUTDOWN_TOKEN", "value": "{generated-token}"}'
```

Note: Use the `/application/{jobId}/secret` endpoint — jobs share the same secret API as applications in Qovery.

### 4.3 CI/CD Integration (Option 5 — Delete on PR Merge/Close)

If the user chose to delete the preview when the PR is merged or closed, generate a CI workflow file:

**GitHub Actions:**
```yaml
# .github/workflows/qovery-preview-cleanup.yml
name: Cleanup Qovery Preview Environment
on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Delete preview environment
        env:
          QOVERY_API_TOKEN: ${{ secrets.QOVERY_API_TOKEN }}
        run: |
          PR_NUMBER=${{ github.event.pull_request.number }}
          ENV_NAME="preview-pr-${PR_NUMBER}"

          # Find the environment ID by name
          ENV_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
            "https://api.qovery.com/project/{projectId}/environment" | \
            jq -r ".results[] | select(.name == \"${ENV_NAME}\") | .id")

          if [ -n "$ENV_ID" ] && [ "$ENV_ID" != "null" ]; then
            curl -sf -X DELETE "https://api.qovery.com/environment/${ENV_ID}" \
              -H "Authorization: Token $QOVERY_API_TOKEN"
            echo "Deleted preview environment: ${ENV_NAME} (${ENV_ID})"
          else
            echo "No preview environment found for PR #${PR_NUMBER}"
          fi
```

**GitLab CI:**
```yaml
# Add to .gitlab-ci.yml
cleanup_preview:
  stage: cleanup
  only:
    - merge_requests
  when: manual  # Or use a webhook trigger on MR close
  script:
    - |
      MR_IID=$CI_MERGE_REQUEST_IID
      ENV_NAME="preview-pr-${MR_IID}"
      ENV_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
        "https://api.qovery.com/project/{projectId}/environment" | \
        jq -r ".results[] | select(.name == \"${ENV_NAME}\") | .id")
      if [ -n "$ENV_ID" ] && [ "$ENV_ID" != "null" ]; then
        curl -sf -X DELETE "https://api.qovery.com/environment/${ENV_ID}" \
          -H "Authorization: Token $QOVERY_API_TOKEN"
        echo "Deleted preview environment: ${ENV_NAME}"
      fi
```

Tell the user:
- They need to add `QOVERY_API_TOKEN` as a repository secret in GitHub (Settings > Secrets) or as a CI/CD variable in GitLab (Settings > CI/CD > Variables)
- Replace `{projectId}` with the actual Qovery project ID
- The workflow file should be committed to the repository

---

## PHASE 5: Deployment Plan Summary

Before executing any operations, present a complete summary of the deployment plan to the user and get explicit confirmation. This is the most important checkpoint — the next phase creates real cloud resources.

### 5.1 Generate the Summary

Present a structured summary:

> **Preview Environment Plan**
>
> **Context:**
> - PR: **#{number}** — {title} (`{pr_branch}` → `{base_branch}`)
> - Repository: `{repo-url}`
> - Organization: **{org_name}** | Cluster: **{cluster_name}** ({region})
> - Project: **{project_name}**
>
> **Blueprint:** `{blueprint_name}` *(existing / will be created from `{source_env}`)*
>
> **Preview environment to create:**
> - Name: `preview-pr-{number}`
> - Mode: `PREVIEW`
> - Cloned from: `{blueprint_name}`
>
> **Services — branch changes:**
>
> | Service | Type | Current Branch | New Branch |
> |---------|------|---------------|------------|
> | backend | Application | main | feat/my-feature |
> | frontend | Application | main | feat/my-feature |
> | postgres | Database | — | — (cloned config, empty data) |
> | redis | Database | — | — (cloned config) |
> | auto-shutdown | Cron Job | — | — (will be created) |
>
> **Auto-shutdown:**
> - Strategy: {stop/delete/recycle/manual/PR-merge}
> - Scheduled: {datetime} ({duration} from now)
>
> **Warnings:**
> - Database data is NOT cloned — seed scripts may be needed
> - A Qovery API token will be generated for the auto-shutdown job
> - Preview environments consume cluster resources while running

Adapt the template to the actual context. Omit sections that don't apply.

### 5.2 Get Confirmation

Ask the user:

> "Does this plan look correct? I'll proceed once you confirm. Let me know if you want to change anything or if you have additional instructions."

**CRITICAL: Do NOT proceed to Phase 6 until the user explicitly confirms.** The next phase creates cloud resources and deploys services.

### 5.3 Handle Changes

If the user wants to modify the plan:
1. Adjust the relevant settings
2. Re-present the **full updated summary**
3. Get confirmation again

Common change requests:
- Different cluster
- Different blueprint source
- Different auto-shutdown duration
- Add/remove services from branch switching
- Skip database cloning
- Add environment variables specific to the preview

---

## PHASE 6: Deploy & Verify

### 6.1 Execute the Plan

Execute the operations in order:

1. **Create blueprint** (if needed — Phase 2)
2. **Clone the blueprint** to create the preview environment (Phase 3.2)
3. **Switch branches** on relevant services (Phase 3.3)
4. **Create auto-shutdown job** (if configured — Phase 4.2)
5. **Deploy the preview environment:**

```bash
curl -s -X POST "https://api.qovery.com/environment/{previewEnvId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Or via CLI:
```bash
qovery environment deploy --environment "preview-pr-{number}"
```

### 6.2 Watch Deployment

Actively watch the deployment — do NOT just tell the user "it's deploying" and walk away.

```bash
# Poll every 15-30 seconds
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{previewEnvId}/statuses" | jq '{
    environment: .environment.state,
    services: [
      (.applications[] | {name: .name, state, type: "app"}),
      (.databases[] | {name: .name, state, type: "db"}),
      (.jobs[] | {name: .name, state, type: "job"}),
      (.containers[] | {name: .name, state, type: "container"})
    ]
  }'
```

Keep polling until:
- **DEPLOYED** → success, go to 6.3
- **BUILD_ERROR** / **DEPLOYMENT_ERROR** → failure, fetch logs and diagnose
- **CANCELED** → tell user, ask if they want to retry

On failure, fetch logs:
```bash
# Use the service-type-appropriate flag
qovery log --service "{service-name}" --since 10m
qovery log --service "{service-name}" --since 10m --filter "ERROR"

# Via API (for applications)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[-30:] | .[] | .message'

# Via API (for containers)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/container/{containerId}/log" | jq '.results[-30:] | .[] | .message'

# Environment deployment logs v2 (for deployment-level errors)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{previewEnvId}/logs" | jq '[.[] | select(.error != null) | {timestamp, error: .error.user_log_message, hint: .error.hint_message}]'
```

Common preview environment failures:
- **Branch doesn't exist**: The PR branch doesn't exist in the git repo → verify the branch name
- **Build error on new branch**: The PR code has build errors → tell the user to fix the code
- **Database connection error**: The preview DB is empty and the app expects data → suggest running seed scripts
- **Health check timeout**: The app takes longer to start in the preview → increase `initial_delay_seconds`

### 6.3 Verify & Present Results

When all services are deployed:

```bash
# Get public URLs for all applications
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/link" | jq '.results'

# Test health endpoints
curl -s https://{preview-url}/health
```

Present the results to the user:

> **Your preview environment is live!**
>
> **Preview URLs:**
> - Frontend: `https://{preview-frontend-url}`
> - Backend API: `https://{preview-backend-url}`
>
> **Auto-shutdown:** {strategy} at {datetime} ({remaining_time} from now)
>
> **Useful commands:**
> ```bash
> # Watch logs
> qovery log --service "backend" --follow
>
> # Check status
> qovery status
>
> # Restart (if stopped by auto-shutdown)
> qovery environment deploy --environment "preview-pr-{number}"
>
> # Manual stop
> qovery environment stop --environment "preview-pr-{number}"
>
> # Manual delete
> qovery environment delete --environment "preview-pr-{number}"
> ```
>
> **Console:** https://console.qovery.com/organization/{orgId}/project/{projectId}/environment/{previewEnvId}

---

## PHASE 7: Cleanup & Lifecycle Management

### 7.1 Manual Cleanup

When the user wants to delete the preview environment:

**Via CLI:**
```bash
qovery environment delete --environment "preview-pr-{number}"
```

**Via API:**
```bash
curl -s -X DELETE "https://api.qovery.com/environment/{previewEnvId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

### 7.2 Restart a Stopped Preview (Recycle)

If the preview was auto-stopped and the user wants to resume working on the PR:

```bash
# Via CLI
qovery environment deploy --environment "preview-pr-{number}"

# Via API
curl -s -X POST "https://api.qovery.com/environment/{previewEnvId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

The services will restart with the same configuration and branch. This is faster than creating a new preview environment from scratch.

### 7.3 Token Cleanup

If a shutdown token was generated for the auto-shutdown job, clean it up after the environment is deleted:

```bash
# List tokens created for preview environments
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/apiToken" | jq '.results[] | select(.name | startswith("preview-shutdown-")) | {id, name, created_at}'

# Delete the preview token
curl -s -X DELETE "https://api.qovery.com/organization/{orgId}/apiToken/{tokenId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Offer to clean up old preview tokens if there are many.

### 7.4 Blueprint Maintenance

Remind the user:
- The **blueprint environment persists** for future PRs — do NOT delete it
- It should stay **stopped** when not in use to avoid resource costs
- If the source environment (production/staging) changes significantly (new services, major config changes), the blueprint should be **re-created** by cloning the updated source
- To update the blueprint: delete the old one, clone the source again, validate, and stop

### 7.5 List All Preview Environments

To see all active preview environments:

```bash
# Via CLI
qovery environment list

# Via API — filter for preview mode
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '[.results[] | select(.mode == "PREVIEW") | {id, name, mode}]'
```

### 7.6 Bulk Cleanup

To delete all preview environments at once (e.g., sprint cleanup):

```bash
# List all preview environments
PREVIEW_ENVS=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq -r '.results[] | select(.mode == "PREVIEW") | .id')

# Delete each one
for env_id in $PREVIEW_ENVS; do
  curl -s -X DELETE "https://api.qovery.com/environment/$env_id" \
    -H "Authorization: Token $QOVERY_API_TOKEN"
  echo "Deleted environment: $env_id"
done
```

---

## Quick Reference

### CLI Commands

```bash
# Blueprint management
qovery environment clone --environment "staging" --name "blueprint"    # Create blueprint
qovery environment deploy --environment "blueprint"                     # Validate blueprint
qovery environment stop --environment "blueprint"                       # Stop blueprint after validation

# Preview environment lifecycle
qovery environment clone --environment "blueprint" --name "preview-pr-123"   # Create preview
qovery environment deploy --environment "preview-pr-123"                      # Deploy preview
qovery environment stop --environment "preview-pr-123"                        # Stop preview
qovery environment delete --environment "preview-pr-123"                      # Delete preview

# Monitoring
qovery status --watch                                                  # Watch deployment
qovery log --service "backend" --follow                                # Stream logs
qovery log --service "backend" --since 1h --filter "ERROR"             # Filter errors
qovery service list                                                    # List all services

# Environment list
qovery environment list                                                # List all environments
```

### API Endpoints

```bash
# Base URL: https://api.qovery.com
# Auth: Authorization: Token $QOVERY_API_TOKEN

# Environment lifecycle
POST   /environment/{envId}/clone              # Clone environment (create blueprint or preview)
POST   /environment/{envId}/deploy             # Deploy environment
POST   /environment/{envId}/stop               # Stop environment
DELETE /environment/{envId}                     # Delete environment

# Service configuration
GET    /environment/{envId}/application         # List applications
GET    /application/{appId}                     # Get application config
PUT    /application/{appId}                     # Edit application (switch branch)
GET    /application/{appId}/link                # Get public URLs

# Container services
GET    /environment/{envId}/container           # List containers
PUT    /container/{containerId}                 # Edit container (switch branch)

# Environment status
GET    /environment/{envId}/statuses            # All service statuses
GET    /environment/{envId}/logs                # Deployment logs v2

# Jobs (auto-shutdown)
POST   /environment/{envId}/job                 # Create cron job
POST   /application/{jobId}/secret              # Set job secret (shutdown token)

# Tokens
POST   /organization/{orgId}/apiToken           # Create API token
GET    /organization/{orgId}/apiToken           # List API tokens
DELETE /organization/{orgId}/apiToken/{tokenId}  # Delete API token

# Service logs
GET    /application/{appId}/log                 # Application logs (last 1000)
GET    /container/{containerId}/log             # Container logs (last 1000)
```

---

## Reference Links

- **Preview Environments Guide**: https://www.qovery.com/docs/getting-started/guides/use-cases/preview-environments
- **Lifecycle Job Examples**: https://github.com/qovery/lifecycle-job-examples
- **Database Seeding Example**: https://github.com/qovery/lifecycle-job-examples/tree/main/examples/seed-postgres-database-with-sql-script
- **Qovery Documentation**: https://www.qovery.com/docs/getting-started/introduction
- **Qovery Console**: https://console.qovery.com
- **CLI Reference**: https://www.qovery.com/docs/cli/commands/overview
- **API Reference**: https://www.qovery.com/docs/api-reference/introduction
- **Qovery Deploy Skill**: https://github.com/Qovery/qovery-skills (for creating initial deployments)
- **Qovery Troubleshoot Skill**: https://github.com/Qovery/qovery-skills (for diagnosing deployment failures)
