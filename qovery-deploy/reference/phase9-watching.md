## PHASE 9: Deployment Watching & Verification

After triggering a deployment (Phase 4 or Phase 5), you MUST actively watch it and verify success. Do NOT just tell the user "it's deploying" and walk away.

### 9.1 Offer to Watch

Immediately after deploying, ask the user:

> "The deployment is in progress. Would you like me to watch it and automatically diagnose and fix any issues if the deployment fails?"

If the user says yes (or doesn't object), enter the active watch loop below. If they explicitly decline, provide them with the manual verification commands and skip to 9.4.

### 9.2 Active Deployment Watch Loop

Watch the deployment and detect success or failure:

```bash
# Option A: CLI, block until the deployment you triggered finishes
#   add --watch to the deploy command itself, e.g.
#   qovery application deploy --application "my-app" --environment "production" --watch
#   or take a snapshot of every service in the environment:
qovery environment statuses --organization "My Org" --project "My Project" --environment "production" --json

# Option B: API (scriptable, poll every 15-30 seconds)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, state, status_details: .status_details}],
    databases: [.databases[] | {id, state}],
    jobs: [.jobs[] | {id, state}],
    helms: [.helms[] | {id, state}],
    terraforms: [.terraforms[] | {id, state}]
  }'
```

Keep polling until the environment state is one of:
- **DEPLOYED** / **READY** -> Success! Go to 9.4
- **BUILD_ERROR** / **DEPLOYMENT_ERROR** / **STOP_ERROR** / **RESTART_ERROR** -> Failure! Go to Phase 10
- **CANCELED** -> Tell the user, ask if they want to retry

The `status_details` field for each service tells you exactly where it failed:
- `action`: What was being done (`DEPLOY`, `DELETE`, `RESTART`, `STOP`)
- `status`: Result (`QUEUED`, `ONGOING`, `SUCCESS`, `ERROR`, `CANCELED`)

The deployment step metrics tell you WHICH step failed:
- `GIT_CLONE` -> Git access issue
- `BUILD` -> Docker build failure
- `MIRROR_IMAGE` -> Registry push failure
- `DEPLOYMENT` -> Kubernetes deployment failure (health check, crash, OOM, etc.)
- `EXECUTING` -> Job or Terraform execution failure

### 9.3 Fetch Logs on Failure

When any service enters an error state, immediately fetch its logs:

```bash
# Via CLI: deployment (build + rollout) logs of the last deployment, errors only
qovery environment deployment logs --environment "production" --service "my-app" --errors-only

# Via CLI: live application logs. `qovery log` streams until interrupted and has no
# --since/--tail/--filter flags, so bound it and filter with grep
# (on macOS `timeout` comes from coreutils as `gtimeout`):
timeout 30 qovery log --application "my-app" | grep -iE "error|fatal|panic|exit"

# Via API: the last 1000 deployment log lines of the environment (build + rollout, all services)
qovery api environment/{envId}/logs | jq -r '.[-50:][] | .message.safe_message // empty'

# Deployment history, to see which step failed and how long it took
qovery api application/{appId}/deploymentHistory | jq '.results[0]'
```

There is no per-service REST endpoint for runtime logs (`/application/{id}/log` does not exist).
For past runtime logs use the Qovery MCP server (`get_service_logs`) when it is connected,
otherwise the bounded `qovery log` stream above.

After fetching logs, analyze them and proceed to Phase 10 for diagnosis and fix.

### 9.4 Verify Success

When all services are deployed successfully:

```bash
# 1. List all services and their statuses
qovery service list

# 2. Get the public URLs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/link" | jq '.results'

# 3. Test the health endpoint
curl -s https://{app-url}/health

# 4. View recent logs to confirm healthy operation (streams; bound it)
timeout 20 qovery log --application "my-app" | tail -20

# 5. Open a shell into a running container (for debugging if needed)
qovery shell --organization "My Org" --project "My Project" --environment "production" --service "my-app"

# 6/7. Port-forward to a service or database locally (secure tunnel, no public exposure).
# port-forward has no --service flag: it uses the CLI context or asks interactively, so the
# user runs it in their own terminal:
#   qovery context set            # pick org / project / environment / service
#   qovery port-forward -p 8080:8080
#   qovery port-forward -p 5432:5432   # with the database selected
# Then in another terminal: psql -h localhost -p 5432 -U myuser -d mydatabase
```

See Phase 8.8 for the full port-forward guide (all database types, different local ports, local dev workflows).

Tell the user:
- Their application is deployed and accessible at the Qovery-generated URL
- They can add a custom domain in the Qovery Console or via the API
- Auto-deploy is enabled: every git push to the configured branch triggers a new deployment
- They can monitor logs, metrics, and deployment history in the Qovery Console at https://console.qovery.com
- For the Terraform path: the `qovery.tf` file should be committed to git (but NEVER commit secrets or API tokens)

### 9.5 Credentials

This skill does not create API tokens (it uses `qovery api` and the CLI session), so there is
nothing to clean up. If the user created a long-lived token for the Terraform path, remind them it
lives in Console > Organization Settings > API Tokens and should be revoked when no longer needed.
