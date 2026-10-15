---
name: qovery-optimize
description: Reduces Kubernetes cluster and application costs on Qovery. Analyzes historical resource consumption, factors in the user's business context (seasonal patterns, growth stage, reliability requirements), estimates external resource costs from public cloud pricing, and proposes right-sizing, autoscaling, environment scheduling, spot instances, and database mode changes. When Qovery observability is enabled on the cluster, right-sizing uses KRR (Kubernetes Resource Recommender) for P99-based, OOM-aware per-container recommendations. Generates a cost report with CSV export and applies changes via CLI+API or Terraform. Use when the user asks to reduce costs, right-size, run KRR, or optimize Qovery resource spend.
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

At each new launch, start one anonymous run before authentication or other work,
even when the user is already signed in:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-optimize
```

Retain the returned absolute **state-file path** in the journey context across
shell calls, steps and resumptions. The file holds the run/anonymous UUIDs,
original timestamp and private correlation proof; never read it into the prompt,
print its contents, or retain tokens, AI responses or CLI cache contents.
The helper requires macOS, Linux or WSL with Bash and curl. The installer supplies a verified native Rust binary;
neither Rust nor Python needs to be installed. Native Windows is unsupported.
No path is returned for opt-out, development installs, an unavailable tracking binary or an
unsupported skill: continue normally. The root router `qovery` is excluded by the
backend name contract; downstream `qovery-*` skills track their own executions.

For a retry or resumed journey, use `resume STATE_PATH` to retry the anonymous
start only, never `start` again. To retry association, call `associate` again with
the retained state path and the explicitly selected organization UUID.
After login and **explicit organization selection/creation**, run:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' associate 'STATE_PATH' --organization 'ORGANIZATION_UUID'
```

Replace those placeholders with the retained path and selected UUID. Already
signed-in users follow the same start → associate order. Do not guess the first
organization returned by an API. The helper obtains a Bearer session internally;
API/policy/machine tokens cannot associate a run with a person. Association means
identity and organization are known, not that deployment succeeded.
One run has one immutable account/organization association. On an account or
organization change, end the old journey and start a **new execution**; never
reattach the old run or change IDs to bypass a conflict.

Requests run in the background with bounded deadlines. Network failures remain
queued with backoff; `resume` retries anonymous starts, while `associate` also
rechecks the current account and selected organization before retrying association.
Keep the path on interruption. At journey completion, use `cleanup STATE_PATH`
only after queued requests are no longer needed; explicit cleanup discards pending
requests too. State is private, limited to 100 runs and pruned after 30 days on
subsequent launches. Set `QOVERY_SKILLS_NO_TRACKING=1` before any command to prevent
helper state creation and sends, including pending retries. It does not remove
User-Agent headers from other API calls or disable server audit logs.
`cleanup` still removes state.
`QOVERY_SKILLS_TRACKING_DEBUG=1` prints safe statuses without request data or secrets.
Never call the legacy tracking endpoint as a fallback.

> **API rule:** send this exact `User-Agent` header on **every** `curl` call to `api.qovery.com`, spelled out in full each time — a shell variable set in one command is gone by the next one:
>
> ```
> -H "User-Agent: QoverySkill/qovery-optimize (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
> ```

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
- [ ] Phase 2 — Analysis across 7 optimization dimensions (right-sizing via KRR when observability is enabled)
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
| Phase 2b | [reference/phase2b-krr-rightsizing.md](reference/phase2b-krr-rightsizing.md) | KRR-based right-sizing when Qovery observability is enabled (setup, run, guardrails) |
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
qovery cluster analysis cost-recommendation -c <cluster-id>   # Server-side KRR right-sizing (observability required)
qovery cluster analysis logs -c <cluster-id> -a <analysis-id> # Report of a past analysis
```

## Reference links

- **Qovery Optimization Guide**: <https://www.qovery.com/docs/getting-started/guides/qovery-101/optimize>
- **KRR (Kubernetes Resource Recommender)**: <https://github.com/robusta-dev/krr>
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
