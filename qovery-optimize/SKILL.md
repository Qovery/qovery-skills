---
name: qovery-optimize
description: Optimize Kubernetes cluster and application costs on Qovery. Analyzes historical resource consumption, understands business context (seasonal patterns, growth stage, reliability requirements), estimates external resource costs from public cloud pricing, and proposes right-sizing, autoscaling, environment scheduling, spot instances, and database mode changes. Generates detailed cost reports with CSV export. Applies changes via CLI+API or Terraform depending on the user's workflow.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: optimization
---

# Qovery Optimize Skill

You are an expert at optimizing Kubernetes infrastructure costs on Qovery. When a user asks you to reduce costs, right-size resources, or optimize their Qovery deployment, follow this skill to analyze their infrastructure, understand their business context, and propose intelligent cost optimizations.

This skill is NOT about blindly reducing everything to minimum. It's about **intelligent optimization** that:
- Understands the business context (seasonal peaks, growth expectations, reliability needs)
- Analyzes historical resource consumption, not just current allocation
- Respects safety margins appropriate for each environment
- Estimates external cloud resource costs from public pricing data
- Presents recommendations with expected savings AND risks
- Applies changes via the user's preferred tool (CLI+API or Terraform)

## When to Use This Skill

Use this skill when the user says anything like:
- "Optimize my Qovery costs"
- "My cloud bill is too high"
- "Right-size my applications"
- "How can I reduce my Kubernetes costs?"
- "Are my services over-provisioned?"
- "Optimize my cluster"
- "Can you help me save money on Qovery?"
- "Review my resource allocations"
- "How much is my infrastructure costing me?"
- "Generate a cost report"
- "I want to reduce my AWS/GCP/Azure bill"
- `/qovery-optimize` (slash command)

---

## Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or `new-console.qovery.com`), extract the resource IDs directly from the URL path. This immediately scopes the optimization analysis — you know which organization, project, environment, or service the user wants to optimize.

**URL format:**
```
https://{console.qovery.com|new-console.qovery.com}/organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}[/{page}]
```

**Extraction rules:**
- `orgId` — UUID after `/organization/`
- `projectId` — UUID after `/project/`
- `envId` — UUID after `/environment/`
- `serviceId` — UUID after `/service/`

Not every URL contains all segments. Use whatever IDs are present to scope the analysis:
- URL with only `orgId` -> optimize across the entire organization (all clusters, all environments)
- URL with `orgId` + `projectId` -> optimize all environments in that project
- URL with `envId` -> optimize that specific environment
- URL with `serviceId` -> focus on right-sizing that specific service

**After extracting IDs, use them directly for inventory and cost analysis:**
```bash
# Get organization name
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | select(.id == "{orgId}") | {id, name}'

# Get all clusters in the organization
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'

# Get environment services and their resource allocations
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    applications: [.applications[] | {id, name: .name, state}],
    containers: [.containers[] | {id, name: .name, state}],
    databases: [.databases[] | {id, name: .name, state}],
    jobs: [.jobs[] | {id, name: .name, state}]
  }'
```

**Use the extracted IDs directly** in all subsequent API calls — skip asking the user to identify which organization, environment, or service to optimize.

---

## PHASE 1: Context Gathering & Business Understanding

Before optimizing, you MUST understand the business context. Blind optimization without context leads to outages.

### 1.1 Authenticate & Inventory

**Shortcut:** If the user provided a Qovery Console URL, extract the organization ID and any other IDs from it using the URL Detection rules above. Use the extracted IDs to scope the inventory and cost analysis — e.g., if a specific environment ID is provided, focus the optimization on that environment's services rather than scanning the entire organization.

Use the same authentication flow as the other Qovery skills:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set
2. Check if CLI is authenticated (`~/.qovery/context.json`)
3. Generate a token via `qovery token` if needed
4. Fall back to JWT from `~/.qovery/context.json`

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

## PHASE 2: Analysis Engine — 7 Optimization Dimensions

Analyze the infrastructure across 7 dimensions. For each, calculate current cost, recommended configuration, expected savings, and risk level.

### Dimension 1: Service Right-Sizing (CPU & Memory)

For EACH service, compare allocated resources vs actual peak usage over the analysis period.

**Right-sizing formula (adjusted by business context):**

| Context | Formula | Safety Buffer | Rationale |
|---|---|---|---|
| Production + steady traffic | `max(peak_7d * 1.5, min_threshold)` | 50% above peak | Handles normal variance |
| Production + seasonal spikes | `max(peak_30d * 1.5, min_threshold)` | 50% above 30-day peak | Captures seasonal peaks |
| Production + growth expected | `max(peak_7d * 2.0, min_threshold)` | 100% above peak | Room for growth |
| Staging | `max(peak_7d * 1.3, min_threshold)` | 30% above peak | Adequate for testing |
| Development | `max(peak_7d * 1.2, min_threshold)` | 20% above peak | Minimal overhead |

