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

