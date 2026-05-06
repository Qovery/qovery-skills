## PHASE 2: Recommend the Right Setup

Based on the user's answers, generate a personalized setup recommendation. Present it clearly before executing.

### 2.1 Cloud Provider Recommendation

| User Context | Recommended Provider | Region | Reasoning |
|---|---|---|---|
| No preference, US-based | AWS | us-east-1 | Widest service coverage, Karpenter cost optimization, largest ecosystem |
| No preference, EU-based | AWS | eu-west-1 | EU data center, GDPR compliant, full AWS feature set |
| EU data residency required | AWS eu-west-1 or Scaleway fr-par | EU | Strict GDPR compliance |
| Already on GCP | GCP | us-central1 or closest | Keep existing ecosystem, use existing credits/billing |
| Already on Azure | Azure | eastus or closest | Keep existing ecosystem, Azure AD integration |
| Cost-sensitive startup / prototyping | Scaleway | fr-par | Simple pricing, often cheaper, European, GDPR-friendly |
| ML/AI with GPUs | AWS or GCP | us-east-1 or us-central1 | Best GPU instance availability (p3, g4dn, g5 on AWS; T4, A100 on GCP) |
| Finance (PCI-DSS) | AWS or Azure | Closest compliant region | Best compliance certifications and audit tools |
| Healthcare (HIPAA) | AWS | us-east-1 or us-west-2 | HIPAA BAA available, widest HIPAA-eligible services |
| Government (FedRAMP) | AWS GovCloud or Azure Gov | gov regions | FedRAMP authorized regions |

### 2.2 Cluster Type Recommendation

| User Context | Recommendation | Why |
|---|---|---|
| New to K8s, wants easy path | **Qovery Managed Cluster** | Qovery creates and manages everything — zero K8s knowledge needed |
| Has existing K8s cluster | **BYOK** | Install Qovery on top via `qovery cluster install` |
| Enterprise, multi-team, isolation needed | **Multiple Qovery Managed Clusters** | Separate production from non-production for security isolation |
| Solo developer, prototyping | **Single Qovery Managed Cluster** | One cluster for all environments, lowest cost |
| Advanced user, specific requirements | **BYOK or Managed** — let them choose | Explain tradeoffs |

### 2.3 Environment Structure Recommendation

| Context | Projects | Environments per Project |
|---|---|---|
| Solo dev, prototyping | 1 project | `development`, `production` |
| Small team, single product | 1 project | `development`, `staging`, `production` |
| Small team, multiple products | 1 project per product | `development`, `staging`, `production` each |
| Medium team, single product | 1 project | `development`, `staging`, `production` + preview environments per PR |
| Large org, multiple products | 1 project per product/team | `development`, `staging`, `production` each, with deployment rules |
| Enterprise | Multiple projects with RBAC | Full environment structure with custom roles per team |

### 2.4 Security Best Practices (Baked In by Default)

These are NOT optional recommendations. They are the DEFAULT setup. The user would have to explicitly opt out.

- Databases are **PRIVATE** (never publicly accessible) — use `qovery port-forward` for local access
- Production environments use **PRODUCTION** mode (stricter defaults)
- Sensitive environment variables use the **secret** type (encrypted at rest, not readable via API)
- Internal service communication uses **`_HOST_INTERNAL`** variables (not external)
- Health checks are **always configured** (TCP or HTTP probe on every service)
- Deployment stages ensure **dependencies start first** (DB before backend, backend before frontend)
- API tokens use **minimum required permissions** (generate per-skill, not org-admin)

### 2.5 Cost Best Practices (Baked In by Default)

- Dev/staging environments get **deployment rules** (auto-stop overnight and weekends — saves 60-70%)
- Dev databases use **container mode** (not managed — saves 60-80% on non-production databases)
- Production databases use **managed mode** (reliability, backups, failover)
- Karpenter configured with **10-20 instance types** for optimal bin-packing and cost
- **Spot instances** enabled for non-production workloads (60-70% compute savings)
- Resource allocation **right-sized from the start** (not over-provisioned)

### 2.6 RBAC Recommendation

| Team Size | Recommended Roles |
|---|---|
| Solo | Just the owner — no RBAC needed |
| 2-5 (startup) | Owner + Admin for co-founder + DevOps for engineers |
| 5-20 (growing) | Owner + Admin + DevOps for engineers + Viewer for stakeholders |
| 20+ (enterprise) | Custom roles: production deploy restricted to senior devs, staging open to all devs, viewer for PMs |

### 2.7 Present the Recommendation

Show the user a clear summary before doing anything:

```
Based on your answers, here's my recommended Qovery setup:

CLOUD PROVIDER
  Provider: AWS
  Region: us-east-1
  Reason: Best overall coverage, Karpenter cost optimization

CLUSTER
  Type: Qovery Managed
  Instance types: t3.small, t3.medium, t3.large, m5.large, m6i.large, c5.large, r5.large
  Spot instances: Enabled for non-production
  Disk: 50GB gp3 per node

PROJECT & ENVIRONMENTS
  Project: "my-project"
  Environments:
    - development  (auto-stop: Mon-Fri 8am-8pm, container-mode databases)
    - staging      (auto-stop: Mon-Fri 8am-10pm)
    - production   (24/7, managed databases, min 2 instances per service)

SECURITY
  - Private databases (no public access)
  - Internal networking for service communication
  - Secrets encrypted at rest
  - Health checks on every service
  - Deployment stages: Infrastructure → Backend → Frontend

COST ESTIMATE
  Cluster: ~$150-300/month (depends on workload)
  Services: per-service costs depend on CPU/memory allocation
  Savings from deployment rules: ~$200-350/month on non-production

TEAM
  {X members to invite with roles}

Shall I proceed with this setup? You can customize anything before I start.
```

Wait for confirmation. If the user wants changes, adjust and re-present.

---