**Minimum thresholds** (never recommend below these):
- CPU: 50m (millicores)
- Memory: 128MB

**How to read the analysis:**
```
Service: backend (production, steady traffic)
  CPU:
    Allocated: 500m
    Peak (7d):  120m
    Peak (30d): 180m
    Recommended: 250m (peak_7d * 1.5 = 180m, rounded up to 250m)
    Savings: ~$XX/month
    Risk: LOW — 120m peak with 250m allocation = 108% headroom

  Memory:
    Allocated: 1024MB
    Peak (7d):  350MB
    Peak (30d): 400MB
    Recommended: 512MB (peak_30d * 1.3 = 520m, rounded to 512MB)
    Savings: ~$XX/month
    Risk: LOW — 400MB peak with 512MB allocation = 28% headroom
```

**IMPORTANT for seasonal businesses:**
- Use the 30-day peak (not 7-day) for right-sizing
- If the user mentioned specific peak periods (e.g., Black Friday): DO NOT optimize below those peaks
- Recommend autoscaling (Dimension 2) as the primary strategy instead of fixed right-sizing
- Suggest pre-scaling before known peaks

### Dimension 2: Instance Count & Autoscaling

Analyze current min/max instances vs actual demand.

| Current Config | Signal | Recommendation |
|---|---|---|
| min=3, max=3 (no autoscaling) | Fixed, may be over-provisioned off-peak | Enable autoscaling: reduce min, set appropriate max |
| min=1, max=1 (production) | No redundancy, single point of failure | Increase min=2 for high availability |
| min=5, max=5, peak demand = 2 instances | Over-provisioned | Enable autoscaling: min=2, max=6 |
| min=2, max=10, never exceeds 3 | Max is fine (costs nothing idle), min may be reducible | Consider min=1 for staging, keep min=2 for production |
| Autoscaling enabled, frequently hitting max | Under-provisioned max | Increase max instances |

**For seasonal businesses:**
- Keep max instances high enough for peak periods (e.g., 3x normal max)
- Reduce min instances during off-peak (e.g., min=2 off-peak, min=5 during Black Friday week)
- Consider KEDA (event-driven autoscaling) for queue-based or metric-based scaling
- Suggest pre-scaling: increase min instances 1-2 days before known peaks

**For growth-stage companies:**
- Use autoscaling as the primary strategy (not fixed instances)
- Set max generously — it only costs money when used
- Review monthly as traffic patterns emerge

### Dimension 3: Database Mode Optimization

| Current | Environment | Signal | Recommendation | Savings |
|---|---|---|---|---|
| Managed DB (e.g., RDS) | Dev/Test | Expensive for non-production | Switch to container mode | 60-80% |
| Container DB | Production | Risk: no backups, no HA, no failover | Switch to managed mode | Costs more, but necessary |
| Managed DB, db.r6g.xlarge | Production | Instance type may be oversized | Check if db.r6g.large suffices | 50% on compute |
| Managed DB, 100GB storage | Production | Storage only 20% used | Cannot shrink RDS storage, but note for next DB | Future savings |

**For Redis/cache:**
- Dev/test: always container mode
- Production: managed ElastiCache only if HA is needed; otherwise container mode is often sufficient for cache

### Dimension 4: Environment Lifecycle (Start/Stop Scheduling)

Identify environments that run 24/7 but don't need to:

| Environment Type | Current | Recommended Schedule | Monthly Savings |
|---|---|---|---|
| Development | 24/7 ($500/month) | Mon-Fri 8am-8pm (60h/week vs 168h) | ~$350 (70%) |
| Staging | 24/7 ($300/month) | Mon-Fri 8am-10pm (70h/week) | ~$175 (58%) |
| Preview/PR | Always running ($200/month) | Auto-stop after 2h idle | ~$180 (90%) |
| Production | 24/7 ($1,000/month) | Keep 24/7 (required) | $0 |

**How to implement:**
- Via Qovery Console: Environment Settings > Deployment Rules
- Via API: Create deployment rules at project or environment level
- Via MCP: `"Stop all non-production environments for the weekend"`

**Deployment rule examples:**
```
Rule 1 (highest priority): prod-* → Never stop
Rule 2: staging-* → Stop weekends, Mon-Fri 8am-10pm
Rule 3: dev-* → Mon-Fri 8am-8pm only
Rule 4 (catch-all): * → Stop after 2h inactive
```

### Dimension 5: Cluster-Level Optimization

| Area | Signal | Recommendation | Savings |
|---|---|---|---|
| Instance types for Karpenter | Only 2-3 types configured | Diversify to 10-20 types (t3, m5, m6i, c5, r5 families) for better bin-packing | 10-20% |
| Spot instances not enabled | All on-demand for non-production | Enable spot for dev/staging clusters | 60-70% |
| Node utilization consistently <40% | Over-provisioned | Verify Karpenter is consolidating properly | Variable |
| Multiple small clusters | Separate clusters for dev/staging/prod | Consider consolidating dev+staging on one cluster | $73/month per eliminated cluster + node savings |
| Single AZ deployment | All nodes in one AZ | Spread across AZs for HA (may increase NAT costs slightly) | Reliability improvement |

