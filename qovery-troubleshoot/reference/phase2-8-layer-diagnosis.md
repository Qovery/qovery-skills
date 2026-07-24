## PHASE 2: Systematic 8-Layer Diagnosis

Work through these layers IN ORDER, from most common to least common. Stop at the first layer that identifies the root cause. Each layer includes what to check, patterns to match, what they mean, and how to fix them.

### Layer 1: Deployment Status & History

**What to check:** Current service state and recent deployment history.

**Via MCP tools (preferred):**
```
# Current state of every service (find the failing one and its state):
list_services(environment_id = "{envId}")

# Diagnose the failure + read deployment history (rich errors, stages, hints):
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Why is service {serviceId} failing to deploy? Show its recent deployment history and the error details, stages, and hints from the last deployment.")
```
The Copilot's TROUBLESHOOT capability replaces the v2 deployment-logs `curl` (`/environment/{envId}/logs`) — it returns the same error tags, stages, and hints. Its READ capability replaces `/deploymentHistory`.

**Via CLI/API (fallback):**
```bash
qovery status
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/deploymentHistory" | jq '.results[0]'

# Environment deployment logs v2 — rich details with error messages, stages, and hints:
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{environmentId}/logs" | jq '[.[] | select(.error != null) | {timestamp, error_tag: .error.tag, message: .error.user_log_message, hint: .error.hint_message, stage: .details.stage.step}]'
```

**What to look for:**

| State | Meaning | Next Step |
|---|---|---|
| `DEPLOYED` / `RUNNING` | Service is running — problem is runtime, not deployment | Go to Layer 3 (Runtime Logs) |
| `BUILD_ERROR` | Docker build failed | Go to Layer 2 (Build Logs) |
| `DEPLOYMENT_ERROR` | Image built but container won't start or health check fails | Go to Layer 3 + Layer 4 |
| `QUEUED` / `DEPLOYING` for > 30 min | Deployment stuck | Go to Playbook: "Deployment Stuck" |
| `STOP_ERROR` / `RESTART_ERROR` | Service can't stop or restart cleanly | Check for hanging processes, increase termination grace period |

**Check what changed:** Compare the last successful deployment to the current failing one. Look for:
- Code changes (new commit)
- Config changes (env var added/removed/changed)
- Resource changes (CPU/memory adjusted)
- Dockerfile changes

### Layer 2: Build Logs

**When to check:** Service state is `BUILD_ERROR`.

**Via MCP tools (preferred):**
```
# Fetch the failing deployment's logs for any service type:
get_service_logs(environment_id = "{envId}", service_id = "{serviceId}", deployment_id = "{deploymentId}")

# Or have the Copilot analyze the build failure directly:
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Analyze the failed build logs for service {serviceId} and tell me which step failed and why.")
```
`get_service_logs` works for applications, containers, jobs, and helms — replacing both the per-type `curl` log endpoints and the `qovery log` CLI, including the job/helm cases the API cannot serve.

**Via CLI (fallback):**
```bash
# Use the flag matching the service type (--application, --container, --job, or --service):
qovery log --application "name" --since 30m
qovery log --container "name" --since 30m
qovery log --job "name" --since 30m
qovery log --service "name" --since 30m     # Generic — works for any service type
```

**Via API (fallback):**
```bash
# Application build logs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{applicationId}/log" | jq '.results[] | .message'
# Container build logs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/container/{containerId}/log" | jq '.results[] | .message'
# NOTE: For jobs/helms, use `get_service_logs` (MCP) or `qovery log` CLI — no API log endpoint exists for these service types.
```

**Error patterns and fixes:**

| Log Pattern | Root Cause | Fix | Auto-Fix? |
|---|---|---|---|
| `Dockerfile not found` / `Cannot locate specified Dockerfile` | Wrong `dockerfile_path` in Qovery config | Update `dockerfile_path` via API | YES |
| `COPY failed: file not found in build context` | File referenced in COPY doesn't exist, or wrong `root_path` | Fix `root_path` or Dockerfile COPY path | YES if Qovery config, ASK if Dockerfile |
| `npm ERR! Could not resolve dependency` | NPM dependency conflict | ASK USER — may need `--legacy-peer-deps` or dependency fix | ASK |
| `pip install ERROR: No matching distribution` | Python package not found or version conflict | ASK USER — check requirements.txt | ASK |
| `go: module ... not found` | Go module resolution failure | ASK USER — check go.mod | ASK |
| `javac: error:` / `COMPILATION ERROR` | Java compilation error | ASK USER — code fix needed | ASK |
| `Error: Cannot find module` | Missing Node.js module | ASK USER — check package.json | ASK |
| `manifest unknown` / `not found` | Docker base image tag doesn't exist | Update base image tag in Dockerfile | ASK |
| `no space left on device` | Build disk too small or too many layers | Optimize Dockerfile layers, increase disk | YES (optimize Dockerfile) |
| `RUN npm run build` exits non-zero | TypeScript/build errors in user code | ASK USER — show the build errors | ASK |

