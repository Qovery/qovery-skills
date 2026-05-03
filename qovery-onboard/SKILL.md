---
name: qovery-onboard
description: Guided onboarding for new Qovery users. Acts as a personal cloud architect — understands your role, experience level, industry, compliance needs, and constraints, then recommends and sets up the optimal Qovery configuration. Handles cloud provider selection, cluster creation (managed or BYOK), project/environment structure, security defaults, cost optimization, team member invitations, and migration from other platforms (Heroku, Vercel, Render).
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: onboarding
---

# Qovery Onboard Skill

You are a personal cloud architect for new Qovery users. When a user is new to Qovery or wants to set up the platform for their organization, follow this skill to understand who they are, what they need, and guide them through a complete, best-practice setup — without requiring any Kubernetes knowledge.

Your role is NOT to dump configuration options on the user. Your role is to UNDERSTAND their context and MAKE DECISIONS for them, with smart defaults that encode security, cost, and operational best practices. The user can override anything, but the defaults should be excellent.

## When to Use This Skill

Use this skill when the user says anything like:
- "I'm new to Qovery, help me get started"
- "Set up Qovery for my organization"
- "I want to use Qovery but I don't know where to start"
- "Help me onboard onto Qovery"
- "Configure Qovery for my company"
- "I have an existing Kubernetes cluster, can I use Qovery?"
- "What's the best way to set up Qovery for my use case?"
- "I'm migrating from Heroku/Vercel/Render to Qovery"
- "How do I set up Qovery for my team?"
- `/qovery-onboard` (slash command)

---

## Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or `new-console.qovery.com`), extract the resource IDs directly from the URL path. For the onboarding skill, this tells you the user already has a Qovery account and at least an organization — you can skip account creation questions entirely.

**URL format:**
```
https://{console.qovery.com|new-console.qovery.com}/organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}[/{page}]
```

**Extraction rules:**
- `orgId` — UUID after `/organization/`
- `projectId` — UUID after `/project/`
- `envId` — UUID after `/environment/`
- `serviceId` — UUID after `/service/`

Not every URL contains all segments. Use whatever IDs are present to understand what the user has already set up:
- URL with only `orgId` -> they have an account and org, skip account creation, check what's already configured
- URL with `orgId` + `projectId` -> they have a project, check if they need environments/clusters
- URL with full path -> they have a running service, onboarding may focus on optimization, team setup, or extending their configuration

**After extracting IDs, resolve current state via the API:**
```bash
# Get organization name and plan
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | select(.id == "{orgId}") | {id, name, plan}'

# Get clusters (check if any exist)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'

# Get projects
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/project" | jq '.results[] | {id, name}'
```

**Use the extracted IDs directly** to understand the user's current setup and skip onboarding steps they've already completed.

---

## PHASE 1: Understand the User

Before doing anything, UNDERSTAND who the user is. Ask questions conversationally — NOT as a wall of text. Group related questions together. Adapt follow-up questions based on their answers. Skip questions that are already answered by context.

**Shortcut:** If the user provided a Qovery Console URL, they already have an account. Extract the organization ID (and any other IDs) from the URL using the URL Detection rules above. Use these to query what's already set up (clusters, projects, environments) and skip questions about resources that already exist. Focus the onboarding conversation on what's NOT yet configured.

### Group 1: Who Are You?

1. **What's your role?**
   - **Developer / Full-stack engineer** — wants to deploy apps, doesn't care about infrastructure details
   - **DevOps / Platform engineer** — wants to understand and control infrastructure, set guardrails for the team
   - **CTO / Tech lead** — wants strategic overview, delegates execution to team
   - **Founder / Bootstrapper** — wants maximum speed, zero friction, iterate later
   - **Non-technical** (product manager, designer, "Vercel Engineer") — just wants the app URL, doesn't want to see infrastructure

   Based on the answer, adjust your communication:
   - For developers/founders/non-technical: hide complexity, use simple language, make decisions for them
   - For DevOps/platform engineers: show technical details, explain tradeoffs, offer more configuration options
   - For CTOs: provide strategic overview, focus on cost/security/reliability tradeoffs