**Spot instance guidance:**
- NEVER for production workloads requiring high availability
- IDEAL for: dev environments, staging, batch jobs, CI/CD, non-critical workers
- Qovery + Karpenter handle spot interruptions automatically with fallback to on-demand

### Dimension 6: Build Optimization

| Signal | Recommendation | Impact |
|---|---|---|
| Builds >10 min | Optimize Dockerfile layers, order COPY commands by change frequency | Faster deploys, lower build compute |
| Docker images >1GB | Use multi-stage builds, alpine base images | Faster pulls, lower registry storage |
| Rebuilds on unchanged services | Qovery smart build detection should handle this; verify it's working | Avoid redundant builds |
| Build runner oversized | Check if build CPU/memory allocation matches build needs | Reduce build runner costs |

### Dimension 7: External Resource Cost Estimation

For resources managed outside of Qovery's direct billing (e.g., `qovery_terraform_service` provisioning AWS/GCP/Azure resources), estimate costs from configuration parameters and public cloud pricing.

**IMPORTANT DISCLAIMER:** These are estimates based on:
- Resource configuration parameters visible in Qovery Terraform service configs
- Public cloud provider pricing as of the analysis date
- Standard on-demand pricing (no Reserved Instance or Savings Plan discounts)

Actual costs may vary based on:
- Data transfer volumes (not estimatable from config alone)
- API request counts and I/O operations (usage-dependent)
- Reserved Instance, Savings Plan, or EDP discounts the user may have
- Regional pricing variations
- Cloud provider pricing changes

**How to estimate:**

1. **Identify external resources** — List all `qovery_terraform_service` resources and managed databases
2. **Extract parameters** — Instance type, storage, region, engine from the service config/variables
3. **Look up pricing** — Use the reference pricing table below or fetch from public pricing APIs
4. **Calculate monthly cost** — Instance hourly rate x 730 hours + storage per GB/month

**Common external resource cost estimates:**

For each resource found, calculate and present:
```
Resource: rds-aurora (Terraform Service)
  Type: AWS RDS Aurora Serverless v2
  Config: 0.5-4 ACU, 20GB storage, us-east-1
  Compute: 0.5 ACU min x $0.12/ACU-hour x 730h = ~$44/month (idle)
           4 ACU max x $0.12/ACU-hour x 730h = ~$350/month (full load)
  Storage: 20GB x $0.10/GB/month = $2/month
  Estimated range: $46 - $352/month depending on load
  Optimization: Check if min ACU can be reduced; review actual ACU usage in CloudWatch

Resource: redis-cache (ElastiCache via Terraform Service)
  Type: AWS ElastiCache, cache.t3.medium, 1 node, us-east-1
  Compute: $0.068/hr x 730h = ~$50/month
  Optimization: Consider cache.t4g.medium (Graviton, ~20% cheaper at ~$40/month)

Resource: NAT Gateway (implicit — exists on every VPC)
  Type: AWS NAT Gateway, 1 per AZ
  Compute: $0.045/hr x 730h = ~$33/month per gateway
  Data: $0.045/GB processed
  Estimated: $33-100/month depending on data transfer
  Optimization: Use VPC endpoints for S3/DynamoDB to reduce NAT traffic
```

**Hidden infrastructure costs** (always present on Kubernetes clusters):

| Resource | Provider | Monthly Cost | Notes |
|---|---|---|---|
| EKS cluster management fee | AWS | $73/month (fixed) | $0.10/hour per cluster |
| GKE cluster management fee | GCP | $73/month (Standard) or $0 (Autopilot, pay-per-pod) | |
| AKS cluster management fee | Azure | $0 (free control plane) | |
| NAT Gateway (per AZ) | AWS | $33-100+/month | $0.045/hr + $0.045/GB data processed |
| Cloud NAT | GCP | $0.045/hr + per-GB | Similar to AWS |
| Application Load Balancer | AWS | ~$16/month + LCU | $0.0225/hr base |
| Cloud Load Balancer | GCP | ~$18/month + per-rule | |
| EBS volumes (gp3) | AWS | $0.08/GB/month | Per node, typically 50-100GB |
| Persistent Disks | GCP | $0.040-0.170/GB/month | Depends on type |

---

## Reference Pricing Table (On-Demand, as of 2025)

Use this table for quick cost estimation. Prices are for us-east-1 (AWS), us-central1 (GCP), eastus (Azure). Other regions may vary by 5-20%.

### AWS EC2 / EKS Node Instance Types