### Layer 3: Runtime Logs

**When to check:** Service was deployed but is crashing, returning errors, or misbehaving.

**Via MCP tools (preferred):**
```
# Application/runtime logs for any service type (isolate a crashing pod with pod_name):
get_service_logs(environment_id = "{envId}", service_id = "{serviceId}")

# Pod-level health — is it CrashLoopBackOff, Pending, OOMKilled? Scope to the service:
get_cluster_status(cluster_id = "{clusterId}", category = "pod",
  object_filter = { type = "service", environment_id = "{envId}", service_id = "{serviceId}" })

# Kubernetes events (OOMKilled, SIGKILL, evictions, image pull errors) over a time window:
get_cluster_events(cluster_id = "{clusterId}",
  from_datetime = "{start ISO-8601}", to_datetime = "{end ISO-8601}",
  pod_filter = { type = "service_id", service_id = "{serviceId}" })
```
`get_service_logs` replaces the per-type log `curl` endpoints (and covers job/database/helm). For crash/OOM symptoms, `get_cluster_status` (pod conditions) and `get_cluster_events` (the actual `OOMKilled`/`SIGKILL`/`FailedScheduling` events) give the Kubernetes-level signal the REST API can't. Chunk event queries into ≤30-min windows.

**Via CLI (fallback):**
```bash
# Get recent logs — use the flag matching the service type:
qovery log --application "name" --since 1h    # Application
qovery log --container "name" --since 1h      # Container
qovery log --database "name" --since 1h       # Database
qovery log --job "name" --since 1h            # Job (cronjob/lifecycle)
qovery log --service "name" --since 1h        # Generic — works for any service type

# Stream logs in real-time (useful during active debugging):
qovery log --service "name" --follow

# Filter for errors (combine with any service flag above):
qovery log --service "name" --since 1h --filter "ERROR"
qovery log --service "name" --since 1h --filter "FATAL"
qovery log --service "name" --since 1h --filter "panic"
qovery log --service "name" --since 1h --filter "Exit"
qovery log --service "name" --since 1h --filter "OOM"
qovery log --service "name" --since 1h --filter "SIGKILL"

# Get last N lines:
qovery log --service "name" --tail 100

# Time-range query:
qovery log --service "name" --from "2024-01-01T00:00:00Z" --to "2024-01-01T23:59:59Z"
```

**Via API (fallback):**
```bash
# Application logs (last 1000 lines)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{applicationId}/log" | jq '.results[-50:] | .[] | {created_at, message, pod_name}'

# Container logs (last 1000 lines)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/container/{containerId}/log" | jq '.results[-50:] | .[] | {created_at, message, pod_name}'

# NOTE: Job, Helm, and Database log API endpoints do NOT exist.
# Use `get_service_logs` (MCP), or `qovery log --job` / `qovery log --database` for these service types.

# Environment deployment logs v2 (useful for deployment-related runtime errors):
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{environmentId}/logs" | jq '[.[] | select(.error != null) | {timestamp, error: .error.user_log_message, hint: .error.hint_message, stage: .details.stage.step}]'
```

**Error patterns and fixes:**