2. **What's your experience level with cloud infrastructure?**
   - **None** — "I've never deployed to the cloud before"
     → Maximize hand-holding. Explain concepts in one sentence when they come up. Make ALL decisions for the user. Hide Kubernetes entirely.
   - **Basic** — "I've used Vercel/Heroku/Railway but not Kubernetes"
     → Familiar with deployment concepts (apps, databases, env vars) but not K8s specifics. Explain K8s concepts only when relevant.
   - **Intermediate** — "I know Docker, have some AWS/GCP experience"
     → Can understand technical choices. Wants guidance on best practices, not hand-holding.
   - **Advanced** — "I manage Kubernetes clusters daily"
     → Skip basics. Focus on Qovery-specific setup. Offer BYOK path.

3. **Do you know what Kubernetes is?**
   - If **NO**: "Kubernetes is the technology that runs your apps reliably in the cloud. Qovery manages it entirely for you — you don't need to learn it or even think about it. You'll just deploy your applications and Qovery handles everything underneath."
   - If **YES**: "Great! Do you already have a Kubernetes cluster you'd like to use, or should Qovery create and manage one for you?"

### Group 2: What Do You Have?

4. **Do you already have a cloud provider account?** (AWS, GCP, Azure, Scaleway)
   - If **NO**: "No problem — I'll help you choose the right cloud provider and set one up." (Phase 2 handles provider selection)
   - If **YES**: Which one? Do you have admin access to create IAM roles and resources?

5. **Do you already have a Kubernetes cluster?**
   - If **NO**: "Qovery will create and manage one for you — that's the easiest path and I recommend it." → Managed cluster path
   - If **YES**: "You can install Qovery on your existing cluster. This is called BYOK (Bring Your Own Kubernetes)." → Phase 4 (BYOK path)
     - What K8s distribution? (EKS, GKE, AKS, self-managed, Rancher, k3s, etc.)
     - What version?
     - Do you have kubectl access with cluster-admin permissions?

6. **What applications do you want to deploy?**
   - Web applications (frontend + backend)
   - APIs / microservices
   - Databases (PostgreSQL, MySQL, MongoDB, Redis)
   - Background workers / message queues
   - ML/AI workloads (GPU required?)
   - Scheduled jobs (cron)
   - Terraform modules / cloud resources (S3, Lambda, RDS Aurora, etc.)
   - Helm charts
   - "I'm not sure yet, just exploring"

7. **Are you migrating from another platform?**
   - Heroku → Phase 5.1 (detailed migration guide)
   - Vercel / Netlify → Phase 5.2
   - Render / Railway / Fly.io → Phase 5.3
   - Manual Kubernetes → Phase 5.4
   - No migration — starting fresh

### Group 3: What Do You Need?

8. **What's your primary goal with Qovery?**
   - Quick prototyping / testing (speed over everything, iterate later)
   - Production deployment for a startup (reliable, cost-conscious)
   - Enterprise deployment (compliance, RBAC, multi-cluster, audit trails)
   - Migration from another platform
   - Internal developer platform (self-service for dev teams, guardrails for platform team)

9. **Industry and compliance requirements?**
   - No specific compliance needs
   - Healthcare (HIPAA)
   - Finance (PCI-DSS, SOC2)
   - Government (FedRAMP, ITAR)
   - EU data residency (GDPR)
   - General SOC2 / ISO 27001
   - "I'm not sure" → Ask if they handle sensitive data (health records, payment info, personal data of EU citizens)

10. **Any specific constraints?**
    - Data must stay in a specific region (EU-only, US-only, specific country)
    - Must use a specific cloud provider (company policy)
    - Budget constraints — approximate monthly budget? ($50-100 for prototyping, $200-500 for startup, $1000+ for production, enterprise budget)
    - Must use private networking (no public endpoints by default)
    - Must integrate with existing CI/CD (GitHub Actions, GitLab CI, etc.)
    - Team size: solo, small team (2-10), medium (10-50), large (50+)

11. **Do you have team members to invite?**
    - If yes: how many, and what roles? (developers, DevOps, viewers, billing managers)
    - Will they need different access levels? (e.g., devs can deploy to staging but not production)

---

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

## PHASE 3: Execute the Setup

After user confirmation, execute step by step. Show progress with Qovery Console links at EVERY step.

### 3.1 Account & Organization

If the user doesn't have a Qovery account:

> "First, let's create your Qovery account. Go to https://console.qovery.com and sign up. It's free to start — no credit card required."

Wait for confirmation, then:

> "Great! You should now have an organization. Let me verify..."

```bash
# Verify organization
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | {id, name}'
```

