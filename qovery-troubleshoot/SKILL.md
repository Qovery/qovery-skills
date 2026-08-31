---
name: qovery-troubleshoot
description: Diagnoses and fixes deployment failures, application crashes, build errors, connectivity problems, stuck deployments, and cluster issues on Qovery. Uses a systematic 8-layer diagnosis with MCP Server integration, CLI, and API, and generates runbooks for recurring issues. Use when the user reports a Qovery deployment that is failing, broken, stuck, or crashing. (For slow deployments use qovery-speedup; for cost optimization use qovery-optimize.)
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: troubleshooting
---

# Qovery Troubleshoot Skill

This skill diagnoses and fixes infrastructure and application issues on Qovery — crashes, build failures, connectivity problems, stuck deployments, or cluster errors. It systematically narrows the root cause, applies the fix, and writes a runbook to prevent recurrence.

For slow-but-working deployments use `qovery-speedup`. For cost-driven optimization use `qovery-optimize`.

## Usage Tracking

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
QOVERY_SKILLS_UA="QoverySkill/qovery-troubleshoot (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)"
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  QOVERY_ORG_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" -H "User-Agent: $QOVERY_SKILLS_UA" \
    "https://api.qovery.com/organization" | jq -r '.results[0].id // empty' 2>/dev/null)
  [ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
    -H "Authorization: Token $QOVERY_API_TOKEN" -H "Content-Type: application/json" -H "User-Agent: $QOVERY_SKILLS_UA" \
    -d '{"skill_name":"qovery-troubleshoot"}' > /dev/null 2>&1 || true
elif command -v qovery >/dev/null 2>&1 && qovery auth token --print >/dev/null 2>&1; then
  QOVERY_ORG_ID=$(curl -s -H "Authorization: Bearer $(qovery auth token --print)" -H "User-Agent: $QOVERY_SKILLS_UA" \
    "https://api.qovery.com/organization" | jq -r '.results[0].id // empty' 2>/dev/null)
  [ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
    -H "Authorization: Bearer $(qovery auth token --print)" -H "Content-Type: application/json" -H "User-Agent: $QOVERY_SKILLS_UA" \
    -d '{"skill_name":"qovery-troubleshoot"}' > /dev/null 2>&1 || true
fi
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

## When to Use This Skill

Trigger phrases:
- "My deployment is failing"
- "My app is crashing on Qovery"
- "Can you troubleshoot my Qovery deployment?"
- "Why is my service down?"
- "Build is failing"
- "Health check is failing"
- "Deployment is stuck"
- "App can't connect to the database"
- `/qovery-troubleshoot` (slash command)

## Workflow checklist

```
Troubleshooting Progress:
- [ ] Phase 1 — Context gathering (auth, service overview, problem identification)
- [ ] Phase 2 — Systematic 8-layer diagnosis
- [ ] Phase 3 — Apply matching playbook
- [ ] Phase 4 — Fix & redeploy
- [ ] Phase 5 — Verify the fix worked
- [ ] Phase 6 — Generate runbook
- [ ] Phase 7 — Prevention recommendations
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| MCP | [reference/mcp-server-integration.md](reference/mcp-server-integration.md) | Primary interface: the Qovery MCP tools, each mapped to the curl it replaces; setup |
| Phase 1 | [reference/phase1-context-gathering.md](reference/phase1-context-gathering.md) | Service inventory, problem identification, log fetching |
| Phase 2 | [reference/phase2-8-layer-diagnosis.md](reference/phase2-8-layer-diagnosis.md) | Cluster → Kubernetes → image → container → app → connectivity → config → cost |
| Phase 3 | [reference/phase3-playbooks.md](reference/phase3-playbooks.md) | Build failure, OOM, port mismatch, health check, stuck deploy, DB connectivity, etc. |
| Phase 4 | [reference/phase4-fix-redeploy.md](reference/phase4-fix-redeploy.md) | Apply config fix, code fix, infra fix, redeploy |
| Phase 5 | [reference/phase5-verification.md](reference/phase5-verification.md) | Confirm the issue is gone end-to-end |
| Phase 6 | [reference/phase6-runbook.md](reference/phase6-runbook.md) | Generate a reusable runbook for recurring issues |
| Phase 7 | [reference/phase7-prevention.md](reference/phase7-prevention.md) | Recommend monitoring, health checks, deployment stages, etc. |

## 8-layer diagnosis (overview)

When triaging an issue, walk top-down through these layers in [reference/phase2-8-layer-diagnosis.md](reference/phase2-8-layer-diagnosis.md):

1. **Cluster** — Is the K8s cluster healthy and ready?
2. **Kubernetes** — Are pods scheduled? Running? In CrashLoopBackOff?
3. **Image** — Did the build succeed? Is the image pullable?
4. **Container** — Is the entrypoint correct? Is the port right? Is the user non-root?
5. **Application** — Does the app start? Are the secrets present? Are env vars correct?
6. **Connectivity** — Can the app reach its DB? Can it be reached from outside?
7. **Configuration** — Health checks, deployment stages, resource limits, autoscaling
8. **Cost** — Is anything hitting a quota or cost cap that is causing failures?

## Quick reference

### MCP tools (primary interface)

Prefer these Qovery MCP tools over CLI/API for every step. Resolve IDs top-down, then act. See [reference/mcp-server-integration.md](reference/mcp-server-integration.md) for full parameters and the tool→curl mapping.

```
# Resolve IDs (org → project → environment → service)
list_organizations()
list_projects(organization_id)
list_environments(project_id)
list_services(environment_id)                 # every service + its state

# Logs (any service type: app, container, job, database, helm)
get_service_logs(environment_id, service_id[, deployment_id, pod_name])

# Kubernetes-level health & events
get_cluster_status(cluster_id, category)      # pod | node | networking | certificate | storage
get_cluster_events(cluster_id, from_datetime, to_datetime[, pod_filter])

# Everything else — config reads, deployment diagnosis, and fixes (reference resources by UUID):
devops_copilot(organization_id, message[, project_id, environment_id, thread_id])
#   READ        : status, config, env vars, health checks, custom domains, db/cluster settings
#   TROUBLESHOOT: diagnose a failing/stuck deployment; which service caused a failure
#   WRITE       : deploy/redeploy/stop/restart/scale; update cpu/memory/env vars/health checks;
#                 reorder deployment stages; add/remove custom domain; cancel a deployment
```

> Phase 4's auto-fix vs. ask-first rules govern every WRITE — using `devops_copilot` to apply a change does not bypass them.

### CLI commands (fallback — when MCP is not configured)

```bash
# Context and status
qovery context set
qovery service list
qovery status --watch

# Logs (use the flag matching the service type, or --service for any type)
qovery log --application "name" --since 1h
qovery log --container "name" --since 1h
qovery log --database "name" --since 1h
qovery log --job "name" --since 1h
qovery log --service "name" --follow
qovery log --service "name" --filter "ERROR"
qovery log --service "name" --tail 100

# Environment variables
qovery application env list
qovery environment env list

# Connectivity testing
qovery port-forward --service "name" --port 8080:8080
qovery shell --service "name"

# Cluster
qovery cluster list
```

### API endpoints (fallback — when MCP and CLI are unavailable)

Each endpoint below has an MCP equivalent (see the tool→curl mapping in [reference/mcp-server-integration.md](reference/mcp-server-integration.md)); use these only when the MCP Server is not configured.

```
# Base URL: https://api.qovery.com   Auth: Authorization: Token $QOVERY_API_TOKEN

# Status & Config
GET  /environment/{envId}/statuses               All service statuses
GET  /application/{appId}                        Service config
GET  /application/{appId}/deploymentHistory      Deployment history
GET  /application/{appId}/environmentVariable    Environment variables
GET  /organization/{orgId}/cluster               Cluster list and status

# Service logs (last 1000 lines)
GET  /application/{applicationId}/log
GET  /container/{containerId}/log
# Note: jobs / helms / databases have no API log endpoint — use `qovery log` CLI.

# Deployment logs
GET  /environment/{environmentId}/log            v1
GET  /environment/{environmentId}/logs           v2 (richer — includes error details, stages, hints)

# Actions
PUT  /application/{appId}                        Update service config (fix)
POST /application/{appId}/restart
POST /environment/{envId}/deploy
POST /environment/{envId}/cancelDeployment       Cancel stuck deployment
```

## Reference links

- **Qovery Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **MCP Server**: <https://mcp.qovery.com/mcp>
- **MCP Server Docs**: <https://www.qovery.com/docs/copilot/mcp-server>
- **Copilot Troubleshooting Capabilities**: <https://www.qovery.com/docs/copilot/capabilities/troubleshooting>
- **Copilot Optimization Capabilities**: <https://www.qovery.com/docs/copilot/capabilities/optimization>
- **CLI Reference**: <https://www.qovery.com/docs/cli/commands/overview>
- **API Reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