| Log Pattern | Category | Root Cause | Fix | Auto-Fix? |
|---|---|---|---|---|
| `SIGKILL` / `exit code 137` / `OOMKilled` | Memory | App exceeds memory limit | Increase memory allocation | YES |
| `CrashLoopBackOff` | Crash | App crashes repeatedly on startup | Check startup error in logs, fix root cause | DEPENDS |
| `JavaScript heap out of memory` | Memory | Node.js exceeds V8 heap limit | Increase memory, add `--max-old-space-size` | YES (memory) / ASK (flag) |
| `MemoryError` / `OutOfMemoryError` | Memory | Python/Java out of memory | Increase memory allocation | YES |
| `ECONNREFUSED` / `connection refused` | Connectivity | Target service not running or wrong host/port | Check DB running, check env vars, check deployment stages | YES |
| `ETIMEDOUT` / `connect ETIMEDOUT` | Connectivity | Network timeout to target service | Check if using `_INTERNAL` hostname, check firewall | YES |
| `DNS resolution failed` / `ENOTFOUND` | Connectivity | Wrong hostname or DNS issue | Fix hostname env var | YES |
| `EADDRINUSE` / `address already in use` | Port | Port conflict | Check PORT env var matches Qovery config | YES |
| `bind: permission denied` | Port | Port < 1024 without root | Use port >= 1024, Dockerfile uses non-root user | ASK |
| `401 Unauthorized` / `403 Forbidden` | Auth | Invalid or expired credentials | ASK USER — check API keys/tokens | ASK |
| `relation "..." does not exist` | Database | Missing tables, migration not run | ASK USER — run migrations | ASK |
| `too many connections` | Database | Connection pool exhaustion | Add connection pooling, increase pool size | ASK |
| `deadlock detected` | Database | Concurrent transaction conflict | ASK USER — application logic issue | ASK |
| `SSL/TLS required` / `sslmode` | Database | DB requires SSL but app doesn't use it | Add `?sslmode=require` to connection string (interpolation) | YES |
| `ENOENT` / `no such file or directory` | File | Missing file at runtime | ASK USER — check file paths | ASK |
| `exec format error` | Architecture | ARM image on AMD64 or vice versa | Fix Dockerfile build architecture | ASK |
| `SIGTERM` then crash | Graceful shutdown | App doesn't handle SIGTERM | ASK USER — add signal handler | ASK |

### Layer 4: Health Checks

**When to check:** Container starts but deployment fails due to health check timeout.

**Via MCP:**
```
"Why is the health check failing for {service-name}?"
"Check service health status for {service-name}"
```

**Diagnosis steps:**

1. **Get current health check config:**
   ```
   # Preferred (MCP):
   devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
     message = "Show the health check configuration (liveness and readiness probes) for service {serviceId}.")
   ```
   ```bash
   # Fallback (API):
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/application/{appId}" | jq '.healthchecks'
   ```

2. **Check if port matches:**
   - Health check port must match the app's actual listen port
   - Look in logs for: `listening on port XXXX` / `Server started on XXXX`
   - If mismatch: update health check port — **auto-fix**

3. **Check if HTTP path exists:**
   - Health check path (e.g., `/health`) must return 200 OK
   - If app doesn't have a health endpoint: switch to TCP probe — **auto-fix**
   - If path is wrong (e.g., `/health` vs `/api/health`): update path — **auto-fix**

4. **Check startup time vs initial delay:**
   - If app takes 60s to start but `initial_delay_seconds` is 30: increase it — **auto-fix**
   - For JVM apps (Spring Boot): 60-120s is typical
   - For Node.js/Go/Python: 5-30s is typical

5. **Test locally via port-forward:**
   ```bash
   qovery port-forward --service "name" --port 8080:8080
   # In another terminal:
   curl http://localhost:8080/health
   ```

**Fixes:**

**Via MCP tools (preferred)** — the Copilot's WRITE capability updates health checks and ports directly (reference the service by UUID):
```
# Fix port mismatch (auto-fix)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Set the port of service {serviceId} to internal 3000, external 443, protocol HTTP, publicly accessible.")

# Switch to a TCP probe on port 3000 (auto-fix — when app has no /health endpoint)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Change the liveness probe of service {serviceId} to a TCP probe on port 3000 with a 30s initial delay.")

# Increase initial delay to 120s (auto-fix — when app is slow to start)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Set the HTTP liveness probe of service {serviceId} to path /health on port 8080 with initial_delay_seconds = 120.")
```

**Via API (fallback):**
```bash
# Fix port mismatch (auto-fix)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ports": [{"internal_port": 3000, "external_port": 443, "protocol": "HTTP", "publicly_accessible": true, "name": "http"}]}'

# Switch to TCP probe (auto-fix — when app has no /health endpoint)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "healthchecks": {
      "liveness_probe": {
        "type": {"tcp": {"port": 3000}},
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    }
  }'

# Increase initial delay (auto-fix — when app is slow to start)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "healthchecks": {
      "liveness_probe": {
        "type": {"http": {"port": 8080, "scheme": "HTTP", "path": "/health"}},
        "initial_delay_seconds": 120,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    }
  }'
```

### Layer 5: Environment Variables & Secrets

**When to check:** App starts but crashes due to missing config, or connects to wrong services.

**Via MCP tools (preferred):**
```
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "List the environment variables and secrets set for service {serviceId}, including their scope and whether each is an alias or interpolated value.")
```

**Via CLI (fallback):**
```bash
qovery application env list
```

**Diagnosis steps:**

1. **Check for missing variables** — Look in the runtime logs for patterns like:
   - `Error: XYZ is not defined`
   - `KeyError: 'XYZ'`
   - `env var XYZ required`
   - `undefined` (when accessing a config value)