| Instance | vCPU | Memory | Hourly | Monthly (~730h) |
|---|---|---|---|---|
| t3.small | 2 | 2GB | $0.0208 | ~$15 |
| t3.medium | 2 | 4GB | $0.0416 | ~$30 |
| t3.large | 2 | 8GB | $0.0832 | ~$61 |
| t3.xlarge | 4 | 16GB | $0.1664 | ~$121 |
| m5.large | 2 | 8GB | $0.096 | ~$70 |
| m5.xlarge | 4 | 16GB | $0.192 | ~$140 |
| m6i.large | 2 | 8GB | $0.096 | ~$70 |
| m6i.xlarge | 4 | 16GB | $0.192 | ~$140 |
| c5.large | 2 | 4GB | $0.085 | ~$62 |
| r5.large | 2 | 16GB | $0.126 | ~$92 |
| t3.medium (spot) | 2 | 4GB | ~$0.013 | ~$9 (70% savings) |
| m5.large (spot) | 2 | 8GB | ~$0.035 | ~$26 (63% savings) |

### AWS RDS Instance Types

| Instance | vCPU | Memory | Hourly | Monthly |
|---|---|---|---|---|
| db.t3.micro | 2 | 1GB | $0.017 | ~$12 |
| db.t3.small | 2 | 2GB | $0.034 | ~$25 |
| db.t3.medium | 2 | 4GB | $0.068 | ~$50 |
| db.t3.large | 2 | 8GB | $0.136 | ~$99 |
| db.r6g.large | 2 | 16GB | $0.260 | ~$190 |
| db.r6g.xlarge | 4 | 32GB | $0.520 | ~$380 |
| RDS storage (gp3) | — | — | — | $0.115/GB/month |
| RDS Multi-AZ surcharge | — | — | — | 2x compute cost |
| Aurora Serverless v2 | — | — | $0.12/ACU-hour | Varies by load |

### AWS ElastiCache

| Instance | vCPU | Memory | Hourly | Monthly |
|---|---|---|---|---|
| cache.t3.micro | 2 | 0.5GB | $0.017 | ~$12 |
| cache.t3.medium | 2 | 3.09GB | $0.068 | ~$50 |
| cache.t4g.medium | 2 | 3.09GB | $0.054 | ~$40 (Graviton, 20% cheaper) |
| cache.r6g.large | 2 | 13.07GB | $0.209 | ~$153 |

### AWS Infrastructure (Fixed Costs)

| Resource | Pricing | Monthly |
|---|---|---|
| EKS cluster fee | $0.10/hr | $73 |
| NAT Gateway (per AZ) | $0.045/hr + $0.045/GB | $33 + data |
| ALB (Application Load Balancer) | $0.0225/hr + LCU-hours | ~$16 + usage |
| NLB (Network Load Balancer) | $0.0225/hr + NLCU-hours | ~$16 + usage |
| EBS gp3 | $0.08/GB/month | Per volume |
| EBS io1 | $0.125/GB/month + $0.065/IOPS | Per volume |
| S3 Standard | $0.023/GB/month | Per bucket |
| S3 Intelligent-Tiering | $0.023/GB (freq) to $0.0036/GB (archive) | Auto-tiered |
| CloudFront | $0.085/GB (first 10TB) | Per distribution |

### GCP

| Resource | Pricing | Monthly |
|---|---|---|
| GKE Standard cluster | $0.10/hr | $73 |
| GKE Autopilot | Per-pod pricing (CPU: $0.0445/vCPU-hr, Mem: $0.0049/GB-hr) | Varies |
| Cloud SQL db-f1-micro | — | ~$7 |
| Cloud SQL db-custom-2-8192 | — | ~$97 |
| Cloud SQL db-custom-4-16384 | — | ~$195 |
| Cloud NAT | $0.045/hr + per-GB | ~$33 + data |
| Cloud Load Balancer | $0.025/hr + per-rule | ~$18 + rules |
| Persistent Disk (SSD) | $0.170/GB/month | Per disk |
| Persistent Disk (Standard) | $0.040/GB/month | Per disk |

### Azure

| Resource | Pricing | Monthly |
|---|---|---|
| AKS control plane | Free | $0 |
| Standard_D2s_v3 (2 vCPU, 8GB) | $0.096/hr | ~$70 |
| Standard_D4s_v3 (4 vCPU, 16GB) | $0.192/hr | ~$140 |
| Azure DB for PostgreSQL (GP, 2 vCores) | — | ~$125 |
| Azure DB for PostgreSQL (GP, 4 vCores) | — | ~$250 |
| Azure Load Balancer (Standard) | $0.025/hr + rules | ~$18 + rules |
| Managed Disks (Premium SSD, P10) | — | ~$19.71/128GB |

### Scaleway

| Resource | Pricing | Monthly |
|---|---|---|
| Kapsule cluster | Free control plane | $0 |
| DEV1-M (3 vCPU, 4GB) | — | ~$20 |
| GP1-S (8 vCPU, 32GB) | — | ~$65 |
| Managed DB (DB-DEV-S) | — | ~$11 |
| Managed DB (DB-GP-XS) | — | ~$42 |

---

## PHASE 3: Cost Report Generation

Generate a comprehensive cost optimization report in TWO formats.

### 3.1 Markdown Report

