## PHASE 1: Measure — Deployment Timeline Analysis

Before optimizing anything, MEASURE where time is actually being spent. Do NOT guess — use data.

**Shortcut:** If the user provided a Qovery Console URL, extract the environment ID and/or service ID from it using the URL Detection rules above. Use the environment ID directly in the V2 deployment history API call below, and use the service ID to focus the timeline analysis on that specific service. Skip asking "which environment/service is slow?"

### 1.1 Gather Structured Deployment History (V2 API)

The V2 deployment history API provides a complete 3-level breakdown: environment total, per-stage, and per-service — all with durations.

**Via MCP (preferred):**
```
"Show me the deployment history for {environment}"
"How long did the last deployment take?"
"What services took the longest to deploy?"
```

**Via API — V2 endpoint (primary data source):**
```bash
# Get last 5 deployments with full stage/service breakdown and durations
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/deploymentHistoryV2?pageSize=5" | jq '.results[] | {
    execution_id: .identifier.execution_id,
    status: .status,
    total_duration: .total_duration,
    trigger: .trigger_action,
    triggered_by: .auditing_data.triggered_by,
    origin: .auditing_data.origin,
    stages: [.stages[] | {
      name: .name,
      status: .status,
      duration: .duration,
      services: [.services[] | {
        name: .identifier.name,
        type: .identifier.service_type,
        status: .status,
        total_duration: .total_duration,
        build_pod_name: .details.build_pod_name
      }]
    }]
  }'
```

This returns structured data like:
```json
{
  "execution_id": "abc123-42",
  "status": "DEPLOYED",
  "total_duration": "PT12M34S",
  "stages": [
    {
      "name": "Infrastructure",
      "status": "DONE",
      "duration": "PT3M10S",
      "services": [
        {"name": "postgres", "type": "DATABASE", "total_duration": "PT3M10S"},
        {"name": "redis", "type": "HELM", "total_duration": "PT2M45S"}
      ]
    },
    {
      "name": "Backend",
      "status": "DONE",
      "duration": "PT8M42S",
      "services": [
        {"name": "backend", "type": "APPLICATION", "total_duration": "PT8M42S", "build_pod_name": "build-abc123-42-0"},
        {"name": "worker", "type": "APPLICATION", "total_duration": "PT4M20S"}
      ]
    }
  ]
}
```

IMPORTANT: Durations are in ISO 8601 format (e.g., `PT8M42S` = 8 minutes 42 seconds). Parse accordingly.

### 1.2 Generate Build Runner Usage Report

For services with a build step (applications and jobs from Git source), generate a Grafana snapshot showing CPU, memory, and network I/O during the build:

```bash
# Get the execution_id from the V2 deployment history response
# Then generate the build runner report
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploymentBuildUsageReport" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "execution_id": "{execution_id_from_v2}",
    "report_expiration_in_seconds": 86400
  }' | jq '{report_url, delete_report_url}'
```

The `execution_id` comes directly from the V2 deployment history response (`identifier.execution_id`). It is an incremental number assigned by Qovery to each deployment execution.

The returned `report_url` is a publicly accessible Grafana snapshot (expires after 24 hours) showing:
- Build pod CPU usage over time
- Build pod memory usage over time
- Build pod network I/O
- Timeline from build start to ~40 minutes after

Share this URL with the user — it's the most powerful diagnostic for build performance.

### 1.3 Parse Deployment Logs for Sub-Step Timing

The V2 API gives per-service total duration, but NOT the sub-step breakdown within a service (git clone vs build vs push vs scheduling vs startup vs health check). For that, parse the deployment logs:

**Via CLI:**
```bash
qovery log --application "name" --since 30m
```

**Via API:**
```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[] | .message'
```

Look for timestamped step markers in the logs:
```
[HH:MM:SS] Cloning repository...
[HH:MM:SS] Clone completed
[HH:MM:SS] Building Docker image...
[HH:MM:SS] Step 1/12: FROM node:22-alpine
...
[HH:MM:SS] Build completed
[HH:MM:SS] Pushing image...
[HH:MM:SS] Push completed
[HH:MM:SS] Deploying to Kubernetes...
[HH:MM:SS] Pod scheduled
[HH:MM:SS] Container started
[HH:MM:SS] Readiness probe passed
[HH:MM:SS] Service is running
```

Calculate the time between each step to build the sub-step timeline.

### 1.4 Compare Across Deployments

Analyze the last 5-10 deployments to establish a baseline and detect trends:

```
Deployment History Comparison:
| # | Date       | Total   | Slowest Stage    | Slowest Service | Status    |
|---|------------|---------|------------------|-----------------|-----------|
| 5 | 2025-04-20 | 12m 34s | Backend (8m 42s) | backend (8m 42s)| DEPLOYED  |
| 4 | 2025-04-19 | 11m 22s | Backend (7m 50s) | backend (7m 50s)| DEPLOYED  |
| 3 | 2025-04-18 | 14m 10s | Backend (10m 5s) | backend (10m 5s)| DEPLOYED  |
| 2 | 2025-04-17 | 6m 45s  | Backend (4m 12s) | backend (4m 12s)| DEPLOYED  |
| 1 | 2025-04-15 | 6m 30s  | Backend (4m 05s) | backend (4m 05s)| DEPLOYED  |
```

Questions to answer:
- **Is deployment time getting worse over time?** (growing codebase, more dependencies)
- **Was there a specific deployment where it jumped?** (what commit/change caused it?)
- **Are some services consistently slower than others?** (focus optimization there)
- **Is the total time dominated by one stage or spread across many?** (serial vs parallel issue)

### 1.5 Present the Timeline

Generate a clear timeline visualization for the user:

```
Deployment Pipeline for environment "production" (last deployment: 12m 34s)

Stage: Infrastructure (3m 10s)
  ├── postgres (DATABASE)     3m 10s  [Qovery managed]
  └── redis (HELM)            2m 45s  [Qovery managed]

Stage: Backend (8m 42s)                              ← SLOWEST STAGE
  ├── backend (APPLICATION)   8m 42s  [has build]    ← SLOWEST SERVICE
  │   ├── Git clone:          0m 08s  (1%)
  │   ├── Docker build:       6m 15s  (72%)          ← BOTTLENECK
  │   ├── Image push:         0m 35s  (7%)
  │   ├── Pod scheduling:     0m 18s  (3%)
  │   ├── App startup:        1m 06s  (13%)
  │   └── Health check:       0m 20s  (4%)
  └── worker (APPLICATION)    4m 20s  [has build]

Stage: Frontend (5m 15s)
  └── frontend (APPLICATION)  5m 15s  [has build]

Stage: Jobs (1m 30s)
  └── db-migrate (JOB)        1m 30s  [lifecycle]

Total: 12m 34s (stages run sequentially as configured)
```

This timeline is the foundation for everything that follows. Present it to the user before proposing any changes.

---

