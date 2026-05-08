---
name: qovery
description: Route Qovery requests to the right specialized skill and handle quick operations (list, status, stop, restart, logs, clone, scale). Activates on any generic Qovery mention. Use when the user mentions Qovery without a specific action, needs a simple operational command, or wants to discover available Qovery capabilities.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: meta-router
---

# Qovery

Entry point for all Qovery interactions. This skill detects the user's intent and either routes to the appropriate specialized skill or handles quick operational commands directly.

## When to Use This Skill

Activate when the user mentions Qovery generically or needs a quick operation:
- "I want to use Qovery"
- "Help me with Qovery"
- "What can I do with Qovery?"
- "Manage my Qovery environment"
- "List my Qovery projects"
- "Check the status of my services"
- "Stop my environment"
- "Restart my service"
- "Show me logs"
- Any Qovery Console URL pasted without a specific request
- `/qovery` (slash command)

Do NOT use this skill if the user's intent clearly matches a specialized skill — use that skill directly.

---

## Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or `new-console.qovery.com`), extract the resource IDs directly from the URL path. See [reference/console-url-detection.md](reference/console-url-detection.md) for extraction rules and API calls.

Use the extracted IDs to determine context and either route to a specialized skill or execute a quick operation against the identified resource.

---

## Intent Detection & Routing

Analyze the user's message and route to the appropriate specialized skill. **Auto-route when confident. Ask when ambiguous.**

### Routing Table

| User Intent | Route To | Example Phrases |
|---|---|---|
| New to Qovery, getting started, what is Qovery | `qovery-onboard` | "new to Qovery", "set up Qovery", "what is Qovery", "getting started", "migrate from Heroku" |
| Deploy an application, create Dockerfile, deploy to K8s | `qovery-deploy` | "deploy my app", "deploy to Kubernetes", "create a Dockerfile", "deploy to the cloud" |
| Deployment failing, app crashing, errors, connectivity | `qovery-troubleshoot` | "deployment failed", "app is crashing", "can't connect", "error", "service down", "health check" |
| Costs too high, right-sizing, resource optimization | `qovery-optimize` | "reduce costs", "optimize", "too expensive", "right-size", "save money", "cloud bill" |
| Deployments slow, build time, startup time | `qovery-speedup` | "deployment is slow", "speed up", "build takes too long", "startup time" |
| Preview environment, PR environment, test branch | `qovery-preview` | "preview for PR-123", "test this branch", "preview environment", "clone for PR" |
| Builder environments, non-tech teams, self-service dev | `qovery-builder-env` | "builder environments", "non-tech teams", "vibe coding", "sales team needs to build" |
| Self-service portal, web UI for builders | `qovery-builder-portal` | "builder portal", "self-service web UI", "web interface for builders" |

### Auto-Routing

When the intent clearly matches a specialized skill, route directly without asking:

> "This sounds like a deployment task. Loading the **qovery-deploy** skill to help you."

The agent should then load and follow the matched skill's instructions.

### Ambiguous Intent — Ask the User

If the intent is unclear, present options:

> "I can help with Qovery! What would you like to do?"
>
> 1. **Deploy** an application to Kubernetes
> 2. **Troubleshoot** a failing deployment or service
> 3. **Optimize** costs and right-size resources
> 4. **Speed up** slow deployments and builds
> 5. **Preview** — create a temporary environment for a PR
> 6. **Builder environments** — set up dev workspaces for non-tech teams
> 7. **Onboard** — get started with Qovery from scratch
> 8. **Quick operation** — list, status, stop, restart, logs (handled here)
>
> Or just describe what you need and I'll figure out the right approach.

---

## Quick Operations

For simple day-to-day commands, handle directly without routing to a specialized skill. Authenticate first — see [reference/auth.md](reference/auth.md).

> **Security:** NEVER display, log, or capture Qovery token values. Use `$(qovery auth token --print)` only **inline** within curl commands — never as a standalone command or in a variable. Add a `User-Agent` header to every request. See [reference/auth.md](reference/auth.md) for full token handling rules and User-Agent requirements.

### List Projects

```bash
qovery project list
```

Or via API:
```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization" | jq '.results[] | {id, name}'
```

### List Environments

```bash
qovery environment list
```

### Check Environment Status

```bash
qovery status
```

Or via API:
```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    services: [
      (.applications[] | {name: .name, state, type: "app"}),
      (.databases[] | {name: .name, state, type: "db"}),
      (.jobs[] | {name: .name, state, type: "job"}),
      (.containers[] | {name: .name, state, type: "container"})
    ]
  }'
```