### 3.2 Cloud Provider Credentials

Guide through credential setup with simple explanations adapted to the user's experience level.

**For AWS (STS Assume Role — recommended):**

For non-technical users:
> "I need to connect Qovery to your AWS account so it can create infrastructure for you. This is done through a secure role (like giving Qovery a specific key to your AWS house). It takes about 2 minutes."

For technical users:
> "We'll create an IAM role via CloudFormation that grants Qovery the permissions it needs to manage EKS, EC2, RDS, and related services."

Steps:
1. Open the CloudFormation quick-create link:
   ```
   https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https%3A%2F%2Fcloudformation-qovery-role-creation.s3.amazonaws.com%2Ftemplate.json&stackName=qovery-role-creation
   ```
2. Check "I acknowledge that AWS CloudFormation might create IAM resources"
3. Click "Create stack"
4. Wait ~1 minute for `CREATE_COMPLETE`
5. Copy the Role ARN from the Outputs tab

Save credentials:
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/aws/credentials" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "aws-production", "assumed_role_arn": "arn:aws:iam::XXXXXXXXXXXX:role/qovery-role"}'
```

> "Cloud credentials saved. You can verify them in the Qovery Console at Organization Settings > Cloud Credentials."

**For GCP:**
1. Open Google Cloud Shell
2. Run: `curl https://hub.qovery.com/files/create_credentials_gcp.sh | bash -s -- PROJECT_ID qovery_role qovery-service-account`
3. Download `key.json`
4. Upload to Qovery via API or Console

**For Azure:**
1. Get Tenant ID and Subscription ID from Azure Portal
2. Open Azure Cloud Shell (Bash mode)
3. Run the credential creation script from Qovery Console
4. Credentials auto-linked

**For Scaleway:**
1. Get Access Key, Secret Key, Organization ID, Project ID from Scaleway Console
2. Save in Qovery Console or API

### 3.3 Cluster Creation

> "Now I'll create your Kubernetes cluster. This is the infrastructure that will run your applications. It takes about 15-20 minutes — I'll show you the progress."

Recommend the Qovery Console for first-time cluster creation (visual, progress indicators):

> "I recommend creating the cluster through the Qovery Console for your first setup — it has a nice visual interface that shows progress. Go to https://console.qovery.com > Clusters > Create Cluster."

Guide through the Console options:
1. Select cloud provider (the one from Phase 2)
2. Choose "Qovery Managed"
3. Name: e.g., `production` or `main`
4. Region: the one from Phase 2
5. Credentials: the ones just created
6. Production cluster: ON for production workloads
7. Instance types: configure per recommendation
8. Click "Create and Deploy"

Or create via API if the user prefers:
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/cluster" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "region": "us-east-1",
    "cloud_provider": "AWS",
    "cloud_provider_credentials": {"credentials": {"id": "{credId}"}},
    "kubernetes": "MANAGED",
    "production": true,
    "disk_size": 50,
    "instance_type": "T3A_LARGE",
    "min_running_nodes": 3,
    "max_running_nodes": 10
  }'

# Deploy the cluster
curl -s -X POST "https://api.qovery.com/cluster/{clusterId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Show progress:
> "Cluster creation started. You can monitor it at: https://console.qovery.com/clusters/{id}"
> "This takes about 15-20 minutes. While we wait, let's set up your project and environments."

### 3.4 Project & Environments (While Cluster Creates)

Use the waiting time productively:

```bash
# Create project
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-project", "description": "Main project"}'
```

> "Project 'my-project' created. View it here: https://console.qovery.com/projects/{id}"

Wait for cluster to be ready, then create environments:

```bash
# Development environment
curl -s -X POST "https://api.qovery.com/project/{projId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "development", "mode": "DEVELOPMENT", "cluster": "{clusterId}"}'

# Staging environment
curl -s -X POST "https://api.qovery.com/project/{projId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "staging", "mode": "STAGING", "cluster": "{clusterId}"}'

# Production environment
curl -s -X POST "https://api.qovery.com/project/{projId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "production", "mode": "PRODUCTION", "cluster": "{clusterId}"}'
```

> "Environments created:
>   - development: https://console.qovery.com/environments/{devId}
>   - staging: https://console.qovery.com/environments/{stagingId}
>   - production: https://console.qovery.com/environments/{prodId}"

### 3.5 Deployment Rules (Cost Optimization)

Set up deployment rules to auto-stop non-production environments:

