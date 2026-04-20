---
name: qovery-troubleshoot
description: Troubleshoot, diagnose, and fix deployment failures, application crashes, performance issues, connectivity problems, cluster issues, and cost inefficiencies on Qovery. Uses systematic 8-layer diagnosis with MCP Server integration, CLI, and API. Generates runbooks for recurring issues.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: troubleshooting
---

# Qovery Troubleshoot Skill

You are an expert at diagnosing and fixing infrastructure and application issues on Qovery. When a user reports a problem with their Qovery deployment — crashes, build failures, connectivity issues, performance degradation, stuck deployments, high costs, or cluster problems — follow this skill to systematically diagnose the root cause, fix it, and prevent recurrence.

## When to Use This Skill

Use this skill when the user says anything like:
- "My deployment is failing"
- "My app is crashing on Qovery"
- "Can you troubleshoot my Qovery deployment?"
- "Why is my application not working?"
- "My database connection is failing"
- "My app is slow / using too much memory / OOM killed"
- "Help me debug my Qovery environment"
- "My Qovery deployment is stuck"
- "Why is the health check failing?"
- "My build keeps failing"
- "My custom domain isn't working"
- "My Qovery costs are too high"
- "My cluster is not responding"
- "What's broken?"

---

## MCP Server Integration

This skill is designed to work with the **Qovery MCP Server** as the primary diagnostic interface. The MCP Server provides faster, more structured responses than raw CLI/API calls and is optimized for troubleshooting.

