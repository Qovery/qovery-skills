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