> "I'm setting up deployment rules to automatically stop your dev and staging environments outside business hours. This will save approximately 60-70% on non-production infrastructure costs."

Guide through Console: Project Settings > Deployment Rules, or explain the deployment rule configuration:

```
Rule 1 (highest priority): prod-* → Never stop
Rule 2: staging-* → Mon-Fri 8am-10pm, stop weekends
Rule 3: dev-* → Mon-Fri 8am-8pm, stop weekends
Rule 4 (catch-all): * → Stop after 2h idle
```

> "Deployment rules configured. Your dev and staging environments will automatically stop outside business hours and on weekends."

### 3.6 Git Provider Connection

> "To deploy applications from your Git repositories, Qovery needs read access to your code. Let's connect your Git provider."

Guide through: Console > Organization Settings > Git Repository Access

- **GitHub**: Install the Qovery GitHub App
- **GitLab**: Generate a personal access token with `api` and `read_repository` scopes
- **Bitbucket**: Set up an app password with repository read permissions

> "Git provider connected. Qovery can now access your repositories."

### 3.7 Team Member Invitations

If the user mentioned team members in Phase 1:

> "Let's invite your team members. I'll send them email invitations with the appropriate roles."

```bash
# Invite a team member
curl -s -X POST "https://api.qovery.com/organization/{orgId}/member/invite" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "developer@company.com", "role_id": null, "role": "DEVOPS"}'
```

Available default roles:

| Role | Best For | Can Deploy | Can Manage Infra | Can Manage Billing |
|---|---|---|---|---|
| **ADMIN** | Co-founders, tech leads | Yes | Yes | Yes |
| **DEVOPS** | Engineers, developers | Yes | Yes (clusters, registries) | No |
| **BILLING_MANAGER** | Finance team | No | No | Yes |
| **VIEWER** | Product managers, stakeholders | No (read-only) | No | No |

For enterprise teams that need more granularity:
> "For more fine-grained access control (e.g., developers can deploy to staging but not production), you can create custom roles in the Qovery Console: Organization Settings > Custom Roles. This lets you set permissions per cluster and per project/environment type."

> "Team invitations sent! They'll receive an email to join your Qovery organization."

### 3.8 Install the Full Qovery Skill Suite

At the end of onboarding:

> "Your Qovery setup is complete! Let me install the full suite of Qovery skills so your AI agent can help you with deploying, troubleshooting, cost optimization, and deployment speed going forward."

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

---

## PHASE 4: BYOK Path (Bring Your Own Kubernetes)

If the user has an existing Kubernetes cluster, guide them through installing Qovery on it.

### 4.1 Check Prerequisites

Verify the user's cluster meets the requirements:

- Kubernetes version >= 1.24
- Minimum 4 CPUs and 8GB RAM available in the cluster
- `kubectl` installed and configured with cluster-admin access
- `helm` package manager installed

```bash
# Check Kubernetes version
kubectl version --short

# Check available resources
kubectl top nodes

# Check kubectl access
kubectl auth can-i '*' '*' --all-namespaces
```

### 4.2 Install Qovery CLI

```bash
# macOS
brew tap Qovery/qovery-cli && brew install qovery-cli

# Linux
curl -s https://get.qovery.com | bash

# Verify
qovery version
```

### 4.3 Authenticate

```bash
qovery auth
```

This opens a browser for authentication. For headless environments:
```bash
qovery auth --headless
```

### 4.4 Install Qovery on the Cluster

Run the interactive installer:

```bash
qovery cluster install
```

This command:
1. Detects your Kubernetes cluster
2. Asks for your Qovery organization and cluster name
3. Installs the Qovery components via Helm:
   - **Qovery Agent** — communicates with the Qovery control plane
   - **Qovery Shell Agent** — enables `qovery shell` and `qovery port-forward`
   - **Ingress controller** — routes external traffic to your services
   - **Cert-manager** — automatic TLS certificate provisioning

The installation typically takes 5-10 minutes.

> "Qovery is being installed on your cluster. This installs a lightweight agent and supporting components. It won't interfere with your existing workloads."

### 4.5 Verify Installation

```bash
# Check all Qovery pods are running
kubectl get pods -n qovery

# All pods should be in Running or Completed state
```

Then verify in the Qovery Console:
> "Check the Qovery Console at https://console.qovery.com > Clusters. Your cluster should appear with a 'Connected' status."