Save to `.qovery/reports/YYYY-MM-DD-cost-optimization.md`:

```markdown
# Qovery Cost Optimization Report

**Date:** YYYY-MM-DD
**Organization:** {name}
**Scope:** {all clusters / specific project / specific environment}
**Business Context:** {SaaS with steady traffic / E-commerce with seasonal peaks / etc.}
**Optimization Priority:** {Minimize cost / Balanced / Maximize performance}
**Analysis Period:** 7 days (real-time) + 30 days (trends)

---

> **Cost Estimation Methodology**
>
> Costs in this report are estimated using two sources:
> 1. **Qovery-managed resources** (applications, containers, databases, Helm charts):
>    Estimated from CPU/memory allocation and Qovery billing API data.
> 2. **External cloud resources** (RDS, ElastiCache, S3, NAT Gateway, load balancers, etc.):
>    Estimated from resource configuration parameters visible in Qovery Terraform services,
>    cross-referenced with public cloud provider pricing as of {date}.
>
> These are estimates. Actual costs depend on usage patterns (data transfer, I/O, API calls)
> and any discounts (Reserved Instances, Savings Plans, EDPs). For precise billing, consult
> your cloud provider's cost dashboard or deploy Kubecost for Kubernetes-level tracking.

---

## Executive Summary

| Metric | Value |
|---|---|
| Current estimated monthly cost | $X,XXX |
| Total potential savings | $XXX - $X,XXX |
| Savings percentage | XX-XX% |
| Recommendations | X total, Y high-impact |
| Risk level | {Low / Medium} — {explanation} |

## Current Cost Breakdown

### By Cluster

| Cluster | Provider | Region | Nodes | Est. Monthly Cost |
|---|---|---|---|---|
| production | AWS EKS | us-east-1 | 5 | $X,XXX |
| staging | AWS EKS | us-east-1 | 2 | $XXX |

### By Environment

| Environment | Mode | Apps | DBs | Helm | Jobs | Est. Monthly Cost |
|---|---|---|---|---|---|---|
| production | PRODUCTION | 3 | 2 | 1 | 2 | $X,XXX |
| staging | STAGING | 3 | 1 | 0 | 0 | $XXX |
| development | DEVELOPMENT | 2 | 1 | 0 | 0 | $XXX |

### By Service (Top 10 by Estimated Cost)

| Service | Environment | Type | CPU | Memory | Instances | Est. Monthly Cost |
|---|---|---|---|---|---|---|
| backend | production | Application | 500m | 1024MB | 3 | $XXX |
| frontend | production | Application | 500m | 512MB | 2 | $XXX |
| postgres | production | Database (Managed) | — | — | — | $XXX |
| redis | production | Helm | — | — | — | $XX |
| ... | ... | ... | ... | ... | ... | ... |

### External Cloud Resources (Estimated)

> These estimates are based on resource configuration and public cloud pricing.
> Actual costs depend on usage. See methodology note above.

| Resource | Type | Config | Region | Est. Monthly Cost |
|---|---|---|---|---|
| EKS cluster fee | Fixed | 1 cluster | us-east-1 | $73 |
| NAT Gateway | Per-AZ | 2 AZs, ~50GB/month | us-east-1 | ~$69 |
| ALB | Load Balancer | 1 ALB | us-east-1 | ~$20 |
| EBS volumes | Storage | 5 nodes x 50GB gp3 | us-east-1 | ~$20 |
| rds-aurora | Terraform Service | Aurora Serverless v2 | us-east-1 | ~$46-352 |
| ... | ... | ... | ... | ... |

**Total estimated external resources: $XXX - $XXX/month**
*Data transfer and I/O charges not included*

---

## Recommendations (Sorted by Estimated Impact)

### 1. Right-Size Services — Save ~$XXX/month {risk: Low}

| Service | Env | Resource | Current | Peak (7d) | Peak (30d) | Recommended | Savings |
|---|---|---|---|---|---|---|---|
| backend | prod | CPU | 500m | 120m | 180m | 250m | ~$XX |
| backend | prod | Memory | 1024MB | 350MB | 400MB | 512MB | ~$XX |
| frontend | prod | CPU | 500m | 30m | 50m | 100m | ~$XX |
| frontend | prod | Memory | 512MB | 100MB | 120MB | 256MB | ~$XX |
| worker | prod | CPU | 1000m | 200m | 300m | 500m | ~$XX |

*Safety buffers applied: Production 1.5x peak (steady traffic)*

### 2. Enable Environment Scheduling — Save ~$XXX/month {risk: None}

| Environment | Current Schedule | Recommended | Savings |
|---|---|---|---|
| dev-* | 24/7 | Mon-Fri 8am-8pm | ~$XXX/month |
| staging-* | 24/7 | Mon-Fri 8am-10pm | ~$XXX/month |
| preview/PR | Always running | Auto-stop after 2h idle | ~$XX/month |

### 3. Switch Dev Databases to Container Mode — Save ~$XX/month {risk: None}

| Database | Environment | Current Mode | Recommended | Savings |
|---|---|---|---|---|
| postgres-dev | development | MANAGED | CONTAINER | ~$XX/month |
| redis-dev | development | MANAGED | CONTAINER | ~$XX/month |

### 4. Enable Autoscaling — Save ~$XX/month {risk: Low}

| Service | Env | Current (min/max) | Recommended (min/max) | Savings |
|---|---|---|---|---|
| backend | prod | 3/3 | 2/5 | ~$XX/month off-peak |
| frontend | prod | 2/2 | 1/3 | ~$XX/month off-peak |

### 5. Enable Spot for Non-Production — Save ~$XX/month {risk: Low}

| Cluster/Environment | Current | Recommended | Savings |
|---|---|---|---|
| staging cluster | On-demand | Spot with on-demand fallback | ~60-70% on compute |

### 6. External Resource Optimizations

| Resource | Current | Recommended | Est. Savings |
|---|---|---|---|
| ElastiCache | cache.t3.medium | cache.t4g.medium (Graviton) | ~$10/month (20%) |
| NAT Gateway | No VPC endpoints | Add S3/DynamoDB VPC endpoints | ~$5-20/month on data |
| Reserved Instances | All on-demand | 1yr RI for stable prod workloads | 30-40% on committed |

### 7. Build Optimizations

| Issue | Recommendation | Impact |
|---|---|---|
| {if applicable} | ... | ... |

---

## Seasonal Considerations

{If the user has seasonal traffic patterns, include specific guidance here:}

- **Peak period:** {Black Friday / end of quarter / holiday / etc.}
- **Pre-scaling recommendation:** Increase min instances to X, 2 days before peak
- **During peak:** Do NOT apply right-sizing changes; let autoscaling handle spikes
- **Post-peak:** Re-analyze and apply right-sizing after traffic normalizes (1 week after)
- **Annual review:** Re-run this analysis at the start of each quarter

---

## Risks & Tradeoffs

{For each recommendation, state the risk:}

| Recommendation | Risk | Mitigation |
|---|---|---|
| Right-size backend to 250m CPU | Low — 108% headroom above 7d peak | Autoscaling catches unexpected spikes |
| Stop dev environments overnight | None — no users during off-hours | Deployment rules handle start/stop |
| Spot instances for staging | Low — Karpenter auto-falls back to on-demand | Brief interruption possible (~2 min) |

---

## Next Steps

1. Review and approve the recommendations above
2. Apply via {CLI+API / Terraform} (see Phase 4)
3. Re-run this analysis in 30 days to track improvements
4. Consider deploying Kubecost for real-time cost visibility
5. Share this report with Qovery support for professional review (see below)
```