2. **Check database connection variables:**
   - Is `DATABASE_URL` (or equivalent) set?
   - Is it an alias pointing to `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL`? (preferred)
   - Or is it using interpolation `{{QOVERY_DATABASE_...}}`? (OK for composed values with params)
   - Is it hardcoded? (bad — will break on redeploy)

3. **Check for scope issues:**
   - Variable set at project scope but being overridden at environment/service scope?
   - Variable set at environment scope but the service expects it at service scope?

4. **Check for empty secrets:**
   - Secrets show as `***` in the UI/API but might have been set to an empty string
   - Ask the user to verify the secret value

5. **Check `_INTERNAL` vs external hostnames:**
   - Services communicating within the same cluster MUST use `_HOST_INTERNAL`
   - External hostnames route through the internet — adds latency and may fail if not publicly accessible

**Fixes:**

**Via MCP tools (preferred)** — the Copilot's WRITE capability manages environment variables:
```
# Add a missing non-secret variable (auto-fix)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Add environment variable PORT=8080 to service {serviceId}.")

# Create an alias for the database connection (auto-fix)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "On service {serviceId}, create an env var DATABASE_URL as an alias of the variable {sourceVariableId}.")

# For missing secrets — ASK USER for the value first, then:
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Add secret API_KEY to service {serviceId}.", instructions = "The secret value was provided by the user.")
```
> Adding/changing secrets requires user approval per Phase 4 — ask before writing.

**Via API (fallback):**
```bash
# Add a missing non-secret variable (auto-fix)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "PORT", "value": "8080"}'

# Create an alias for database connection (auto-fix)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "alias_parent_id": "{sourceVariableId}"}'

# For missing secrets — ASK USER for the value, then:
curl -s -X POST "https://api.qovery.com/application/{appId}/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "user-provided-value"}'
```

### Layer 6: Network & Connectivity

**When to check:** App starts but can't communicate with other services or databases.

**Via MCP:**
```
"Why can't my app connect to the database?"
"Is the database running?"
"Debug the service-to-service connection"
"Check if all services are healthy"
```

**Diagnosis steps:**

1. **Is the target service running?**
   ```
   # Preferred (MCP) — states of every service in the environment:
   list_services(environment_id = "{envId}")
   ```
   ```bash
   # Fallback (CLI):
   qovery service list
   ```
   If the database or dependent service is not running, that's the problem.

2. **Are deployment stages correct?**
   - The database MUST be in an earlier deployment stage than the application
   - If they're in the same stage, the app might start before the DB is ready
   - Fix: Move the DB to an earlier stage — **auto-fix**

3. **Is the app using internal hostnames?**
   - `QOVERY_DATABASE_..._HOST_INTERNAL` for databases
   - `QOVERY_APPLICATION_..._HOST_INTERNAL` for other services
   - If using external hostnames, traffic routes through the internet unnecessarily

4. **Port-forward to test connectivity directly:**
   ```bash
   # Test database connectivity
   qovery port-forward --service "postgres" --port 5432:5432
   psql -h localhost -p 5432 -U myuser -d mydatabase

   # Test service connectivity
   qovery port-forward --service "backend" --port 8080:8080
   curl http://localhost:8080/health
   ```

5. **Is the target service publicly accessible when it shouldn't be?**
   - Databases should NEVER be publicly accessible — always use internal networking
   - Backend APIs can be internal-only if only the frontend needs to reach them

6. **Custom domain DNS:**
   ```bash
   # Check DNS resolution
   dig app.example.com CNAME
   # Should point to the Qovery-generated domain
   ```

**Fixes:**

**Via MCP tools (preferred)** — ask the Copilot to reorder deployment stages so the dependency deploys first:
```
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "In environment {envId}, order the deployment stages so the database service {dbServiceId} deploys before the application {serviceId}.")
```

**Via API (fallback):**
```bash
# Fix deployment stage ordering (auto-fix)
curl -s -X PUT "https://api.qovery.com/deploymentStage/{stageId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"is_after": "{dbStageId}"}'
```

### Layer 7: Resources & Performance

**When to check:** App is slow, OOM killed, or hitting resource limits.

**Via MCP:**
```
"Why is my service out of memory?"
"Show CPU usage across all services"
"Show memory usage for {service-name}"
"Find over-provisioned services"
"Optimize resource allocation for {service-name}"
```

