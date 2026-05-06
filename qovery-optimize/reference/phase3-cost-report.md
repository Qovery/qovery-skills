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

