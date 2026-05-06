## PHASE 5: Cost Controls & Lifecycle Management

### 5.1 TTL Lifecycle Job — Auto-Stop and Auto-Delete

Each builder environment has a **TTL (time-to-live)** — a lifecycle job that automatically stops or deletes the environment after a configured duration. This is the primary cost control mechanism. The TTL was configured by the platform engineer in Phase 1.3 and is created automatically by the provisioning script (Phase 4.4).

**How the TTL lifecycle job works:**

1. A **cron job** is created inside each builder environment using a raw Dockerfile (`curlimages/curl:8.11.1` — no git repo needed)
2. The job runs on a schedule (e.g., every hour) and calls the Qovery API to **stop** the environment
3. A dedicated API token (`SHUTDOWN_TOKEN`) is stored as a secret on the job — the builder cannot see or modify it
4. The platform team controls the TTL via the `builder-platform-config.yaml` file

**TTL cron job creation (via API):**

This is already handled by the provisioning script (Phase 4.4, Step 4), but here's the standalone API call for reference:

```bash
# 1. Generate a shutdown token
SHUTDOWN_TOKEN=$(curl -sf -X POST "https://api.qovery.com/organization/{orgId}/apiToken" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-ttl-{name}", "description": "Auto-shutdown token for builder-{name}"}' | jq -r '.token')

# 2. Create the TTL cron job
JOB_ID=$(curl -sf -X POST "https://api.qovery.com/environment/{builderEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-shutdown",
    "description": "Automatically stops this environment after the configured TTL",
    "cpu": 250,
    "memory": 256,
    "max_nb_restart": 0,
    "max_duration_seconds": 60,
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
        "arguments": ["-c", "curl -sf -X POST https://api.qovery.com/environment/{builderEnvId}/stop -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo \"Environment stopped by TTL\" || echo \"Already stopped or failed\""],
        "scheduled_at": "0 20 * * 1-5",
        "timezone": "Europe/Paris"
      }
    }
  }' | jq -r '.id')

# 3. Set the shutdown token as a secret
curl -sf -X POST "https://api.qovery.com/application/$JOB_ID/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"SHUTDOWN_TOKEN\", \"value\": \"$SHUTDOWN_TOKEN\"}"
```

**Common TTL cron schedules:**

| TTL | Cron Expression | Description |
|-----|----------------|-------------|
| Business hours | `0 20 * * 1-5` | Stop at 8pm weekdays |
| 8 hours | `0 */8 * * *` | Stop every 8 hours |
| 24 hours | `0 0 * * *` | Stop at midnight daily |
| 1 week | `0 0 * * 0` | Stop every Sunday midnight |
| Specific date | `0 10 15 6 *` | Stop at 10am on June 15 |

**Auto-delete after extended inactivity (optional):**

If the platform engineer configured a `delete_after` TTL in addition to `stop_after`, create a **second cron job** that deletes the environment if it has been stopped for longer than the specified period:

```bash
# Delete job — runs weekly, checks if environment has been stopped for > N days
curl -sf -X POST "https://api.qovery.com/environment/{builderEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-delete",
    "description": "Deletes this environment if stopped for more than 7 days",
    "cpu": 250,
    "memory": 256,
    "max_nb_restart": 0,
    "max_duration_seconds": 60,
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
        "arguments": ["-c", "curl -sf -X DELETE https://api.qovery.com/environment/{builderEnvId} -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo \"Environment deleted by TTL\" || echo \"Delete failed or already deleted\""],
        "scheduled_at": "0 0 * * 0",
        "timezone": "Etc/UTC"
      }
    }
  }'
```

### 5.2 Business Hours Schedule (Complementary to TTL)

In addition to the TTL lifecycle job, configure deployment rules to stop environments during off-hours for additional savings:

**Business hours schedule (recommended):**
- Start: weekdays at 8:00 AM (builder's timezone)
- Stop: weekdays at 8:00 PM (builder's timezone)
- Weekends: stopped all day

This works alongside the TTL — the business hours schedule handles daily stop/start, while the TTL handles the overall environment lifetime.

### 5.2 Resource Limits Per Builder

Set per-environment resource limits to prevent cost overruns:

| Resource | Recommended for Dev | Notes |
|----------|-------------------|-------|
| IDE CPU | 1000m (1 core) | Enough for VS Code + AI tools |
| IDE Memory | 2048MB (2GB) | Increase to 4GB for heavy AI workloads |
| Database CPU | 250m | Container mode only for dev |
| Database Memory | 256MB | Increase for larger datasets |
| Database Storage | 10GB | Sufficient for dev data |

These are set when creating the template (Phase 3.4) and inherited by all cloned environments.

### 5.3 Cost Monitoring & Alerts

Show the platform engineer how to monitor builder costs:

```bash
# View all builder environments and their statuses
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '[.results[] | {name, mode, cluster_id}]'
```

Recommendations:
- Use the Qovery Console dashboard for visual cost monitoring
- Set up budget alerts in your cloud provider (AWS Budgets, GCP Budgets, Azure Cost Alerts)
- Reference the qovery-optimize skill for deeper cost analysis: "Say 'Optimize my Qovery costs' for a detailed cost report"

### 5.4 Environment Cleanup Policy

Establish a cleanup policy for inactive builder environments:

- **30 days inactive** -> warn the builder, ask if still needed
- **60 days inactive** -> stop the environment automatically
- **90 days inactive** -> delete the environment (with warning)

Track last activity via the Qovery API:
```bash
# Check deployment history (last activity) for each environment
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/deploymentHistory?version=v2" | jq '.results[0].created_at'
```

---