### 3.2 CSV Export

Generate alongside the markdown report: `.qovery/reports/YYYY-MM-DD-cost-optimization.csv`

```csv
category,service,environment,resource,current,peak_7d,peak_30d,recommended,est_savings_monthly,risk
right-size,backend,production,cpu,500m,120m,180m,250m,$XX,Low
right-size,backend,production,memory,1024MB,350MB,400MB,512MB,$XX,Low
right-size,frontend,production,cpu,500m,30m,50m,100m,$XX,Low
scheduling,dev-*,development,environment,24/7,,,"Mon-Fri 8am-8pm",$XXX,None
db-mode,postgres-dev,development,database,MANAGED,,,CONTAINER,$XX,None
autoscaling,backend,production,instances,3/3,,,2/5,$XX,Low
spot,staging,staging,cluster,on-demand,,,spot,$XX,Low
external,elasticache,production,node-type,cache.t3.medium,,,cache.t4g.medium,$10,None
```

---

## PHASE 4: Apply Changes

### 4.1 User Approval

Present the report and ask:

> "Here are my cost optimization recommendations, sorted by impact. Which ones would you like me to apply? You can:
> - Say **'all'** to apply everything
> - Pick specific numbers (e.g., '1, 2, 4')
> - Say **'skip'** for any you want to hold off on
> - Ask me to adjust any recommendation before applying"

NEVER apply changes without explicit user approval.

### 4.2 Determine the Tool

If the user specified their tool in Phase 1, use that. If not, ask:

> "How should I apply these changes?
> A) **Qovery API** — applies immediately, changes take effect on next deployment
> B) **Generate Terraform diffs** — I'll show you the exact `.tf` changes to review and apply yourself
> C) **Both** — apply now via API and also generate Terraform for long-term IaC management"

### 4.3 Apply via API

For each approved recommendation:

```bash
# Right-size a service (CPU + memory)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cpu": 250, "memory": 512}'

# Enable autoscaling
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 2, "max_running_instances": 5}'

# Via MCP
"Scale down the backend to 250m CPU and 512MB memory"
"Set backend autoscaling to min 2, max 5"
"Stop all development environments"
```

### 4.4 Generate Terraform Diffs

If the user manages infrastructure via Terraform, generate clear before/after diffs:

