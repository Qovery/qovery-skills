## MCP Server Integration

This skill is designed to work with the **Qovery MCP Server** as the primary diagnostic and remediation interface. The MCP Server exposes structured tools that are faster and more reliable than raw CLI/API calls, and it handles authentication for you — no tokens flow through the shell.

**If the Qovery MCP Server is available** (configured in the agent's MCP settings), use its tools for every step: context gathering, diagnosis, and applying fixes. Prefer the MCP tools over `qovery` CLI commands and over `curl` against `api.qovery.com`.

**If the MCP Server is NOT available**, fall back to the Qovery CLI, and then to the REST API via `curl`. Every diagnostic step in this skill lists all three tiers in priority order: **MCP tool → CLI command → API endpoint**.

### How to check if the MCP Server is available

The MCP Server is available if the agent has it configured at `https://mcp.qovery.com/mcp`. Check by calling `list_organizations` (or attempting any read tool). If the tool resolves, prefer MCP for all subsequent steps. If the tool is not present, use the CLI/API fallbacks.

---

## MCP tools reference

These are the tools the Qovery MCP Server exposes. They are the primary interface for this skill — reach for them before CLI or `curl`.

### Resolution & inventory (READ)

| Tool | Parameters | Use it to | Replaces |
|---|---|---|---|
| `list_organizations` | — | List organizations the token can access | `GET /organization` |
| `list_projects` | `organization_id` | List projects in an organization | `GET /organization/{orgId}/project` |
| `list_environments` | `project_id` | List environments in a project | `GET /project/{projectId}/environment` |
| `list_services` | `environment_id` | List every service (app, container, job, database, helm, terraform) in an environment **with its state** | `GET /environment/{envId}/statuses` |

Chain these to resolve IDs top-down (org → project → environment → service) when you don't already have them from a Console URL.

### Logs (READ)

| Tool | Parameters | Use it to | Replaces |
|---|---|---|---|
| `get_service_logs` | `environment_id`, `service_id`, optional `deployment_id`, optional `pod_name` | Fetch runtime/build logs for a service of **any** type — application, container, job, database, helm | `GET /application/{id}/log`, `GET /container/{id}/log`, and covers the job/database/helm cases the API has no endpoint for |

`get_service_logs` supersedes both the per-type `curl` log endpoints and the `qovery log` CLI. Use `deployment_id` to scope to one deployment and `pod_name` to isolate a single crashing pod.

### Cluster / Kubernetes (READ)

| Tool | Parameters | Use it to | Replaces |
|---|---|---|---|
| `get_cluster_status` | `cluster_id`, `category` (`pod`, `networking`, `certificate`, `node`, `storage`, or `custom`), optional `object_filter` | Inspect the health/conditions of Kubernetes objects: pods (CrashLoopBackOff, pending, phase), nodes (pressure, capacity), certificates (TLS provisioning), services/gateways/routes (networking), PVCs (storage) | K8s-level inspection that the REST API doesn't expose |
| `get_cluster_events` | `cluster_id`, `from_datetime`, `to_datetime`, optional `pod_filter` | Read Kubernetes events (OOMKilled, FailedScheduling, image pull errors, evictions) over a time range. Chunk queries into ≤30-min windows to stay under the 5000-event cap | K8s event inspection the REST API doesn't expose |

`object_filter` accepts a `name` match, a `namespace`, or a Qovery `{environment_id, service_id}` pair — use the service filter to scope directly to the failing service's pods. `pod_filter` on events accepts `service_id` or `pod_name`.

### Config reads, diagnosis & actions — `devops_copilot`

`devops_copilot` is the single tool for everything the read/inventory tools above don't cover: reading detailed config, running the deployment-failure diagnosis, and applying fixes. **Always resolve IDs first with the tools above, and reference every resource by its UUID in the `message` — never by human-readable name.**

Required params: `organization_id` and a natural-language `message`. Optional scoping: `project_id`, `environment_id`, `thread_id` (continue a prior diagnosis), `instructions`.

| Category | What to ask `devops_copilot` | Replaces |
|---|---|---|
| **READ** | Environment status; application details, advanced settings, env vars, custom domains, health checks; database details; cluster advanced/security settings | `GET /application/{id}`, `.../environmentVariable`, `.../customDomain`, `.../healthchecks`, `GET /application/{id}/deploymentHistory` |
| **TROUBLESHOOT** | Diagnose a failing or stuck deployment; identify which services caused a deployment failure | `GET /environment/{envId}/logs` (v2 deployment logs with error tags, stages, hints) |
| **WRITE** | Deploy / redeploy / stop / restart / delete environment; deploy / redeploy / stop / restart / scale a service; update resources (CPU/memory); update environment variables; update health checks; update advanced settings; add/remove custom domain; cancel a stuck deployment | `PUT /application/{id}`, `POST /application/{id}/restart`, `POST /environment/{envId}/deploy`, `POST /environment/{envId}/cancelDeployment`, `POST /application/{id}/environmentVariable`, `.../secret`, `PUT /deploymentStage/{id}` |

> **Safety still applies to WRITE calls.** The auto-fix vs. ask-first rules in Phase 4 govern *what* you may change — using `devops_copilot` to apply the change does not bypass them. Ask before any code/Dockerfile/secret/schema change.

Example WRITE message (IDs already resolved):

```
devops_copilot(
  organization_id = "<org-uuid>",
  environment_id  = "<env-uuid>",
  message = "Increase the memory of service <service-uuid> to 1024 MB, then redeploy it."
)
```

---

## MCP Server Setup (if not configured)

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
