## PHASE 1: Context Gathering

Before diagnosing anything, you MUST understand what's deployed and what the user is experiencing.

### 1.1 Authenticate

Run `qovery api /organization` to confirm the CLI is authenticated. If it succeeds, use `qovery api` for every API call in this skill (no token needs to be extracted). If it fails, fall back to `$QOVERY_API_TOKEN` with `curl`, or ask the user to run `qovery auth` (or create a token themselves and export it). See the auth reference loaded with this skill for details.

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

**Via MCP:**
```
"Show me the configuration for {service-name}"
"Show deployment history for {service-name}"
"What environment variables are set for {service-name}?"
```

**Via CLI:**
```bash
qovery application env list          # Environment variables

# Recent logs — use the flag matching the service type:
qovery log --application "name"      # Application logs
qovery log --container "name"        # Container logs
qovery log --database "name"         # Database logs
qovery log --job "name"              # Job (cronjob/lifecycle) logs
qovery log --service "name"          # Generic — works for any service type
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

# Service logs (last 1000 lines) — use the endpoint matching the service type:
# Application logs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{applicationId}/log" | jq '.results[-50:] | .[] | .message'
# Container logs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/container/{containerId}/log" | jq '.results[-50:] | .[] | .message'
# NOTE: Job, Helm, and Database log API endpoints do NOT exist — use `qovery log` CLI instead.

# Environment deployment logs (v2 — includes error details, stages, and hints):
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{environmentId}/logs" | jq '[.[] | {type, timestamp, message: .message.safe_message, error: .error.user_log_message, stage: .details.stage.step}]'
```

---