```hcl
# BEFORE (current):
resource "qovery_application" "backend" {
  cpu    = 500
  memory = 1024
  min_running_instances = 3
  max_running_instances = 3
}

# AFTER (optimized):
resource "qovery_application" "backend" {
  cpu    = 250    # Right-sized: peak 180m (30d), recommended 250m (1.5x buffer)
  memory = 512    # Right-sized: peak 400MB (30d), recommended 512MB (1.3x buffer)
  min_running_instances = 2    # Enabled autoscaling: reduced from 3 for off-peak savings
  max_running_instances = 5    # Headroom for traffic spikes
}
```

Present each change with a comment explaining the reasoning and the data behind it.

### 4.5 Set Up Environment Scheduling

For deployment rules:
- Via Console: guide through Environment Settings > Deployment Rules
- Via MCP: `"Stop all development environments for the weekend"`
- Note: provide the deployment rule configuration (pattern, start time, stop time, timezone, days)

### 4.6 Redeploy Affected Services

After applying resource changes, services need a redeploy:

```bash
# Redeploy all services in the environment
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"

# Or via MCP
"Redeploy the production environment"

# Or via CLI
qovery environment deploy
```

---

## PHASE 5: Ongoing Monitoring & Follow-Up

### 5.1 Offer Kubecost Deployment

If Kubecost is not already installed on the cluster:

> "Kubecost provides real-time cost visibility per pod, namespace, and deployment. It shows exactly how much each service costs and identifies optimization opportunities automatically. Would you like me to deploy it on your cluster?"

If the user agrees, deploy Kubecost via Qovery Helm chart:

1. Add the Kubecost Helm repository to the organization:
   - Repository name: `kubecost`
   - URL: `https://kubecost.github.io/cost-analyzer/`

2. Create a Helm service in the environment:
   - Chart: `cost-analyzer`
   - Version: `1.108.0` (or latest)
   - Allow cluster-wide resources: yes
   - Port: 9090 (HTTP, publicly accessible for dashboard access)

3. After deployment, provide the Kubecost dashboard URL to the user.

### 5.2 Cloud Provider Cost Dashboard

For precise billing data beyond estimates:

> "For exact billing data from your cloud provider, you can check:
> - **AWS**: Cost Explorer at https://console.aws.amazon.com/cost-management/
> - **GCP**: Billing at https://console.cloud.google.com/billing
> - **Azure**: Cost Management at https://portal.azure.com/#blade/Microsoft_Azure_CostManagement
> - **Scaleway**: Billing at https://console.scaleway.com/billing
>
> These dashboards show actual charges including data transfer, API calls, and I/O that aren't estimatable from configuration alone."

### 5.3 Offer Qovery Support Review

> "Would you like to share this optimization report with Qovery's support team for a professional review? They can:
> - Validate the recommendations against your specific Qovery plan and pricing
> - Suggest cloud provider-specific optimizations (Reserved Instances, Savings Plans, EDPs)
> - Review your cluster configuration (Karpenter settings, instance type selection)
> - Provide guidance on Qovery Enterprise features for cost management
> - Help with advanced optimizations (KEDA autoscaling, multi-cluster strategies)
>
> You can reach them at:
> - **Email:** support@qovery.com (attach the report from `.qovery/reports/`)
> - **Qovery Console:** In-app chat support
> - **Community Forum:** https://discuss.qovery.com
>
> Sharing the report in `.qovery/reports/` gives them full context for a faster, more targeted review."

### 5.4 Save Report & Schedule Follow-Up

1. **Save both reports:**
   ```bash
   # Already saved during Phase 3:
   .qovery/reports/YYYY-MM-DD-cost-optimization.md   # Full report
   .qovery/reports/YYYY-MM-DD-cost-optimization.csv   # Spreadsheet data
   ```

2. **Offer to commit to git:**
   ```bash
   git add .qovery/reports/
   git commit -m "docs: add cost optimization report YYYY-MM-DD"
   ```

3. **Recommend follow-up schedule:**
   > "I recommend re-running this optimization analysis:
   > - **Monthly** for steady workloads (track drift and new opportunities)
   > - **After traffic pattern changes** (new feature launch, marketing campaign, seasonal event)
   > - **After infrastructure changes** (new services, cluster upgrades, provider migrations)
   > - **Post-seasonal peak** (1 week after Black Friday, etc.) to right-size back down
   > - **Quarterly** at minimum for any business"

---

## PHASE 6: Seasonal & Special Considerations

### E-Commerce / Seasonal Businesses

- **NEVER right-size below 30-day peaks** during or approaching peak season
- **Pre-scale 1-2 days before known peaks**: increase `min_running_instances` temporarily
- **Keep autoscaling max high**: 3-5x normal capacity during peak season
- **Post-peak review**: 1 week after the peak ends, re-analyze and right-size back down
- **Annual calendar**: create a schedule of known peaks and optimization windows

Example pre-scale command:
```bash
# Before Black Friday: increase min instances
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 5, "max_running_instances": 20}'

# After Black Friday: revert to normal
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 2, "max_running_instances": 6}'
```