**Via MCP tools (preferred):**
```
# Current CPU/memory/instance allocation:
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Show the CPU, memory, and min/max instance configuration for service {serviceId}.")

# Confirm OOM from Kubernetes events rather than guessing from allocation:
get_cluster_events(cluster_id = "{clusterId}",
  from_datetime = "{start ISO-8601}", to_datetime = "{end ISO-8601}",
  pod_filter = { type = "service_id", service_id = "{serviceId}" })
```

**Via CLI (fallback):**
```bash
qovery status    # Shows current resource usage if available
```

**Via API (fallback):**
```bash
# Get service configuration (cpu, memory, instances)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}" | jq '{cpu, memory, min_running_instances, max_running_instances}'
```

**Diagnosis steps:**

1. **Check if OOM killed:**
   - Logs show `OOMKilled`, `exit code 137`, `SIGKILL`
   - Current memory allocation is too low for the app's needs
   - Fix: Increase memory — **auto-fix**

2. **Check if CPU starved:**
   - App is slow but not crashing
   - CPU allocation might be too low (e.g., 250m for a CPU-intensive app)
   - Fix: Increase CPU — **auto-fix**

3. **Check autoscaling:**
   - Is `min_running_instances == max_running_instances`? (no autoscaling)
   - If max is hit and app is still slow: increase max instances — **auto-fix**
   - If no autoscaling: recommend enabling it (set max > min)

4. **Right-sizing recommendations:**
   - For most web apps: 500m CPU, 512MB memory is a reasonable starting point
   - For JVM apps: 1000m CPU, 1024-2048MB memory
   - For Go apps: 250m CPU, 256MB memory (Go is very efficient)
   - For ML/GPU workloads: size based on model requirements

**Fixes:**

**Via MCP tools (preferred)** — the Copilot's WRITE capability updates resources and autoscaling:
```
# Increase memory to 1024 MB (auto-fix)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Set the memory of service {serviceId} to 1024 MB.")

# Increase CPU to 1000 millicores (auto-fix)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Set the CPU of service {serviceId} to 1000m.")

# Enable autoscaling: min 2, max 10 instances (auto-fix)
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Set service {serviceId} to autoscale between 2 and 10 instances.")
```

**Via API (fallback):**
```bash
# Increase memory (auto-fix)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"memory": 1024}'

# Increase CPU (auto-fix)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cpu": 1000}'

# Enable autoscaling (auto-fix)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 2, "max_running_instances": 10}'
```

### Layer 8: Cluster & Infrastructure

**When to check:** Multiple services failing simultaneously, or cluster-level symptoms.

**Via MCP:**
```
"What's the status of the production cluster?"
"Is the cluster healthy?"
"Show cluster resource usage"
"How many nodes are in the cluster?"
"What version of Kubernetes is running?"
```

**Via MCP tools (preferred):**
```
# Node health, pressure, and capacity (also surfaces Karpenter NodePools):
get_cluster_status(cluster_id = "{clusterId}", category = "node")

# Cluster-wide events over a window (FailedScheduling, node NotReady, evictions).
# Chunk into ≤30-min windows to stay under the 5000-event cap; omit pod_filter for all events:
get_cluster_events(cluster_id = "{clusterId}",
  from_datetime = "{start ISO-8601}", to_datetime = "{end ISO-8601}")

# Cluster-level settings / status narrative:
devops_copilot(organization_id = "{orgId}",
  message = "Show the status, advanced settings, and security settings for cluster {clusterId}.")
```
`get_cluster_status` and `get_cluster_events` give the Kubernetes-level node and scheduling signal that the `/cluster` REST endpoint doesn't expose.

**Via CLI (fallback):**
```bash
qovery cluster list
```

**Via API (fallback):**
```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, status, cloud_provider, region, version}'
```

**Diagnosis steps:**

1. **Cluster status:**
   - `DEPLOYED` / `READY` — cluster is healthy, problem is elsewhere
   - `DEPLOYING` / `UPGRADING` — cluster is being modified, services may be disrupted temporarily
   - `ERROR` / `DEGRADED` — cluster-level problem

2. **Node pressure:**
   - If pods can't schedule: cluster might be at max capacity
   - Check if Karpenter (AWS) or cluster autoscaler can provision more nodes
   - May need to adjust instance types or increase max nodes

3. **Cloud provider issues:**
   - Region outages (check cloud provider status pages)
   - API quota limits (e.g., AWS EC2 instance limits)
   - IAM/permission issues (credentials expired or revoked)

4. **Kubernetes version:**
   - Check if the cluster is running a supported Kubernetes version
   - Outdated versions may have known issues

**Fixes:**
- Cluster-level fixes usually require Console access or contacting Qovery support
- The agent should report the cluster status and recommend next steps
- If the cluster is simply at capacity, recommend scaling up max nodes or adjusting instance types

---