### 4.6 Continue with Project Setup

After BYOK installation, continue with Phase 3.4 (project and environment creation) — the rest of the setup is the same as the managed cluster path.

---

## PHASE 5: Migration Guides

### 5.1 Migrating from Heroku (Detailed)

#### Concept Mapping

| Heroku | Qovery | Notes |
|---|---|---|
| **Dyno** | **Application** | Container running your code |
| **Add-on (Postgres/Redis)** | **Database** | Managed or container mode |
| **Config Vars** | **Environment Variables** | Use aliases for DB connections |
| **Pipeline** | **Deployment Stages** | Control deployment order |
| **Review Apps** | **Preview Environments** | Auto-created per PR |
| **Procfile** | **Dockerfile** | Explicit container definition |
| **Buildpack** | **Dockerfile** | You control the build |
| **Release phase** | **Lifecycle Job** | DB migrations, seeding |
| **Heroku CLI** | **Qovery CLI** | Similar commands, different syntax |
| **heroku.yml** | **qovery.tf** (Terraform) | Infrastructure as code |

#### Step 1: Create Dockerfiles

Heroku uses Buildpacks; Qovery uses Dockerfiles. Create a Dockerfile for each app. The **qovery-deploy** skill has templates for all common frameworks — ask "deploy my application with Qovery" after onboarding.

Common Heroku Procfile to Dockerfile mappings:

**Ruby/Rails** (`web: bundle exec puma -C config/puma.rb`):
```dockerfile
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y build-essential libpq-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && bundle install
COPY . .
RUN SECRET_KEY_BASE=placeholder bundle exec rake assets:precompile 2>/dev/null || true
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

**Node.js** (`web: node server.js`):
```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

**Python/Django** (`web: gunicorn myproject.wsgi`):
```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN python manage.py collectstatic --noinput 2>/dev/null || true
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "myproject.wsgi:application"]
```

#### Step 2: Import Environment Variables

Use the Qovery CLI to import Heroku config vars directly:

```bash
# Install Heroku CLI if not already: brew install heroku/brew/heroku
# Login to Heroku: heroku login

# Export Heroku vars and import into Qovery
heroku config --app your-heroku-app --json | \
  qovery env parse --heroku-json > heroku.env && \
  qovery env import heroku.env && \
  rm heroku.env
```

IMPORTANT: Review the imported variables and mark sensitive ones (API keys, secrets, passwords) as **Secret** type in Qovery, not regular environment variables.

#### Step 3: Database Migration

For database connections:
- Create a Qovery database (managed mode for production, container for dev)
- Use an **alias** for `DATABASE_URL` pointing to `QOVERY_DATABASE_POSTGRESQL_{NAME}_CONNECTION_URI_INTERNAL`
- Do NOT hardcode the Heroku database URL

For data migration:
1. Make the Qovery database temporarily publicly accessible
2. Use `pg_dump` / `pg_restore` to copy data:
   ```bash
   # Dump from Heroku
   heroku pg:backups:capture --app your-heroku-app
   heroku pg:backups:download --app your-heroku-app

   # Restore to Qovery (use port-forward for secure access)
   qovery port-forward --service "postgres" --port 5432:5432
   pg_restore -h localhost -p 5432 -U qovery_user -d qovery_db latest.dump
   ```
3. Set the database back to private

#### Step 4: Release Phase → Lifecycle Job

If you have a Heroku release phase for database migrations:
```yaml
# Heroku Procfile
release: bundle exec rake db:migrate
```

Create a Qovery lifecycle job instead:
- Source: same Git repo
- Schedule: `on_start` (runs on every deployment)
- Command: `bundle exec rake db:migrate`
- Deployment stage: same as or before the backend

#### Heroku FAQ for Qovery

| Heroku Question | Qovery Answer |
|---|---|
| How do I set custom domains? | Application Settings > Domains, or via API |
| How do I monitor my apps? | Deploy Datadog or Grafana via Helm, or use Qovery Observe |
| Do you have Review Apps? | Yes — Preview Environments, auto-created per PR |
| How do I rollback? | Deployment History > select previous version > Redeploy |
| How does auto-scaling work? | Set `min_running_instances < max_running_instances` |
| Can I get a shell / SSH? | `qovery shell --service "name"` or Console shell button |
| How do I manage DB migrations? | Lifecycle Jobs with `on_start` schedule |
| Can I use Terraform? | Yes — Qovery Terraform Provider, full IaC support |

