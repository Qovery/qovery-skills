---
name: qovery-optimize
description: Reduces Kubernetes cluster and application costs on Qovery. Analyzes historical resource consumption, factors in the user's business context (seasonal patterns, growth stage, reliability requirements), estimates external resource costs from public cloud pricing, and proposes right-sizing, autoscaling, environment scheduling, spot instances, and database mode changes. Generates a cost report with CSV export and applies changes via CLI+API or Terraform. Use when the user asks to reduce costs, right-size, or optimize Qovery resource spend.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: optimization
---

# Qovery Optimize Skill

This skill reduces Kubernetes infrastructure costs on Qovery via right-sizing, autoscaling, environment scheduling, spot instances, and database mode changes.

It is NOT about blindly reducing everything to minimum. It is **intelligent optimization** that:
- Understands the business context (seasonal peaks, growth expectations, reliability needs)
- Analyzes historical resource consumption, not just current allocation
- Respects safety margins appropriate for each environment
- Estimates external cloud resource costs from public pricing data
- Presents recommendations with expected savings AND risks

## Usage Tracking

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
QOVERY_ORG_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq -r '.results[0].id' 2>/dev/null)
SKILL_NAME="qovery-optimize"
curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-optimize (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  -d "{\"skill_name\":\"${SKILL_NAME}\"}" > /dev/null 2>&1 || true
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

## When to Use This Skill

Trigger phrases:
- "Optimize my Qovery costs"
- "Right-size my Kubernetes resources"
- "How can I reduce my cloud spending?"
- "My AWS bill is too high"
- "Make my cluster cheaper"
- "Audit my Qovery spending"
- `/qovery-optimize` (slash command)

For slow deployments use `qovery-speedup`. For deployment failures use `qovery-troubleshoot`.

## Workflow checklist

```
Cost Optimization Progress:
- [ ] Phase 1 — Context gathering (auth, business context, resource metrics)
- [ ] Phase 2 — Analysis across 7 optimization dimensions
- [ ] Phase 3 — Generate cost report (Markdown + CSV)
- [ ] Phase 4 — Apply approved changes (CLI+API or Terraform) + USER CONFIRMATION per change
- [ ] Phase 5 — Set up ongoing monitoring & follow-up
- [ ] Phase 6 — Document seasonal & special considerations
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-context-gathering.md](reference/phase1-context-gathering.md) | Inventory, business context, resource metrics queries |
| Phase 2 | [reference/phase2-optimization-dimensions.md](reference/phase2-optimization-dimensions.md) | Right-sizing, autoscaling, DB mode, scheduling, cluster, build, external resources |
| Phase 3 | [reference/phase3-cost-report.md](reference/phase3-cost-report.md) | Report template (Markdown + CSV) |
| Phase 4 | [reference/phase4-apply-changes.md](reference/phase4-apply-changes.md) | CLI+API + Terraform application paths, with per-change confirmation |
| Phase 5 | [reference/phase5-monitoring.md](reference/phase5-monitoring.md) | Ongoing dashboards, alert thresholds, follow-up cadence |
| Phase 6 | [reference/phase6-seasonal.md](reference/phase6-seasonal.md) | Black Friday / EOY / launch handling |

## Cloud pricing reference

For external-resource cost estimation, consult the per-provider pricing tables. These are **point-in-time public list prices** — verify against the provider's pricing page before quoting savings.

| Provider | File |
|---|---|
| AWS (EC2 / EKS / RDS / ElastiCache / infra fixed) | [reference/pricing/aws.md](reference/pricing/aws.md) |
| GCP (GKE / Cloud SQL / Cloud NAT / disks) | [reference/pricing/gcp.md](reference/pricing/gcp.md) |
| Azure (AKS / VMs / Postgres / LB) | [reference/pricing/azure.md](reference/pricing/azure.md) |
| Scaleway (Kapsule / DB / instances) | [reference/pricing/scaleway.md](reference/pricing/scaleway.md) |

## Quick reference

### MCP queries

```
# Cost analysis
"Show me monthly spending"
"What are my highest cost services?"
"Compare costs this month vs last month"

# Resource analysis
"Show CPU usage across all services"
"Find over-provisioned services"
"Find underutilized resources"

# Inactive resources
"Show environments inactive for 24 hours"
"List unused databases"
"Find idle applications"

# Actions
"Stop all development environments for the weekend"
"Scale down the backend to 250m CPU"
"Stop all non-production environments"

# Recommendations
"Should I scale up or down?"
"Optimize resource allocation for my-api"
```

### API endpoints

```
# Base URL: https://api.qovery.com   Auth: Authorization: Token $QOVERY_API_TOKEN

# Costs
GET /organization/{orgId}/currentCost
GET /organization/{orgId}/cluster/{clusterId}/currentCost
GET /organization/{orgId}/invoice

# Metrics
GET /cluster/{clusterId}/metrics?query={promql}&range={duration}&step={interval}

# Service configuration
GET /application/{appId}                                    CPU, memory, instances
PUT /application/{appId}                                    Update CPU, memory, instances

# Cloud provider instance types
GET /organization/{orgId}/cloudProvider/aws/instanceType
GET /organization/{orgId}/cloudProvider/gcp/instanceType
GET /organization/{orgId}/cloudProvider/azure/instanceType
GET /organization/{orgId}/cloudProvider/scaleway/instanceType

# Environment management
POST /environment/{envId}/deploy                            Redeploy after changes
POST /environment/{envId}/stop
POST /environment/{envId}/restart
```

### CLI commands

```bash
qovery cluster list                  # Cluster overview
qovery service list                  # Service overview with resource info
qovery status                        # Current status
qovery application env list          # Check env var configuration
```

## Reference links

- **Qovery Optimization Guide**: <https://www.qovery.com/docs/getting-started/guides/qovery-101/optimize>
- **Deployment Rules (Scheduling)**: <https://www.qovery.com/docs/configuration/deployment-rule>
- **Kubecost Integration**: <https://www.qovery.com/docs/configuration/integrations/observability/kubecost>
- **Copilot Optimization Capabilities**: <https://www.qovery.com/docs/copilot/capabilities/optimization>
- **Cluster Metrics API**: <https://www.qovery.com/docs/api-reference/clusters/fetch-cluster-metrics>
- **Billing API**: <https://www.qovery.com/docs/api-reference/billing/get-cluster-current-cost>
- **KEDA Autoscaling**: <https://www.qovery.com/docs/configuration/application#keda-event-driven>
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Speedup Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Support**: <support@qovery.com>
- **Community Forum**: <https://discuss.qovery.com>
