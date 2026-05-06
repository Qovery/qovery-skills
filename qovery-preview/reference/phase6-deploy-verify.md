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

