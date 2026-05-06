## PHASE 9: Deployment Watching & Verification

After triggering a deployment (Phase 4 or Phase 5), you MUST actively watch it and verify success. Do NOT just tell the user "it's deploying" and walk away.

### 9.1 Offer to Watch

Immediately after deploying, ask the user:

> "The deployment is in progress. Would you like me to watch it and automatically diagnose and fix any issues if the deployment fails?"

If the user says yes (or doesn't object), enter the active watch loop below. If they explicitly decline, provide them with the manual verification commands and skip to 9.4.

### 9.2 Active Deployment Watch Loop

Watch the deployment and detect success or failure:

```bash
# Option A: CLI (interactive, real-time)
qovery status --watch

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
# Via CLI — get last 10 minutes, filter for errors
qovery log --application "my-app" --since 10m
qovery log --application "my-app" --since 10m --filter "ERROR"
qovery log --application "my-app" --since 10m --filter "error"
qovery log --application "my-app" --since 10m --filter "FATAL"
qovery log --application "my-app" --since 10m --filter "panic"
qovery log --application "my-app" --since 10m --filter "Exit"

# Via API — get last 1000 log lines
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[-50:] | .[] | .message'

# Get deployment history to see which step failed and duration
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/deploymentHistory" | jq '.results[0]'
```

For other service types, replace the endpoint:
- Containers: `GET /container/{containerId}/log`
- Jobs: `GET /job/{jobId}/log`
- Databases: `GET /database/{databaseId}/log` (limited)
- Helm: `GET /helm/{helmId}/log`

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

# 4. View recent logs to confirm healthy operation
qovery log --application "my-app" --tail 20

# 5. Open a shell into a running container (for debugging if needed)
qovery shell --application "my-app"

# 6. Port-forward to access internal services locally (secure tunnel, no public exposure)
qovery port-forward --service "my-app" --port 8080:8080

# 7. Port-forward to access the database locally (e.g., for pgAdmin, DBeaver, psql)
qovery port-forward --service "postgres" --port 5432:5432
# Then in another terminal: psql -h localhost -p 5432 -U myuser -d mydatabase
```

See Phase 8.8 for the full port-forward guide (all database types, different local ports, local dev workflows).

Tell the user:
- Their application is deployed and accessible at the Qovery-generated URL
- They can add a custom domain in the Qovery Console or via the API
- Auto-deploy is enabled: every git push to the configured branch triggers a new deployment
- They can monitor logs, metrics, and deployment history in the Qovery Console at https://console.qovery.com
- For the Terraform path: the `qovery.tf` file should be committed to git (but NEVER commit secrets or API tokens)

### 9.5 Token Cleanup

If you generated an API token earlier via `qovery token` during Phase 2, offer to delete it now that deployment is complete. This is good security practice — short-lived tokens reduce the blast radius if compromised.

```bash
# List tokens to find the one you created
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/apiToken" | jq '.results[] | {id, name, created_at}'

# Delete the token by ID
curl -s -X DELETE "https://api.qovery.com/organization/{orgId}/apiToken/{tokenId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Ask the user: "I generated an API token earlier for deployment. Would you like me to delete it now, or keep it for future use?"

- If the user wants to keep it: remind them to store it securely and that it can be managed at Qovery Console > Organization Settings > API Tokens
- If the user wants to delete it: delete via the API above
- If a JWT token was used instead (Method 2): no cleanup needed, it expires automatically

---