### SaaS / Steady Traffic

- **Focus on right-sizing** — steady traffic means 7-day peaks are reliable predictors
- **Focus on environment scheduling** — biggest savings for non-production
- **Autoscaling with conservative max** — spikes are rare, max=2x normal is usually sufficient
- **Reserved Instances / Savings Plans** — stable workloads benefit most from committed pricing (30-40% savings)

### Startup / Growth Stage

- **Conservative right-sizing** — don't cut too aggressively, traffic is growing
- **Use autoscaling as primary strategy** — set generous max, low min
- **Review monthly** — traffic patterns are still emerging
- **Avoid long-term commitments** (RIs, Savings Plans) — traffic is unpredictable
- **Focus on environment scheduling** — immediate savings with zero risk

### B2B / Business-Hours

- **Aggressive environment scheduling** — most traffic is 9am-6pm weekdays
- **Consider reducing production instances outside business hours** (if your SLA allows brief scale-down at 3am)
- **Weekend shutdown for staging/dev** — significant savings

### ML/AI Workloads

- **GPU instances are expensive** ($1-10/hour per GPU) — optimize aggressively
- **Training workloads**: use spot instances (60-70% savings), tolerate interruptions with checkpointing
- **Inference serving**: autoscale to zero when idle (KEDA), use GPU sharing if supported
- **Data pipelines**: schedule during off-peak hours for potential spot availability
- **Karpenter GPU provisioning**: ensure GPU node groups are configured with appropriate instance types (p3, g4dn, g5)

### Batch Processing / Data Pipelines

- **Event-driven autoscaling (KEDA)**: scale based on queue depth, not CPU
- **Scale to zero**: when no work is queued, scale pods to 0
- **Spot instances**: ideal for fault-tolerant batch workloads
- **Schedule during off-peak**: cloud prices can be lower when demand is low

---

## Quick Reference

### MCP Queries for Optimization

```
# Cost analysis
"Show me monthly spending"
"What are my highest cost services?"
"Compare costs this month vs last month"
"Show me cost trends over time"

# Resource analysis
"Show CPU usage across all services"
"Show memory usage for production services"
"Find over-provisioned services"
"Find underutilized resources"

# Inactive resources
"Show environments inactive for 24 hours"
"List unused databases"
"Find idle applications"

# Actions
"Stop all development environments for the weekend"
"Scale down the backend to 250m CPU"
"Right-size all development services"
"Stop all non-production environments"

# Recommendations
"Should I scale up or down?"
"Optimize resource allocation for my-api"
"Suggest better CPU/memory settings"
```

### API Endpoints for Optimization

```bash
# Base URL: https://api.qovery.com
# Auth: Authorization: Token $QOVERY_API_TOKEN

# Costs
GET /organization/{orgId}/currentCost
GET /organization/{orgId}/cluster/{clusterId}/currentCost
GET /organization/{orgId}/invoice

# Metrics
GET /cluster/{clusterId}/metrics?query={promql}&range={duration}&step={interval}

# Service configuration
GET /application/{appId}                        # CPU, memory, instances
PUT /application/{appId}                        # Update CPU, memory, instances

# Cloud provider instance types (for reference)
GET /organization/{orgId}/cloudProvider/aws/instanceType
GET /organization/{orgId}/cloudProvider/gcp/instanceType
GET /organization/{orgId}/cloudProvider/azure/instanceType
GET /organization/{orgId}/cloudProvider/scaleway/instanceType

# Environment management
POST /environment/{envId}/deploy                # Redeploy after changes
POST /environment/{envId}/stop                  # Stop environment
POST /environment/{envId}/restart               # Restart environment
```

### CLI Commands for Optimization

```bash
qovery cluster list          # Cluster overview
qovery service list          # Service overview with resource info
qovery status                # Current status
qovery application env list  # Check env var configuration
```

---

## Reference Links

- **Qovery Optimization Guide**: https://www.qovery.com/docs/getting-started/guides/qovery-101/optimize
- **Deployment Rules (Scheduling)**: https://www.qovery.com/docs/configuration/deployment-rule
- **Kubecost Integration**: https://www.qovery.com/docs/configuration/integrations/observability/kubecost
- **Copilot Optimization Capabilities**: https://www.qovery.com/docs/copilot/capabilities/optimization
- **Cluster Metrics API**: https://www.qovery.com/docs/api-reference/clusters/fetch-cluster-metrics
- **Billing API**: https://www.qovery.com/docs/api-reference/billing/get-cluster-current-cost
- **KEDA Autoscaling**: https://www.qovery.com/docs/configuration/application#keda-event-driven
- **Qovery Deploy Skill**: https://github.com/Qovery/qovery-skills (for deploying new applications)
- **Qovery Troubleshoot Skill**: https://github.com/Qovery/qovery-skills (for fixing deployment issues)
- **Qovery Support**: support@qovery.com
- **Community Forum**: https://discuss.qovery.com
