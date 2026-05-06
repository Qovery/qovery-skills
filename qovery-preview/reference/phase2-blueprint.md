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