### Stop an Environment

```bash
qovery environment stop --environment "{name}"
```

Or via API:
```bash
curl -s -X POST -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/stop"
```

### Deploy (Start/Restart) an Environment

```bash
qovery environment deploy --environment "{name}"
```

### Delete an Environment

```bash
qovery environment delete --environment "{name}"
```

### Restart a Service

```bash
qovery service restart --service "{name}"
```

### View Logs

```bash
# Stream logs in real-time
qovery log --service "{name}" --follow

# Filter for errors
qovery log --service "{name}" --since 1h --filter "ERROR"

# Last N lines
qovery log --service "{name}" --tail 100
```

Via API (applications):
```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[-50:] | .[] | .message'
```

### List Services in an Environment

```bash
qovery service list
```

### View Environment Variables

```bash
qovery application env list
```

### Clone an Environment

```bash
qovery environment clone --environment "{source}" --name "{new-name}"
```

### Cancel a Deployment

```bash
curl -s -X POST -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/cancelDeployment"
```

---

## Generic Qovery Operations

For operations not covered by the specialized skills or the quick operations above, use the Qovery CLI and API directly.

### Custom Domain Management

```bash
# List custom domains for an application
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{appId}/customDomain" | jq '.results'

# Add a custom domain
curl -s -X POST -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  "https://api.qovery.com/application/{appId}/customDomain" \
  -d '{"domain": "app.example.com", "generate_certificate": true}'

# Delete a custom domain
curl -s -X DELETE -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{appId}/customDomain/{domainId}"
```

### Scaling (Instances)

```bash
# Get current scaling config
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{appId}" | jq '{min_running_instances, max_running_instances, cpu, memory}'

# Update scaling
curl -s -X PUT -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  "https://api.qovery.com/application/{appId}" \
  -d '{"min_running_instances": 2, "max_running_instances": 5, ...}'
```

IMPORTANT: When calling `PUT /application/{appId}`, include ALL required fields from the current config, not just the ones being changed. Fetch the current config with `GET /application/{appId}` first.

### Deployment History

```bash
# Last 5 deployments for an environment
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/deploymentHistory?version=v2" | jq '.results[0:5]'

# Deployment logs v2 (includes error details, stages, hints)
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/logs" | jq '[.[] | select(.error != null) | {timestamp, error: .error.user_log_message, hint: .error.hint_message}]'
```

### Organization & Cluster Info

```bash
# List organizations
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization" | jq '.results[] | {id, name}'

# List clusters in an organization
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, status, cloud_provider, region}'

# List members
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/member" | jq '.results[] | {name, email, role_name}'
```

### Webhooks

```bash
# List webhooks
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/webhook" | jq '.results'
```

### API Tokens

```bash
# List API tokens
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/apiToken" | jq '.results[] | {id, name, created_at}'

# Create an API token
qovery token create --name "my-token" --duration 24h
```

For any operation that requires multi-step planning, creating infrastructure from scratch, or complex workflows, route to the appropriate specialized skill instead of handling it here.

---

## Available Qovery Skills

Quick reference for all specialized skills. When routing, tell the user which skill you're loading and why.

| Skill | What It Does | Trigger Phrase |
|---|---|---|
| `qovery-onboard` | Guided setup for new Qovery users, BYOK, migrations | "I'm new to Qovery" |
| `qovery-deploy` | Deploy any app to Kubernetes via CLI+API or Terraform | "Deploy my application" |
| `qovery-troubleshoot` | Diagnose and fix deployment failures, crashes, connectivity | "My deployment is failing" |
| `qovery-optimize` | Optimize costs, right-size resources, generate reports | "Reduce my cloud costs" |
| `qovery-speedup` | Analyze and fix slow deployments and builds | "My builds are slow" |
| `qovery-preview` | Preview environments for PRs with auto-shutdown | "Preview PR-123" |
| `qovery-builder-env` | Builder workspaces for non-tech teams with RBAC + TTL | "Set up builder environments" |
| `qovery-builder-portal` | Self-service web portal for builders (Vite + React) | "Deploy the builder portal" |

---

## Reference Links

- **Qovery Documentation**: https://www.qovery.com/docs/getting-started/introduction
- **Qovery Console**: https://console.qovery.com
- **CLI Reference**: https://www.qovery.com/docs/cli/commands/overview
- **API Reference**: https://www.qovery.com/docs/api-reference/introduction
