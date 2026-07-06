## PHASE 1: Context Gathering

Before diagnosing anything, you MUST understand what's deployed and what the user is experiencing.

### 1.1 Authenticate

**If you are using the Qovery MCP Server, skip this step** — the MCP Server authenticates internally (OAuth or its configured token), so no token needs to flow through the shell. Authentication below is only needed for the CLI/API fallback tiers.

Use the same authentication flow as the deploy skill:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set
2. Try `qovery auth token --print` — if the CLI is authenticated, this outputs a valid token (auto-refreshed). Use with `Authorization: Bearer $(qovery auth token --print)`.
3. Generate a named API token if needed: `qovery token create --name "troubleshoot-skill" --duration 24h`
4. If the CLI is not authenticated, run `qovery auth` for interactive login, then use step 2.

### 1.2 Get Overview of All Services

Get the status of everything in the user's environment. If you don't already have the environment ID (e.g. from a Console URL), resolve it first by chaining `list_organizations` → `list_projects` → `list_environments`.

**Via MCP tools (preferred):**
```
list_services(environment_id = "{envId}")
```
Returns every service (application, container, job, database, helm, terraform) with its current state — this single call replaces the `/environment/{envId}/statuses` API request. To triage, filter the result for services not in a healthy/running state.

For a narrative status ("what's failing and why"), you can also ask the Copilot:
```
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Show the status of every service in environment {envId} and list which ones are failing.")
```

**Via CLI (fallback):**
```bash
qovery context set    # Set org/project/environment
qovery service list   # List all services and statuses
qovery status         # Detailed status
```

**Via API (fallback):**
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

**Shortcut:** If the user provided a Qovery Console URL with a service ID, use the extracted IDs to skip directly to fetching the service status and logs. The URL page suffix (`service-logs`, `deployment-logs`, etc.) hints at the problem area — use it to focus your initial investigation. You can skip question 1 below entirely if the service ID is already known from the URL.

Ask the user or detect from service statuses:

1. **Which service has the problem?** (name or detect from error states, or extracted from Console URL)
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

**Via MCP tools (preferred):**
```
# Runtime / build logs — works for ANY service type (app, container, job, database, helm):
get_service_logs(environment_id = "{envId}", service_id = "{serviceId}")
#   optional: deployment_id = "{deploymentId}"  → scope to one deployment
#   optional: pod_name      = "{podName}"        → isolate a single crashing pod

# Config, deployment history, and env vars — via the Copilot (reference resources by UUID):
devops_copilot(organization_id = "{orgId}", environment_id = "{envId}",
  message = "Show the configuration, recent deployment history, and environment variables for service {serviceId}.")
```
`get_service_logs` replaces every per-type `curl` log endpoint (and covers job/database/helm logs, which have no API endpoint). `devops_copilot` READ replaces the `/application/{id}`, `/deploymentHistory`, and `/environmentVariable` API calls.

**Via CLI (fallback):**
```bash
qovery application env list          # Environment variables

# Recent logs — use the flag matching the service type:
qovery log --application "name"      # Application logs
qovery log --container "name"        # Container logs
qovery log --database "name"         # Database logs
qovery log --job "name"              # Job (cronjob/lifecycle) logs
qovery log --service "name"          # Generic — works for any service type
```

**Via API (fallback):**
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

# Service logs (last 1000 lines) — use the endpoint matching the service type:
# Application logs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{applicationId}/log" | jq '.results[-50:] | .[] | .message'
# Container logs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/container/{containerId}/log" | jq '.results[-50:] | .[] | .message'
# NOTE: Job, Helm, and Database log API endpoints do NOT exist — use `get_service_logs` (MCP) or `qovery log` CLI instead.

# Environment deployment logs (v2 — includes error details, stages, and hints):
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{environmentId}/logs" | jq '[.[] | {type, timestamp, message: .message.safe_message, error: .error.user_log_message, stage: .details.stage.step}]'
```

---

