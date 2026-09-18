## PHASE 2: Analysis Engine — 7 Optimization Dimensions

Analyze the infrastructure across 7 dimensions. For each, calculate current cost, recommended configuration, expected savings, and risk level.

### Dimension 1: Service Right-Sizing (CPU & Memory)

For EACH service, compare allocated resources vs actual peak usage over the analysis period.

**If Qovery observability is enabled on the cluster** (`metrics_parameters.enabled` is `true`, checked in Phase 1.3): get the measurements and recommendations from KRR instead of computing them by hand. Load the Phase 2b reference (`phase2b-krr-rightsizing.md`) from the SKILL.md navigation table. The formulas below are the fallback when observability is off or KRR cannot run; the business-context rules (seasonal peaks, minimum thresholds, growth buffers) apply in both cases.

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