**If the Qovery MCP Server is available** (configured in the agent's MCP settings), prefer it for all queries. Use natural language prompts — the MCP Server understands context and returns structured, actionable data.

**If the MCP Server is NOT available**, fall back to the Qovery CLI and REST API. Every diagnostic step in this skill lists all three options: MCP query, CLI command, and API endpoint.

### How to check if MCP Server is available

The MCP Server is available if the agent has it configured at `https://mcp.qovery.com/mcp`. Check by attempting a simple query like "Show me all environments." If it works, prefer MCP for all subsequent queries.

### MCP Server Setup (if not configured)

If the user wants to enable MCP for richer troubleshooting, guide them:

```bash
# Claude Code (OAuth — easiest)
claude mcp add --transport http qovery https://mcp.qovery.com/mcp --callback-port 4242

# Claude Code (API Token)
claude mcp add --transport http qovery https://mcp.qovery.com/mcp --header 'Authorization: Token qov_xxxx'

# OpenAI Codex
# In .codex/config.toml:
# [mcp_servers.qovery]
# url = "https://mcp.qovery.com/mcp"
# http_headers = { "Authorization" = "Token qov_xxxx" }
```

---

## PHASE 1: Context Gathering

Before diagnosing anything, you MUST understand what's deployed and what the user is experiencing.

### 1.1 Authenticate

Use the same authentication flow as the deploy skill:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set
2. Check if CLI is authenticated (`~/.qovery/context.json`)
3. Generate a token via `qovery token` if needed
4. Fall back to JWT from `~/.qovery/context.json` with `Authorization: Bearer`

### 1.2 Get Overview of All Services

Get the status of everything in the user's environment:

**Via MCP (preferred):**
```
"Show me the status of all services in the {environment} environment"
"What services are failing?"
"Is everything healthy?"
"Show failing services"
```

**Via CLI:**
```bash
qovery context set    # Set org/project/environment
qovery service list   # List all services and statuses
qovery status         # Detailed status
```

**Via API:**
```bash
# Get environment statuses (all services at once)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, name: .name, state, service_deployment_status}],
    databases: [.databases[] | {id, name: .name, state}],
    jobs: [.jobs[] | {id, name: .name, state}],
    helms: [.helms[] | {id, name: .name, state}],
    terraforms: [.terraforms[] | {id, name: .name, state}]
  }'
```

### 1.3 Identify the Problem

Ask the user or detect from service statuses:

1. **Which service has the problem?** (name or detect from error states)
2. **What are you experiencing?** Categorize into:
   - **Won't deploy** — build error, deployment error, stuck
   - **Crashes** — starts but dies (CrashLoopBackOff, OOM, segfault)
   - **Connectivity** — can't reach database, other service, or external API
   - **Performance** — slow responses, high latency, resource exhaustion
   - **Custom domain** — DNS, TLS, routing issues
   - **High costs** — want to optimize spending
   - **Cluster** — cluster-level issues (unhealthy, upgrade problems, node pressure)
3. **When did it start?** Was there a recent deployment, config change, or traffic spike?
4. **Did it ever work?** First deployment or regression?

### 1.4 Get Service Details

Once you know which service to diagnose:

**Via MCP:**
```
"Show me the configuration for {service-name}"
"Show deployment history for {service-name}"
"What environment variables are set for {service-name}?"
```

**Via CLI:**
```bash
qovery application env list          # Environment variables
qovery log --application "name"      # Recent logs
```

**Via API:**
```bash
# Service details
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}" | jq

# Deployment history
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/deploymentHistory" | jq '.results[0:5]'

# Environment variables
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/environmentVariable" | jq
```

---

## PHASE 2: Systematic 8-Layer Diagnosis

Work through these layers IN ORDER, from most common to least common. Stop at the first layer that identifies the root cause. Each layer includes what to check, patterns to match, what they mean, and how to fix them.

### Layer 1: Deployment Status & History

**What to check:** Current service state and recent deployment history.

**Via MCP:**
```
"Why is my deployment failing?"
"Show deployment history for {service-name}"
"What happened during the last deployment?"
```

**Via CLI/API:**
```bash
qovery status
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/deploymentHistory" | jq '.results[0]'
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

**Via MCP:**
```
"Show build logs for {service-name}"
"Analyze failed build logs"
"Why is my build failing?"
```

**Via CLI:**
```bash
qovery log --application "name" --since 30m
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

**Via MCP:**
```
"Show error logs from the last hour for {service-name}"
"Why is my app returning 500 errors?"
"Investigate application crashes for {service-name}"
```

**Via CLI:**
```bash
# Get recent logs
qovery log --application "name" --since 1h

# Filter for errors
qovery log --application "name" --since 1h --filter "ERROR"
qovery log --application "name" --since 1h --filter "error"
qovery log --application "name" --since 1h --filter "FATAL"
qovery log --application "name" --since 1h --filter "panic"
qovery log --application "name" --since 1h --filter "Exit"
qovery log --application "name" --since 1h --filter "OOM"
qovery log --application "name" --since 1h --filter "SIGKILL"
```

**Via API:**
```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[-50:] | .[] | .message'
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
   ```bash
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

**Via MCP:**
```
"What environment variables are set for {service-name}?"
"Why isn't my environment variable working?"
"Show configuration for {service-name}"
```

**Via CLI:**
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
   ```bash
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

**Via CLI:**
```bash
qovery status    # Shows current resource usage if available
```

**Via API:**
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

**Via CLI:**
```bash
qovery cluster list
```

**Via API:**
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

## PHASE 3: Common Issue Playbooks

Pre-built diagnostic sequences for the most common problems. Jump directly to the relevant playbook based on the user's description.

### Playbook: App Won't Start

**Triggers:** "my app won't start", "deployment error", "container keeps crashing"

1. Check deployment status (Layer 1) — is it `BUILD_ERROR` or `DEPLOYMENT_ERROR`?
2. If `BUILD_ERROR`: fetch build logs (Layer 2), identify the failing step
3. If `DEPLOYMENT_ERROR`: fetch runtime logs (Layer 3), check for crash reason
4. Check health checks (Layer 4) — is the probe timing out?
5. Check env vars (Layer 5) — is a required variable missing?
6. Check resources (Layer 7) — is the app OOM killed?
7. Apply fix and redeploy

### Playbook: App Is Slow

**Triggers:** "my app is slow", "high latency", "performance issue", "takes forever to respond"

1. Check resource allocation (Layer 7) — CPU/memory too low?
2. Check if autoscaling is hitting max instances
3. Check if app is using external hostnames instead of `_INTERNAL` (Layer 6)
4. Check database performance — port-forward and run `EXPLAIN ANALYZE` on slow queries
5. Check for N+1 queries or missing indexes (ASK USER to review queries)
6. Recommend right-sizing and autoscaling configuration
7. Check if the app is CPU-bound or I/O-bound from logs

### Playbook: Database Connection Fails

**Triggers:** "can't connect to database", "ECONNREFUSED", "connection timeout", "database unreachable"

1. Is the database service running? (Layer 1 — `qovery service list`)
2. Are deployment stages correct? (Layer 6 — DB must deploy before app)
3. Is `DATABASE_URL` set correctly? (Layer 5 — should be an alias, not hardcoded)
4. Is it using `_INTERNAL` hostname? (Layer 5 — `_HOST_INTERNAL`, not `_HOST`)
5. Port-forward to the DB and test locally (Layer 6):
   ```bash
   qovery port-forward --service "postgres" --port 5432:5432
   psql -h localhost -p 5432 -U myuser -d mydatabase
   ```
6. Check for connection pool exhaustion in app logs (Layer 3)
7. Check if DB requires SSL but app doesn't use it (Layer 3 — `sslmode` error)
8. Apply fix and redeploy

### Playbook: Deployment Stuck / Queued

**Triggers:** "deployment stuck", "deployment queued forever", "won't deploy", "deploying for hours"

1. Check environment status — is another deployment in progress?
2. Check deployment stage dependencies — circular wait?
3. Check cluster status (Layer 8) — is the cluster healthy?
4. Check if there are resource constraints (no node capacity)
5. Cancel the stuck deployment and retry:
   ```bash
   # Cancel via API
   curl -s -X POST "https://api.qovery.com/environment/{envId}/cancelDeployment" \
     -H "Authorization: Token $QOVERY_API_TOKEN"
   # Or via MCP: "Cancel the ongoing deployment"
   ```
6. Retry the deployment
7. If it's still stuck: check Qovery Console for more details or contact support

### Playbook: Custom Domain Not Working

**Triggers:** "domain not working", "SSL error", "certificate issue", "custom domain 404"

1. Check if the custom domain is registered in Qovery:
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/application/{appId}/customDomain" | jq
   ```
2. Check DNS CNAME record:
   ```bash
   dig app.example.com CNAME
   # Must point to the Qovery-generated domain
   ```
3. Check if the service is publicly accessible (port config has `publicly_accessible: true`)
4. Check TLS certificate — Qovery uses Let's Encrypt, may take a few minutes to provision
5. Check if the protocol is `HTTP` (not `TCP`/`UDP`) for web traffic
6. If DNS is correct but still not working: wait 5-10 minutes for DNS propagation

### Playbook: Terraform Service Failing

**Triggers:** "terraform error", "terraform plan failed", "terraform service stuck"

1. Fetch Terraform execution logs via MCP or API
2. Common causes:
   - **Variable errors**: Missing or wrong `variables` in the Terraform service config
   - **Permission errors**: Cloud credentials don't have required IAM permissions
   - **State lock**: Previous run didn't release the state lock
   - **Resource conflicts**: Resource already exists outside Terraform
3. Show the Terraform error output to the user — **ASK before making changes**
4. Terraform code changes always require user approval

### Playbook: Helm Chart Failing

**Triggers:** "helm install failed", "chart error", "helm timeout"

1. Fetch Helm install/upgrade logs via MCP or API
2. Common causes:
   - **Invalid values**: YAML syntax error in `values_override`
   - **Missing dependencies**: Chart requires a dependency that isn't deployed
   - **Timeout**: Chart takes longer than `timeout_sec` to deploy
   - **Resource conflicts**: Kubernetes resources already exist
3. If timeout: increase `timeout_sec` — **auto-fix**
4. If values error: fix `values_override` — **auto-fix for typos, ASK for logic changes**
5. Check `qovery.env.*` macro references — are the referenced variables set?

### Playbook: High Costs / Cost Optimization

**Triggers:** "too expensive", "reduce costs", "cost optimization", "save money"

**Via MCP (preferred — provides structured cost analysis):**
```
"Show me monthly spending"
"Find underutilized resources"
"Which environments are costing the most?"
"Show me idle services"
"Stop all non-production environments for the weekend"
```

**Manual diagnosis:**

1. **List all services with resource allocations:**
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/environment/{envId}/statuses" | jq
   ```

2. **Identify over-provisioned services:**
   - CPU allocation much higher than actual usage
   - Memory allocation much higher than peak usage
   - Recommend right-sizing — **auto-fix**

3. **Identify idle/unused services:**
   - Services with no traffic or no recent deployments
   - Development/staging environments running 24/7
   - Recommend stopping during off-hours — **auto-fix via MCP**

4. **Database mode optimization:**
   - Production using container-mode database? Consider managed mode for reliability
   - Dev/test using managed-mode database? Switch to container mode to save costs

5. **Spot instances:**
   - For non-critical workloads, consider enabling spot instances on the cluster

6. **Environment lifecycle:**
   - Stop all non-production environments overnight/weekends:
     ```
     MCP: "Stop all development environments overnight"
     ```

### Playbook: OOM / Resource Exhaustion

**Triggers:** "out of memory", "OOM killed", "crash loop", "exit code 137"

1. Confirm OOM from logs (Layer 3): `OOMKilled`, `exit code 137`, `SIGKILL`
2. Check current memory allocation:
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/application/{appId}" | jq '.memory'
   ```
3. Increase memory by 50-100% — **auto-fix**:
   - 512MB -> 1024MB
   - 1024MB -> 2048MB
4. If it keeps happening: the app likely has a memory leak — **ASK USER** to investigate
5. For Node.js: suggest `--max-old-space-size` flag — **ASK USER**
6. For JVM: suggest `-Xmx` and `-Xms` JVM options — **ASK USER**
7. Redeploy and monitor

### Playbook: Build Failing

**Triggers:** "build error", "docker build failed", "can't build"

1. Fetch build logs (Layer 2)
2. Check Dockerfile path — is `dockerfile_path` correct? — **auto-fix if wrong**
3. Check `root_path` for monorepos — **auto-fix if wrong**
4. Check for dependency errors — **ASK USER** for code/package changes
5. Check for disk space issues — optimize Dockerfile layers — **auto-fix**
6. Check base image availability — **auto-fix if base image tag is wrong**
7. Redeploy

---

## PHASE 4: Fix & Redeploy

### CRITICAL RULE: What You Can and Cannot Fix Automatically

**AUTO-FIX ALLOWED (no permission needed):**
- Qovery service configuration: port numbers, health check paths/ports/delays, memory/CPU limits, deployment stage ordering, environment variables (non-secret), Dockerfile path, git branch, root_path, instance counts, autoscaling settings
- Resource right-sizing (increase memory/CPU)
- Deployment stage reordering
- Health check type switching (HTTP to TCP)
- Stopping/starting services for cost optimization
- Canceling stuck deployments

**MUST ASK USER BEFORE FIXING:**
- Any changes to application source code
- Any changes to Dockerfiles
- Adding, changing, or removing secrets
- Database schema changes
- Terraform module code changes
- Helm values changes that affect application behavior
- Any change where you are not 100% certain it will fix the issue

**WHEN ASKING, always:**
1. Explain the error clearly (quote the relevant log lines)
2. Explain what you think the root cause is
3. Show the exact change you propose
4. Wait for explicit approval before making the change

### Redeploy After Fix

```bash
# Redeploy a single service
curl -s -X POST "https://api.qovery.com/application/{appId}/restart" \
  -H "Authorization: Token $QOVERY_API_TOKEN"

# Or redeploy the whole environment
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"

# Or via CLI
qovery application redeploy --application "name"

# Or via MCP
# "Redeploy the backend application"
# "Restart the API service"
```

### Watch and Verify

After redeploying, watch the deployment (same as Phase 1.2). If it fails again, loop back to Phase 2 with the new error. Maximum 3 auto-fix attempts per service before escalating to the user with a full summary of what was tried.

---

## PHASE 5: Verification

After the fix is applied and the service is redeployed:

1. **Check service status:**
   ```
   MCP: "Is {service-name} healthy now?"
   CLI: qovery status
   ```

2. **Check logs for healthy operation:**
   ```bash
   qovery log --application "name" --tail 20
   ```

3. **Test the endpoint:**
   ```bash
   # Via port-forward (for internal services)
   qovery port-forward --service "name" --port 8080:8080
   curl http://localhost:8080/health

   # Via public URL (for public services)
   curl https://{app-url}/health
   ```

4. **Report to the user:**
   - What the problem was
   - What the root cause was
   - What was fixed
   - Whether it's working now
   - Preventive recommendations (Phase 7)

---

## PHASE 6: Runbook Generation

After resolving an issue, offer to create a runbook for future reference:

> "I've fixed the issue. Would you like me to create a runbook documenting what happened and how it was resolved? This helps if the same issue occurs again."

If the user agrees:

### Create the Runbook

1. **Create the directory** (if it doesn't exist):
   ```bash
   mkdir -p .qovery/runbooks
   ```

2. **Generate a markdown file** with the following structure:

   ```markdown
   # Runbook: {Issue Title}

   **Date:** {YYYY-MM-DD}
   **Service:** {service-name}
   **Environment:** {environment-name}
   **Severity:** {Critical / High / Medium / Low}
   **Time to Resolve:** {Xm}

   ## Symptoms

   {What the user reported and what the agent observed}

   ## Diagnosis

   **Layer:** {Which diagnostic layer identified the issue}
   **Commands used:**
   - {MCP query or CLI command 1}
   - {MCP query or CLI command 2}

   ## Root Cause

   {Clear explanation of why the issue occurred}

   ## Resolution

   {Exact steps taken to fix the issue, including commands}

   ## Prevention

   {How to prevent this from happening again}

   ## Related Runbooks

   {Links to any related runbooks if applicable}
   ```

3. **File naming**: `YYYY-MM-DD-{issue-slug}.md`
   - Example: `2025-04-20-oom-kill-backend.md`
   - Example: `2025-04-20-db-connection-refused.md`
   - Example: `2025-04-20-health-check-timeout.md`

4. **Ask the user** if they want to commit the runbook to git:
   ```bash
   git add .qovery/runbooks/
   git commit -m "docs: add runbook for {issue-slug}"
   ```

### Reference Past Runbooks

When a new issue occurs, check if there are existing runbooks in `.qovery/runbooks/` that match the symptoms. If a relevant runbook exists, reference it — the fix might be the same or similar.

---

## PHASE 7: Prevention & Recommendations

After fixing an issue, suggest preventive measures tailored to what went wrong:

### After Build Errors
- Pin dependency versions in lockfiles (package-lock.json, go.sum, requirements.txt)
- Use multi-stage Docker builds to reduce build context size
- Enable auto-deploy on Git push so build issues are caught early

### After Health Check Failures
- Add a dedicated `/health` endpoint to your application
- Set `initial_delay_seconds` based on actual startup time (measure it)
- Use readiness probes in addition to liveness probes
- For JVM apps: use Spring Boot Actuator's `/actuator/health`

### After OOM Kills
- Right-size memory based on observed peak usage + 20% buffer
- Enable autoscaling (`min_running_instances < max_running_instances`)
- For Node.js: set `--max-old-space-size` to 75% of container memory
- For JVM: set `-Xmx` to 75% of container memory
- Consider profiling for memory leaks

### After Connectivity Issues
- Always use `_INTERNAL` hostnames for in-cluster communication
- Use environment variable aliases for database connections (not hardcoded)
- Configure deployment stages so dependencies start first
- Use `qovery port-forward` for local debugging

### After Cost Issues
- Stop non-production environments during off-hours (MCP can automate this)
- Use container-mode databases for dev/test (not managed)
- Right-size resources based on actual usage
- Enable spot instances for non-critical workloads
- Clean up unused environments regularly

### After Cluster Issues
- Keep Kubernetes version up to date
- Monitor cluster capacity and node pressure
- Ensure cloud credentials are valid and have sufficient permissions
- Set up alerts for cluster-level issues (via Qovery Console)

### General Best Practices
- Use the [Qovery Deploy Skill](https://github.com/Qovery/qovery-skills) for new deployments — it sets up health checks, deployment stages, and env var aliases correctly from the start
- Use the [Qovery MCP Server](https://mcp.qovery.com/mcp) for day-to-day monitoring and management
- Use Terraform for production infrastructure (reproducible, version-controlled)
- Commit your `qovery.tf` and `.qovery/runbooks/` to git

---

## Quick Reference

### MCP Queries by Category

**Status & Health:**
```
"Is everything healthy?"
"Show failing services"
"What's the status of all services?"
"Is the cluster healthy?"
```

**Logs & Diagnostics:**
```
"Show error logs from the last hour for {service}"
"Why is my deployment failing?"
"Analyze failed build logs for {service}"
"Why is the health check failing?"
```

**Connectivity:**
```
"Why can't my app connect to the database?"
"Is the database running?"
"Show database connection info"
```

**Resources:**
```
"Show CPU usage across all services"
"Why is my service out of memory?"
"Find over-provisioned services"
```

**Cost:**
```
"Show me monthly spending"
"Find underutilized resources"
"Stop all non-production environments"
```

**Actions:**
```
"Restart the API service"
"Redeploy the backend"
"Cancel the ongoing deployment"
"Scale the API to 5 replicas"
"Rollback the API to previous version"
```

### CLI Commands for Diagnosis

```bash
# Context and status
qovery context set
qovery service list
qovery status
qovery status --watch

# Logs
qovery log --application "name" --since 1h
qovery log --application "name" --filter "ERROR"

# Environment variables
qovery application env list
qovery environment env list

# Connectivity testing
qovery port-forward --service "name" --port 8080:8080
qovery port-forward --service "postgres" --port 5432:5432
qovery shell --service "name"

# Cluster
qovery cluster list
```

### API Endpoints for Diagnosis

```bash
# Base URL: https://api.qovery.com
# Auth: Authorization: Token $QOVERY_API_TOKEN

GET /environment/{envId}/statuses              # All service statuses
GET /application/{appId}                        # Service config
GET /application/{appId}/deploymentHistory      # Deployment history
GET /application/{appId}/log                    # Application logs
GET /application/{appId}/environmentVariable    # Environment variables
GET /application/{appId}/customDomain           # Custom domains
GET /organization/{orgId}/cluster               # Cluster list and status

PUT /application/{appId}                        # Update service config (fix)
POST /application/{appId}/restart               # Restart service
POST /environment/{envId}/deploy                # Redeploy environment
POST /environment/{envId}/cancelDeployment      # Cancel stuck deployment
```

---

## Reference Links

- **Qovery Documentation**: https://www.qovery.com/docs/getting-started/introduction
- **Qovery Console**: https://console.qovery.com
- **MCP Server**: https://mcp.qovery.com/mcp
- **MCP Server Docs**: https://www.qovery.com/docs/copilot/mcp-server
- **Copilot Troubleshooting Capabilities**: https://www.qovery.com/docs/copilot/capabilities/troubleshooting
- **Copilot Optimization Capabilities**: https://www.qovery.com/docs/copilot/capabilities/optimization
- **CLI Reference**: https://www.qovery.com/docs/cli/commands/overview
- **API Reference**: https://www.qovery.com/docs/api-reference/introduction
- **Qovery Deploy Skill**: https://github.com/Qovery/qovery-skills (for deploying new applications)
