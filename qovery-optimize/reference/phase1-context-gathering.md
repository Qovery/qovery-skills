## PHASE 1: Context Gathering & Business Understanding

Before optimizing, you MUST understand the business context. Blind optimization without context leads to outages.

### 1.1 Authenticate & Inventory

**Shortcut:** If the user provided a Qovery Console URL, extract the organization ID and any other IDs from it using the URL Detection rules above. Use the extracted IDs to scope the inventory and cost analysis — e.g., if a specific environment ID is provided, focus the optimization on that environment's services rather than scanning the entire organization.

Run `qovery api /organization` to confirm the CLI is authenticated. If it succeeds, use `qovery api` for every API call in this skill (no token needs to be extracted). If it fails, fall back to `$QOVERY_API_TOKEN` with `curl`, or ask the user to run `qovery auth` (or create a token themselves and export it). See the auth reference loaded with this skill for details.

Then gather a complete inventory:

**Via MCP (preferred):**
```
"Show me all environments"
"Show me all clusters"
"What services are running in production?"
"Show me monthly spending"
"What are my highest cost services?"
```

**Via CLI:**
```bash
qovery cluster list
qovery service list
qovery status
```

**Via API:**
```bash
# List all clusters with costs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region}'

# Get cluster cost range
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster/{clusterId}/currentCost" | jq

# Get organization cost
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/currentCost" | jq

# List all environments and services
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '.results[] | {id, name, mode}'

# Get service configuration (repeat for each service)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}" | jq '{name, cpu, memory, min_running_instances, max_running_instances}'

# Get billing invoices
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/invoice" | jq
```

### 1.2 Understand the Business Context

ASK the user these questions before running any analysis. Group them conversationally:

**Group 1: Application & Traffic**

1. **What type of application is this?**
   - SaaS (steady, predictable traffic)
   - E-commerce (seasonal spikes — holidays, flash sales, promotions)
   - B2B / enterprise (business-hours heavy, quiet nights/weekends)
   - Consumer app (evening/weekend peaks)
   - Internal tool (business-hours only, low traffic)
   - Batch processing / data pipeline (scheduled, bursty)
   - ML/AI workloads (training vs inference, GPU-intensive)

2. **What are your peak traffic patterns?**
   - Steady throughout the day
   - Business hours only (9am-6pm)
   - Spikes at specific times (morning rush, lunchtime, evening)
   - Seasonal peaks — WHEN? (Black Friday, end of quarter, holiday season, back-to-school, etc.)
   - How long do spikes last? (hours, days, weeks)
   - How much does traffic increase during peaks? (2x, 5x, 10x normal)
   - Unpredictable spikes (viral events, press coverage)

**Group 2: Requirements & Growth**

3. **What's your reliability requirement per environment?**
   - Production: zero downtime, always available
   - Staging: can tolerate brief interruptions
   - Dev: can tolerate significant downtime, OK to stop overnight

4. **What are your growth expectations?**
   - Stable — traffic is predictable and not growing significantly
   - Moderate growth — 20-50% year-over-year
   - Rapid scaling expected — 2x-10x growth possible
   - Unknown / just launched

**Group 3: Tools & Priority**

5. **How do you manage your infrastructure?**
   - Qovery Console (manual)
   - Qovery CLI + API
   - Terraform Provider
   - Mix of approaches
   - Not sure (the agent will check for `.tf` files in the project)

6. **What's your optimization priority?**
   - **Minimize cost** — aggressive optimization, accept some risk of resource pressure during spikes
   - **Balance cost and performance** (recommended) — meaningful savings with comfortable safety margins
   - **Maximize performance** — only optimize obvious waste, keep generous buffers

### 1.3 Gather Resource Metrics

Collect actual resource consumption data. Default analysis period: **7 days** for real-time analysis, **30 days** for seasonal/trend analysis.

**Via MCP (preferred):**
```
"Show CPU usage across all services"
"Show memory usage for all production services"
"Find over-provisioned services"
"Show me monthly spending"
"Find underutilized resources"
"Show environments inactive for 24 hours"
"Analyze resource utilization"
```

**Via API — Cluster metrics (Prometheus-compatible):**
```bash
# CPU usage per container (7-day range, 1-hour step)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/cluster/{clusterId}/metrics?query=container_cpu_usage_seconds_total&range=7d&step=1h"

# Memory usage per container
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/cluster/{clusterId}/metrics?query=container_memory_working_set_bytes&range=7d&step=1h"

# For seasonal analysis (30 days)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/cluster/{clusterId}/metrics?query=container_cpu_usage_seconds_total&range=30d&step=6h"
```

---