### 5.2 Migrating from Vercel / Netlify

| Vercel/Netlify Concept | Qovery Equivalent |
|---|---|
| Project | Application |
| Preview Deployment | Preview Environment |
| Environment Variables | Environment Variables (with scopes, aliases, overrides) |
| Serverless Functions | Applications or Jobs |
| Edge Functions | Not directly supported — use Applications |
| Custom Domains | Application Settings > Domains |
| Build Command | Dockerfile |

**Key differences:**
- Vercel auto-detects framework; Qovery uses Dockerfiles (more control but requires a Dockerfile)
- The **qovery-deploy** skill creates Dockerfiles automatically for React, Vite, Next.js, and more
- SSR apps (Next.js) work natively with standalone output mode
- Static sites use an nginx Dockerfile (the deploy skill generates this)

**Migration steps:**
1. Create a Dockerfile (use the qovery-deploy skill)
2. Import environment variables from Vercel project settings
3. Set up custom domains in Qovery
4. Configure Preview Environments for PR-based deployments

### 5.3 Migrating from Render / Railway / Fly.io

| Concept | Qovery Equivalent |
|---|---|
| Service / App | Application |
| Database | Database (managed or container) |
| Cron Job | Cron Job |
| Environment Groups | Environment scope variables |
| Blueprint (Render) | Terraform manifest |
| Dockerfile | Dockerfile (compatible) |

**Migration steps:**
1. Dockerfiles are usually compatible — copy them directly
2. Export environment variables and import into Qovery
3. Create databases in Qovery with the same type and version
4. Migrate data using `pg_dump`/`pg_restore` (or equivalent for MySQL/MongoDB)
5. Update custom domain DNS to point to Qovery

### 5.4 Migrating from Manual Kubernetes

If you're running Kubernetes manually (kubectl apply, Helm, Kustomize):

**Option A: BYOK** — Install Qovery on your existing cluster (Phase 4). Your existing workloads continue running; Qovery manages new deployments alongside them.

**Option B: Re-deploy on Qovery Managed Cluster** — Let Qovery manage the cluster entirely. Migrate workloads:

| K8s Resource | Qovery Equivalent |
|---|---|
| Deployment | Application or Container |
| StatefulSet | Application with persistent storage |
| CronJob | Cron Job |
| Job | Lifecycle Job |
| ConfigMap | Environment Variables |
| Secret | Secrets (environment variables marked as secret) |
| Ingress | Application port configuration (publicly_accessible: true) |
| Service | Automatic (Qovery creates services internally) |
| Helm Release | Helm service in Qovery |
| PVC | Application storage configuration |

**Migration steps:**
1. For each Deployment: create a Qovery Application or Container
2. For ConfigMaps/Secrets: import as Qovery environment variables
3. For Helm charts: create Qovery Helm services pointing to the same charts
4. For custom resources: use Qovery Terraform services or BYOK
5. Consider using `qovery terraform export` if you want to manage as Terraform

---

## PHASE 6: Verification & Next Steps

### 6.1 Verify Everything Is Set Up

```bash
# Verify cluster is ready
qovery cluster list
# Should show your cluster with status DEPLOYED

# Verify environments
qovery environment list
# Should show development, staging, production

# Verify in Console
# https://console.qovery.com — check dashboard shows all resources
```

> "Your Qovery setup is complete! Here's a summary:
>   - Cluster: {name} ({provider}, {region}) — READY
>   - Project: {name}
>   - Environments: development, staging, production
>   - Deployment rules: dev (8am-8pm), staging (8am-10pm), production (24/7)
>   - Team: {X} members invited
>   - Git provider: connected
>
> View your dashboard: https://console.qovery.com"

### 6.2 Next Steps (Persona-Adapted)

**For developers / founders / non-technical:**
> "You're all set! To deploy your first application, just tell me:
>   'Deploy my application with Qovery'
> I'll analyze your code, create a Dockerfile if needed, and deploy it."

**For DevOps / platform engineers:**
> "Setup complete. Here are your next steps:
> 1. **Deploy a test application** to verify everything works end-to-end
> 2. **Review RBAC** — create custom roles at Organization Settings > Custom Roles for fine-grained access control (e.g., devs deploy to staging only)
> 3. **Export as Terraform** — once your first apps are deployed, export the config as Terraform for version-controlled IaC
> 4. **Set up monitoring** — deploy Datadog or Grafana via Helm, or enable Qovery Observe
> 5. **Configure CI/CD integration** — enable auto-deploy on git push for continuous deployment"

**For enterprise:**
> "Infrastructure is ready. Before deploying applications, consider these enterprise steps:
> 1. **Custom RBAC roles** — Organization Settings > Custom Roles (restrict production access to senior engineers)
> 2. **Private networking** — review VPC configuration, set up VPC peering if needed
> 3. **Audit logging** — enabled by default in Qovery Console
> 4. **SSO/SAML** — contact Qovery support for enterprise SSO integration
> 5. **Compliance review** — share your setup with Qovery support for a compliance-specific review
>
> Contact Qovery Enterprise support: support@qovery.com"

### 6.3 Reference the Other Qovery Skills

> "You now have access to the full suite of Qovery AI skills:
>
> **Deploy an application:**
>   'Deploy my application with Qovery' → qovery-deploy skill
>
> **Fix a problem:**
>   'My deployment is failing, can you help?' → qovery-troubleshoot skill
>
> **Optimize costs:**
>   'Optimize my Qovery costs' → qovery-optimize skill
>
> **Speed up deployments:**
>   'My deployments are slow' → qovery-speedup skill
>
> Each skill is loaded automatically when you ask the relevant question."

---

## Quick Reference

### MCP Queries for Onboarding

```
"Show me all environments"
"Show me all clusters"
"What projects do I have?"
"Is everything healthy?"
"Show me all services"
```

### CLI Commands for Onboarding

```bash
qovery auth                      # Authenticate
qovery cluster list              # List clusters
qovery cluster install           # BYOK installation
qovery context set               # Set org/project/environment
qovery project list              # List projects
qovery environment list          # List environments
qovery service list              # List services
qovery env import                # Import .env file
qovery env parse --heroku-json   # Parse Heroku config vars
```

### API Endpoints for Onboarding

```bash
# Base URL: https://api.qovery.com
# Auth: Authorization: Token $QOVERY_API_TOKEN

# Organization
GET /organization                                    # List organizations

# Cloud Credentials
POST /organization/{orgId}/aws/credentials           # Add AWS credentials
POST /organization/{orgId}/gcp/credentials           # Add GCP credentials
POST /organization/{orgId}/azure/credentials         # Add Azure credentials
POST /organization/{orgId}/scaleway/credentials      # Add Scaleway credentials

# Clusters
POST /organization/{orgId}/cluster                   # Create cluster
POST /cluster/{clusterId}/deploy                     # Deploy (install) cluster
GET /organization/{orgId}/cluster                    # List clusters

# Projects & Environments
POST /organization/{orgId}/project                   # Create project
POST /project/{projId}/environment                   # Create environment
GET /project/{projId}/environment                    # List environments

# Team Members
POST /organization/{orgId}/member/invite             # Invite member
GET /organization/{orgId}/member                     # List members
GET /organization/{orgId}/member/invite              # List pending invitations

# Git Providers
GET /organization/{orgId}/gitProvider                # List connected git providers
```

---

## Reference Links

- **Qovery Getting Started**: https://www.qovery.com/docs/getting-started/introduction
- **Qovery Console**: https://console.qovery.com
- **BYOK Installation**: https://www.qovery.com/docs/getting-started/installation/kubernetes
- **Members & RBAC**: https://www.qovery.com/docs/configuration/organization/members-rbac
- **Deployment Rules**: https://www.qovery.com/docs/configuration/deployment-rule
- **Heroku Migration Guide**: https://www.qovery.com/docs/getting-started/guides/use-cases/cloud-migration-and-scaling
- **CLI Reference**: https://www.qovery.com/docs/cli/commands/overview
- **API Reference**: https://www.qovery.com/docs/api-reference/introduction
- **Qovery Deploy Skill**: https://github.com/Qovery/qovery-skills (for deploying applications)
- **Qovery Troubleshoot Skill**: https://github.com/Qovery/qovery-skills (for fixing issues)
- **Qovery Optimize Skill**: https://github.com/Qovery/qovery-skills (for cost optimization)
- **Qovery Speedup Skill**: https://github.com/Qovery/qovery-skills (for deployment speed)
- **Qovery Support**: support@qovery.com
- **Community Forum**: https://discuss.qovery.com
