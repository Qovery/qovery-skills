---
name: qovery-deploy
description: Deploy any application, database, Helm chart, or Terraform module to Kubernetes using Qovery. Analyzes your codebase, creates missing Dockerfiles, provisions databases (container or managed), sets up environment variables, and deploys via Qovery CLI + API or Terraform provider. Supports Node.js, Python, Go, Java, Ruby, PHP, .NET, React, Vite, Next.js and more.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: deployment
---

# Qovery Deploy Skill

You are an expert at deploying applications to Kubernetes using Qovery. When a user asks you to deploy their application with Qovery, follow this skill to analyze their project, ask the right questions, prepare everything (including creating Dockerfiles if missing), and deploy using either the Qovery CLI + API or the Qovery Terraform provider.

## When to Use This Skill

Use this skill when the user says anything like:
- "Deploy my application with Qovery"
- "Set up Qovery for my project"
- "I want to deploy this to Kubernetes"
- "Help me deploy to the cloud with Qovery"
- "Can you create a Qovery configuration for my app?"

---

## PHASE 1: Discovery & User Questionnaire

Before doing anything, you MUST gather information by asking the user these questions. Do NOT skip this phase. Ask them conversationally, not as a wall of text — group related questions together.

### Group 1: Qovery Account & Infrastructure

#### Step 1: Authenticate

Before asking any questions, try to detect an existing token automatically:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set in the environment
2. If not, check if the CLI is authenticated: look for `~/.qovery/context.json` with a valid `access_token`
3. If the CLI is authenticated, you can generate a token via `qovery token --name "deploy-skill"` (see Phase 2)
4. As a fallback, the CLI's JWT token from `~/.qovery/context.json` can be used directly with `Authorization: Bearer <jwt>` instead of `Authorization: Token <api-token>`
- Only ask the user to manually create a token at Qovery Console > Organization Settings > API Tokens if none of the above options work
- Tokens should be stored securely (never commit to git)

#### Step 2: Resolve Organization

After authenticating, **proactively list all organizations** the user has access to:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | {id, name}'
```

- **If 0 organizations**: The user does not have a Qovery account or has not been invited to any organization. Direct them to sign up at https://console.qovery.com — they need an organization before anything else.
- **If 1 organization**: Confirm with the user and move on:
  > "I found your organization: **{name}**. I'll use this one."
- **If multiple organizations**: Present the full list and ask the user to choose. Do NOT silently pick the first one:
  > "I found multiple Qovery organizations on your account:
  > 1. **Acme Corp** (id: abc-123)
  > 2. **Personal Projects** (id: def-456)
  > 3. **Staging Org** (id: ghi-789)
  >
  > Which organization should I deploy to?"

Store the selected organization ID — it will be used for all subsequent API calls.

#### Step 3: Resolve Cluster

After selecting the organization, **proactively list all clusters** in that organization:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'
```

- **If 0 clusters**: The user MUST create a cluster before deploying. Go to **Phase 2B: Cluster Setup** after completing Phase 2 prerequisites. Cluster creation takes 15-30 minutes.
- **If 1 cluster**: Confirm the cluster details with the user:
  > "I found one cluster: **{name}** ({cloud_provider}, {region}, status: {status}). I'll deploy to this cluster."
  - If the cluster status is NOT `DEPLOYED` or `READY`, warn the user: "This cluster is currently in **{status}** state and cannot accept deployments. Please wait for it to be ready or choose a different cluster."
- **If multiple clusters**: Present the full list with key details and ask the user to choose. Do NOT silently pick one:
  > "I found multiple clusters in your organization:
  >
  > | # | Name | Provider | Region | Status |
  > |---|------|----------|--------|--------|
  > | 1 | production | AWS | us-east-1 | DEPLOYED |
  > | 2 | staging | AWS | eu-west-1 | DEPLOYED |
  > | 3 | dev | GCP | us-central1 | DEPLOYED |
  >
  > Which cluster should I deploy to?"
  - Only show clusters with `DEPLOYED` or `READY` status as valid options. If a cluster is in another state, list it but mark it as unavailable (e.g., "~~dev~~ (status: DEPLOYING — not ready)").

IMPORTANT: Do NOT skip the cluster check. Without a running cluster, no services can be deployed. Store the selected cluster ID — it will be used when creating environments.

#### Step 4: Resolve Project & Environment

Ask the user:

4. **Do you already have a Qovery project and environment, or should we create them?**
   - If they have existing ones, ask for the names (you will look them up via the API using the resolved organization ID)
   - If not, you will create them in the selected organization, targeting the selected cluster

### Group 2: Project Analysis

Before asking more questions, **analyze the codebase yourself** by looking at:

- `package.json` — Node.js (check for `next`, `react`, `vite`, `express`, `fastify`, `nestjs`)
- `go.mod` / `go.sum` — Go
- `requirements.txt` / `pyproject.toml` / `Pipfile` — Python (check for `flask`, `django`, `fastapi`, `uvicorn`, `gunicorn`)
- `pom.xml` / `build.gradle` / `build.gradle.kts` — Java (check for `spring-boot`)
- `Gemfile` — Ruby (check for `rails`)
- `composer.json` — PHP (check for `laravel`)
- `*.csproj` / `*.sln` — .NET
- `Dockerfile` — Already has one?
- `.dockerignore` — Exists?
- `docker-compose.yml` / `docker-compose.yaml` — Multi-service architecture?
- `.env` / `.env.example` / `.env.local` — Environment variables?
- `*.tf` — Terraform modules?
- `Chart.yaml` — Helm chart?

Then tell the user what you detected and ask:

5. **Is my analysis correct?** (confirm language, framework, detected services)

6. **What port does your application listen on?** (often detectable from code, but confirm)

7. **Should the application be publicly accessible?** (exposed to the internet via HTTPS)

### Group 3: Database & Services

8. **Does your project need a database?**
   - If YES: which type? (PostgreSQL, MySQL, MongoDB, Redis)
   - Look for database connection strings in code, ORM configs (Prisma, TypeORM, SQLAlchemy, GORM, etc.)

9. **Is this deployment for development/testing or production?**
   - **Dev/test** -> Database in Container mode (cheaper, runs on the Kubernetes cluster, fast to provision)
   - **Production** -> Database in Managed mode (cloud-managed, e.g. AWS RDS — higher availability, automated backups) OR via a Terraform service for advanced setups like RDS Aurora Serverless

10. **Do you need any additional cloud resources?** (S3 buckets, Redis cache, message queues, Lambda functions, CDN, etc.)
    - These can be provisioned via Qovery Terraform services

### Group 4: Deployment Method

11. **How would you like to deploy?**
    - **Option A: CLI + API** — Quickest way to get started. Good for development and staging environments. Uses `qovery` CLI commands and `curl` API calls to create and deploy services.
    - **Option B: Terraform Provider (Recommended for production)** — Declarative, reproducible, version-controlled infrastructure as code. Creates a `qovery.tf` file that defines your entire stack. Can be committed to git and used in CI/CD pipelines.

After gathering all answers, proceed to the appropriate phase.

---

## PHASE 2: Prerequisites & Authentication

### Install Qovery CLI

The CLI is needed regardless of the deployment method (even with Terraform, the CLI is useful for monitoring, logs, and shell access).

```bash
# macOS (Homebrew)
brew tap Qovery/qovery-cli
brew install qovery-cli

# Linux
curl -s https://get.qovery.com | bash

# Windows (Scoop)
scoop bucket add qovery https://github.com/Qovery/scoop-qovery-cli
scoop install qovery-cli

# Docker
docker run ghcr.io/qovery/qovery-cli:latest help

# Verify installation
qovery version
```

### Authenticate

```bash
# Interactive browser-based login
qovery auth

# OR for headless environments, set an existing API token
export QOVERY_CLI_ACCESS_TOKEN="your-api-token"
```

### Set Context

The CLI uses a context-based approach. Set your default organization, project, and environment:

```bash
# Interactive context selection
qovery context set

# Verify
qovery project list
qovery environment list
```

### Obtain an API Token for API Calls

Many operations in this skill use the Qovery REST API directly (via `curl`). You need a token for the `Authorization` header. Try these methods in order — use the first one that works:

**Method 1: Generate a token via the CLI (preferred)**

If the user is already authenticated via `qovery auth`, the CLI can generate an API token without leaving the terminal:

```bash
# Generate a named token (easy to identify and clean up later)
qovery token --name "deploy-skill-$(date +%Y%m%d)"

# The command outputs the token — save it
export QOVERY_API_TOKEN="qov_..."
```

Use this token in API calls with the header: `Authorization: Token $QOVERY_API_TOKEN`

This token is permanent (no expiration) and can be deleted later from the Qovery Console (Organization Settings > API Tokens) or via the API when no longer needed. The agent should offer to clean it up after deployment is complete (see Phase 9).

**Method 2: Use the CLI's JWT token (fallback)**

If `qovery token` fails (e.g., insufficient permissions), the CLI stores a JWT token locally after authentication. This can be used directly:

```bash
# Extract JWT from CLI context
export QOVERY_JWT_TOKEN=$(cat ~/.qovery/context.json | jq -r '.access_token')
```

Use this token with a **Bearer** header instead of Token: `Authorization: Bearer $QOVERY_JWT_TOKEN`

IMPORTANT: JWT tokens expire (check the `access_token_expiration` field in `context.json`). If the token is expired, re-authenticate with `qovery auth` to refresh it. API tokens from Method 1 do not expire.

**Method 3: User provides an existing API token (manual)**

If the user already has an API token from the Qovery Console:

```bash
export QOVERY_API_TOKEN="your-existing-token"
```

**Method 4: Generate from the Qovery Console (last resort)**

Direct the user to: Qovery Console > Organization Settings > API Tokens > Generate.

**Summary of auth headers used in this skill:**

| Token Source | Header Format |
|---|---|
| API Token (from `qovery token` or Console) | `Authorization: Token $QOVERY_API_TOKEN` |
| JWT Token (from `~/.qovery/context.json`) | `Authorization: Bearer $QOVERY_JWT_TOKEN` |

All `curl` examples in this skill use `Authorization: Token $QOVERY_API_TOKEN`. If you are using a JWT token instead, replace `Token` with `Bearer` in the header.

### Install Terraform (if using Terraform path)

```bash
# macOS
brew install terraform

# Linux
curl -fsSL https://releases.hashicorp.com/terraform/1.13.0/terraform_1.13.0_linux_amd64.zip -o terraform.zip
unzip terraform.zip && sudo mv terraform /usr/local/bin/

# Verify
terraform version
```

---

## PHASE 2B: Cluster Setup (New Accounts / No Existing Cluster)

SKIP this phase entirely if the user already has a running cluster in Qovery. Only follow this phase if:
- The user has a brand new Qovery account with no clusters, OR
- The user explicitly asks to create a new cluster

Cluster creation takes 15-30 minutes. The user needs to complete this before any services can be deployed.

### 2B.1 Choose a Cloud Provider

Ask the user which cloud provider they want to use:

| Provider | Kubernetes Service | Best For |
|----------|-------------------|----------|
| **AWS** (Recommended) | EKS with Karpenter | Most popular, widest feature support, cost optimization via Karpenter + Spot |
| **GCP** | GKE Autopilot | Fully managed nodes, pay-per-pod billing, zero node management |
| **Azure** | AKS | Microsoft ecosystem, Azure AD integration |
| **Scaleway** | Kapsule | European cloud, simple pricing, GDPR-friendly |

### 2B.2 Create Cloud Provider Credentials

Each cloud provider requires credentials so Qovery can manage infrastructure in the user's cloud account. Guide the user through the appropriate process:

#### AWS Credentials (STS Assume Role — Recommended)

This is the most secure method. It uses temporary credentials that auto-rotate.

1. **Open the CloudFormation quick-create link** in AWS Console:
   ```
   https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https%3A%2F%2Fcloudformation-qovery-role-creation.s3.amazonaws.com%2Ftemplate.json&stackName=qovery-role-creation
   ```
   This creates an IAM role with the permissions Qovery needs (EC2, EKS, IAM, ELB, S3, RDS, ElastiCache, CloudWatch, etc.).

2. **In AWS CloudFormation Console**:
   - Click Next (template is pre-filled)
   - Keep default stack name `qovery-role-creation`
   - Click Next twice (skip options and tags)
   - Check "I acknowledge that AWS CloudFormation might create IAM resources"
   - Click "Create stack"

3. **Wait ~1 minute** for status to change to `CREATE_COMPLETE`

4. **Copy the Role ARN** from the Outputs tab (looks like `arn:aws:iam::123456789012:role/qovery-role`)

5. **Save credentials in Qovery** via Console (Organization Settings > Cloud Credentials > Add) or via API:
   ```bash
   curl -s -X POST "https://api.qovery.com/organization/{orgId}/aws/credentials" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "aws-production",
       "assumed_role_arn": "arn:aws:iam::123456789012:role/qovery-role"
     }'
   ```

**AWS Credentials (Static Keys — Alternative)**

If the user cannot use STS Assume Role:

1. Create an IAM user `qovery` in AWS Console
2. Apply the Qovery IAM policy: download from `https://www.qovery.com/docs/files/qovery-iam-aws.json`
3. Create access keys for the user (Security Credentials > Create access key)
4. Save in Qovery:
   ```bash
   curl -s -X POST "https://api.qovery.com/organization/{orgId}/aws/credentials" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "aws-production",
       "access_key_id": "AKIA...",
       "secret_access_key": "..."
     }'
   ```

#### GCP Credentials

1. **Get the GCP Project ID** from the Google Cloud Console project selector
2. **Open Google Cloud Shell** (terminal icon in top-right of Google Cloud Console)
3. **Run the Qovery credential creation script**:
   ```bash
   curl https://hub.qovery.com/files/create_credentials_gcp.sh | bash -s -- YOUR_PROJECT_ID qovery_role qovery-service-account
   ```
   This enables required APIs, creates a service account, assigns IAM roles, and generates a `key.json` file.
4. **Download `key.json`** from Cloud Shell (More menu > Download > enter `key.json`)
5. **Upload to Qovery Console** (Organization Settings > Cloud Credentials > Add GCP) or save via API:
   ```bash
   curl -s -X POST "https://api.qovery.com/organization/{orgId}/gcp/credentials" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "gcp-production",
       "gcp_credentials": "'"$(cat key.json | base64)"'"
     }'
   ```

IMPORTANT: The `key.json` file grants access to the GCP project. Never commit it to git.

#### Azure Credentials

1. **Get your Tenant ID**: Azure Portal > Azure Active Directory > Overview > copy Tenant ID
2. **Get your Subscription ID**: Azure Portal > Subscriptions > copy Subscription ID
3. **Open Azure Cloud Shell** (>_ icon in top navigation) — select **Bash** mode (not PowerShell)
4. **Go to Qovery Console** > Clusters > Create Cluster > Select Azure > Enter Tenant ID and Subscription ID
5. **Copy the generated command** from Qovery Console and run it in Azure Cloud Shell
   - This creates a service principal and assigns Contributor role
   - Credentials are automatically linked to your Qovery organization

#### Scaleway Credentials

1. **Get your Scaleway Access Key and Secret Key** from the Scaleway Console > IAM > API Keys
2. **Get your Organization ID and Project ID** from Scaleway Console
3. **Save in Qovery Console** (Organization Settings > Cloud Credentials > Add Scaleway) or via API

### 2B.3 Create the Cluster

After credentials are set up, create the cluster. There are three options:

#### Option A: Via Qovery Console (Recommended for first-time setup)

This is the easiest way to create your first cluster:

1. Go to https://console.qovery.com
2. Click **Clusters** in the left sidebar
3. Click **Create Cluster**
4. Select your cloud provider (AWS / GCP / Azure / Scaleway)
5. Choose **Qovery Managed** (recommended) or **Self-Managed (BYOK)** if you have an existing cluster
6. Configure:
   - **Cluster name**: e.g., `production` or `staging`
   - **Region**: Choose the region closest to your users
   - **Credentials**: Select the credentials you just created
   - **Production cluster**: Toggle ON if this is for production workloads
7. Configure resources (depends on provider):
   - **AWS**: Select instance types for Karpenter (recommend selecting 10-20 types across t3, m5, m6i families), enable Spot instances for cost savings, set disk size (minimum 20GB)
   - **GCP**: GKE Autopilot handles node provisioning automatically
   - **Azure**: Select VM sizes (e.g., Standard_D2ads_v5 for general purpose)
   - **Scaleway**: Select node type and count
8. Configure features (VPC, Static IP, etc.) — defaults are fine for most users
9. Click **Create and Deploy**
10. Wait 15-30 minutes for the cluster to be ready

#### Option B: Via Qovery API

```bash
# Step 1: Get your credentials ID
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/aws/credentials" | jq '.results[] | {id, name}'

# Step 2: Create the cluster
curl -s -X POST "https://api.qovery.com/organization/{orgId}/cluster" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "region": "us-east-1",
    "cloud_provider": "AWS",
    "cloud_provider_credentials": {
      "credentials": {
        "id": "{credentialsId}"
      }
    },
    "kubernetes": "MANAGED",
    "production": true,
    "disk_size": 50,
    "instance_type": "T3A_LARGE",
    "min_running_nodes": 3,
    "max_running_nodes": 10
  }' | jq '{id, name, status}'

# Step 3: Deploy (install) the cluster
curl -s -X POST "https://api.qovery.com/cluster/{clusterId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json"
```

Adapt `cloud_provider`, `region`, and `instance_type` for other providers:
- GCP: `"cloud_provider": "GCP"`, `"region": "us-central1"`
- Azure: `"cloud_provider": "AZURE"`, `"region": "eastus"`, `"instance_type": "STANDARD_D2ADS_V5"`
- Scaleway: `"cloud_provider": "SCW"`, `"region": "fr-par"`

#### Option C: Via Terraform Provider

```hcl
# AWS credentials
resource "qovery_aws_credentials" "my_aws_creds" {
  organization_id   = var.qovery_organization_id
  name              = "aws-production"
  access_key_id     = var.aws_access_key_id
  secret_access_key = var.aws_secret_access_key
}

# Cluster
resource "qovery_cluster" "production" {
  organization_id   = var.qovery_organization_id
  credentials_id    = qovery_aws_credentials.my_aws_creds.id
  name              = "production"
  cloud_provider    = "AWS"
  region            = "us-east-1"
  instance_type     = "T3A_LARGE"
  disk_size         = 50
  min_running_nodes = 3
  max_running_nodes = 10
}
```

For GCP:
```hcl
resource "qovery_gcp_credentials" "my_gcp_creds" {
  organization_id = var.qovery_organization_id
  name            = "gcp-production"
  credentials     = file("key.json")
}

resource "qovery_cluster" "production" {
  organization_id = var.qovery_organization_id
  credentials_id  = qovery_gcp_credentials.my_gcp_creds.id
  name            = "production"
  cloud_provider  = "GCP"
  region          = "us-central1"
}
```

For Azure:
```hcl
resource "qovery_azure_credentials" "my_azure_creds" {
  organization_id = var.qovery_organization_id
  name            = "azure-production"
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
}

resource "qovery_cluster" "production" {
  organization_id = var.qovery_organization_id
  credentials_id  = qovery_azure_credentials.my_azure_creds.id
  name            = "production"
  cloud_provider  = "AZURE"
  region          = "eastus"
  instance_type   = "STANDARD_D2ADS_V5"
}
```

For Scaleway:
```hcl
resource "qovery_scaleway_credentials" "my_scw_creds" {
  organization_id         = var.qovery_organization_id
  name                    = "scaleway-production"
  scaleway_access_key     = var.scaleway_access_key
  scaleway_secret_key     = var.scaleway_secret_key
  scaleway_project_id     = var.scaleway_project_id
  scaleway_organization_id = var.scaleway_organization_id
}

resource "qovery_cluster" "production" {
  organization_id = var.qovery_organization_id
  credentials_id  = qovery_scaleway_credentials.my_scw_creds.id
  name            = "production"
  cloud_provider  = "SCW"
  region          = "fr-par"
}
```

### 2B.4 Wait for Cluster to Be Ready

Cluster creation takes 15-30 minutes. Here's what happens during this time:

| Step | Time | What's Being Created |
|------|------|---------------------|
| 1. Networking | 3-5 min | VPC, subnets, security groups, NAT gateways |
| 2. Kubernetes Control Plane | 10-15 min | EKS/GKE/AKS master nodes |
| 3. Worker Nodes | 5-10 min | Compute instances for your workloads |
| 4. Qovery Components | 3-5 min | Ingress controller, cert-manager, monitoring |

Monitor the cluster status:

```bash
# Via CLI
qovery cluster list

# Via API (poll until status is DEPLOYED or READY)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {name, status, deployment_status}'
```

Once the cluster status shows **DEPLOYED** or **READY**, proceed to Phase 3.

IMPORTANT: Tell the user they can continue analyzing their codebase and preparing Dockerfiles (Phases 3-5) while waiting for the cluster. The cluster only needs to be ready before the final deployment step.

---

## PHASE 3: Codebase Analysis & Dockerfile Creation

### 3.1 Check for Existing Dockerfile

Look for `Dockerfile` in the project root or in subdirectories for monorepos. If one exists and looks correct, use it. If it is missing or incomplete, create one using the templates below.

### 3.2 Create .dockerignore

If no `.dockerignore` exists, always create one. Adapt based on the detected language:

```dockerignore
# Common
.git
.gitignore
.env
.env.*
*.md
LICENSE
docker-compose*.yml
.dockerignore
Dockerfile

# Node.js
node_modules
npm-debug.log
.next
.nuxt
dist
coverage
.nyc_output

# Python
__pycache__
*.pyc
.venv
venv
.pytest_cache
.mypy_cache

# Go
vendor (if not using go mod vendor)

# Java
target
build
.gradle
.idea

# General
.vscode
.idea
*.swp
*.swo
```

### 3.3 Dockerfile Templates

Use the appropriate template based on the detected language/framework. All templates follow best practices: multi-stage builds, non-root user, minimal final image.

#### Node.js — Express / Fastify / NestJS (API server)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build 2>/dev/null || true

FROM node:22-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist 2>/dev/null || true
COPY --from=builder /app/src ./src 2>/dev/null || true
COPY --from=builder /app/. ./ 2>/dev/null || true
USER appuser
EXPOSE 3000
CMD ["node", "src/index.js"]
```

IMPORTANT: Adapt the CMD to match the actual entry point found in `package.json` scripts (`start` or `main` field). Adjust the EXPOSE port to match the actual port the app listens on.

#### Next.js (SSR / Full-Stack)

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
USER appuser
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

IMPORTANT: Next.js standalone output must be enabled. Check `next.config.js` or `next.config.mjs` and add if missing:
```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
};
module.exports = nextConfig; // or: export default nextConfig;
```

#### React / Vite (SPA — Static Frontend)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
# For React (CRA), use /app/build instead of /app/dist

# SPA routing support — serve index.html for all routes
RUN printf 'server {\n\
    listen 80;\n\
    server_name _;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
    location /assets {\n\
        expires 1y;\n\
        add_header Cache-Control "public, immutable";\n\
    }\n\
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

IMPORTANT: For Vite projects the build output is in `dist/`. For Create React App (CRA) projects it is in `build/`. Check `package.json` or the framework config to confirm.

#### Python — Flask

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
USER appuser
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "app:app"]
```

IMPORTANT: Adjust the `app:app` in the CMD to match the actual Flask application module and variable name (e.g., `wsgi:app`, `main:create_app()`). If gunicorn is not in requirements.txt, add it.

#### Python — Django

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN python manage.py collectstatic --noinput 2>/dev/null || true
USER appuser
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "myproject.wsgi:application"]
```

IMPORTANT: Replace `myproject` with the actual Django project name (the directory containing `wsgi.py`). If gunicorn is not in requirements.txt, add it.

#### Python — FastAPI

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

IMPORTANT: Adjust `main:app` to match the actual module and FastAPI app variable. If uvicorn is not in requirements.txt, add it.

#### Go

```dockerfile
FROM golang:1.24-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/server .
USER appuser
EXPOSE 8080
CMD ["./server"]
```

IMPORTANT: If the main package is not in the root directory, adjust the build command (e.g., `go build -o /app/server ./cmd/server`). Check `go.mod` for the module path.

#### Java — Spring Boot (Maven)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY pom.xml .
COPY .mvn .mvn
COPY mvnw .
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B
COPY src ./src
RUN ./mvnw package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
USER appuser
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

#### Java — Spring Boot (Gradle)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY build.gradle* settings.gradle* gradlew ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon
COPY src ./src
RUN ./gradlew bootJar --no-daemon -x test

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
USER appuser
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

#### Ruby — Rails

```dockerfile
FROM ruby:3.3-slim AS builder
RUN apt-get update && apt-get install -y build-essential libpq-dev nodejs npm && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && bundle config set --local without 'development test' && bundle install
COPY . .
RUN SECRET_KEY_BASE=placeholder bundle exec rake assets:precompile 2>/dev/null || true

FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y libpq-dev && rm -rf /var/lib/apt/lists/*
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /app /app
USER appuser
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

#### PHP — Laravel

```dockerfile
FROM composer:2 AS deps
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

FROM php:8.3-fpm-alpine AS builder
RUN apk add --no-cache postgresql-dev && docker-php-ext-install pdo_pgsql
WORKDIR /app
COPY --from=deps /app/vendor ./vendor
COPY . .
RUN composer dump-autoload --optimize --no-dev

FROM php:8.3-fpm-alpine
RUN apk add --no-cache nginx postgresql-dev && docker-php-ext-install pdo_pgsql
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app /app
COPY nginx.conf /etc/nginx/http.d/default.conf
RUN chown -R appuser:appgroup /app/storage /app/bootstrap/cache
EXPOSE 80
CMD ["sh", "-c", "php-fpm -D && nginx -g 'daemon off;'"]
```

#### .NET

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder
WORKDIR /app
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=builder /app/publish .
USER appuser
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
CMD ["dotnet", "MyApp.dll"]
```

IMPORTANT: Replace `MyApp.dll` with the actual assembly name from your `.csproj` file (the `<AssemblyName>` property or project file name).

---

## PHASE 3B: Deployment Plan Summary

Before executing any operations (Phase 4 or Phase 5), you MUST present a complete summary of the deployment plan to the user and get explicit confirmation. This applies to BOTH the CLI+API path and the Terraform path.

### 3B.1 Generate the Summary

Based on all information gathered in Phase 1 (user answers, resolved organization, resolved cluster) and Phase 3 (codebase analysis, Dockerfile creation), compile a deployment plan. Present it in a clear, structured format:

> **Deployment Plan**
>
> **Target Infrastructure:**
> - Organization: **{org_name}** (`{org_id}`)
> - Cluster: **{cluster_name}** ({cloud_provider}, {region})
> - Project: **{project_name}** *(new — will be created / existing)*
> - Environment: **{env_name}** (mode: {PRODUCTION/STAGING/DEVELOPMENT}) *(new — will be created / existing)*
> - Deployment method: **{CLI + API / Terraform}**
>
> **Services to deploy:**
>
> | Service | Type | Source | Port | Public | CPU | Memory |
> |---------|------|--------|------|--------|-----|--------|
> | backend | Application | git: main, path: /backend | 8080 | Yes | 500m | 512MB |
> | frontend | Application | git: main, path: /frontend | 3000 | Yes | 500m | 512MB |
> | worker | Container | registry: my-org/worker:v1.0 | — | No | 250m | 256MB |
>
> **Databases to provision:**
>
> | Name | Type | Version | Mode | Storage | Instance |
> |------|------|---------|------|---------|----------|
> | postgres | PostgreSQL | 16 | Container | 10GB | — |
> | redis | Redis | 7 | Container | 5GB | — |
>
> **Deployment stages (execution order):**
> 1. **Infrastructure**: postgres, redis
> 2. **Backend**: backend, worker
> 3. **Frontend**: frontend
>
> **Environment variables to set:**
> - `PORT` = `8080`
> - `NODE_ENV` = `production`
> - `DATABASE_URL` = alias -> `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL`
> - `JWT_SECRET` = *(secret — value provided by user)*
> - *(N other variables from .env file)*
>
> **Files to create/modify:**
> - `backend/Dockerfile` *(new — Node.js Express template)*
> - `backend/.dockerignore` *(new)*
> - `frontend/Dockerfile` *(new — Next.js template)*
> - `next.config.mjs` *(modified — added `output: 'standalone'`)*
>
> **Warnings:**
> - No `/health` endpoint detected in backend — will use TCP health check probe instead of HTTP
> - Database `postgres` is in **Container** mode — suitable for dev/test but not recommended for production workloads
> - Frontend has no `.dockerignore` — `node_modules` will be excluded via the generated file

Adapt this template to the actual services detected. Omit sections that don't apply (e.g., no "Databases" section if no databases are needed, no "Files to create" if all Dockerfiles exist).

For the **Terraform path**, also include:
> **Terraform files to generate:**
> - `qovery.tf` — main infrastructure definition
> - `variables.tf` — input variables
> - `terraform.tfvars` — variable values *(will contain org/cluster/project IDs)*

### 3B.2 Get Confirmation

After presenting the summary, ask the user for explicit confirmation:

> "Does this deployment plan look correct? I'll proceed with creating these resources once you confirm. Let me know if you want to change anything (e.g., different cluster, more memory, managed database instead of container, etc.)."

**CRITICAL: Do NOT proceed to Phase 4 or Phase 5 until the user explicitly confirms.** This is the most important checkpoint in the deployment workflow — the next phases create real cloud resources, deploy services, and may incur costs.

### 3B.3 Handle Changes

If the user wants to modify the plan:
1. Adjust the relevant settings based on their feedback
2. Re-present the **full updated summary** (not just the changed parts — the user should always see the complete picture)
3. Get confirmation again before proceeding

Common change requests:
- Switch cluster (e.g., "use staging instead of production")
- Change database mode (e.g., "use managed for production")
- Adjust resources (e.g., "give the backend 1GB memory")
- Change port or public accessibility
- Add/remove services
- Switch deployment method (CLI+API vs Terraform)

---

## PHASE 4: Deploy via CLI + API (Quick Path)

Use this path when the user chose "CLI + API" or wants the fastest way to deploy.

IMPORTANT — Authentication for API calls: All `curl` examples below use `Authorization: Token $QOVERY_API_TOKEN`. If you obtained a token via `qovery token`, use it as-is. If you are using the CLI's JWT token from `~/.qovery/context.json` instead, replace `Token` with `Bearer` in all headers:
```bash
# With API Token (from `qovery token` or Console):
-H "Authorization: Token $QOVERY_API_TOKEN"

# With JWT Token (from ~/.qovery/context.json):
-H "Authorization: Bearer $QOVERY_JWT_TOKEN"
```

### 4.1 Verify Organization, Project, and Cluster

Use the organization and cluster resolved during Phase 1 (Group 1, Steps 2-3). Before creating any resources, verify they are still in the expected state:

```bash
# Verify the selected organization exists and is accessible
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | select(.id == "{selectedOrgId}") | {id, name}'

# Verify the selected cluster is healthy and ready for deployments
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | select(.id == "{selectedClusterId}") | {id, name, status, cloud_provider, region}'

# List existing projects in the selected organization
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/project" | jq '.results[] | {id, name}'
```

**Pre-flight checks before proceeding:**
- The selected cluster status MUST be `DEPLOYED` or `READY`. If it is in any other state (`DEPLOYING`, `UPGRADING`, `ERROR`, etc.), do NOT proceed. Warn the user and either wait for the cluster or ask them to select a different one.
- If the user has not yet selected an organization or cluster (e.g., they jumped directly to Phase 4), resolve them now using the logic from Phase 1, Group 1, Steps 2-3.
- Confirm the selections match what was approved in the Phase 3B deployment plan summary.

### 4.2 Create Project (if needed)

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-project",
    "description": "My application project"
  }' | jq '{id, name}'
```

### 4.3 Create Environment (if needed)

Environment modes: `PRODUCTION`, `STAGING`, `DEVELOPMENT`, `PREVIEW`

```bash
curl -s -X POST "https://api.qovery.com/project/{projectId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "mode": "PRODUCTION",
    "cluster": "{clusterId}"
  }' | jq '{id, name, mode}'
```

### 4.4 Create Database (if needed)

#### Container Mode (dev/test — cheaper, on-cluster)

```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/database" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-postgres",
    "type": "POSTGRESQL",
    "version": "16",
    "mode": "CONTAINER",
    "accessibility": "PRIVATE",
    "cpu": 250,
    "memory": 512,
    "storage": 10
  }' | jq '{id, name, type, mode}'
```

#### Managed Mode (production — cloud-managed, e.g. AWS RDS)

```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/database" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-postgres",
    "type": "POSTGRESQL",
    "version": "16",
    "mode": "MANAGED",
    "accessibility": "PRIVATE",
    "instance_type": "db.t3.medium",
    "storage": 20
  }' | jq '{id, name, type, mode}'
```

Supported database types: `POSTGRESQL`, `MYSQL`, `MONGODB`, `REDIS`

### 4.5 Create Application (from Git Repository)

Detect the git provider from the remote URL:
```bash
git remote get-url origin
```
- `github.com` -> `GITHUB`
- `gitlab.com` or self-hosted GitLab -> `GITLAB`
- `bitbucket.org` -> `BITBUCKET`

```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/application" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-app",
    "git_repository": {
      "url": "https://github.com/user/repo",
      "branch": "main",
      "root_path": "/",
      "provider": "GITHUB"
    },
    "build_mode": "DOCKER",
    "dockerfile_path": "Dockerfile",
    "cpu": 500,
    "memory": 512,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {
        "internal_port": 8080,
        "external_port": 443,
        "protocol": "HTTP",
        "publicly_accessible": true,
        "name": "http"
      }
    ],
    "healthchecks": {
      "liveness_probe": {
        "type": {
          "http": {
            "port": 8080,
            "scheme": "HTTP",
            "path": "/health"
          }
        },
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    },
    "auto_deploy": true
  }' | jq '{id, name}'
```

IMPORTANT: Adapt these values based on the user's project:
- `provider`: `GITHUB`, `GITLAB`, or `BITBUCKET` (detect from git remote URL)
- `root_path`: `/` for single-app repos, `/backend` or `/frontend` for monorepos
- `internal_port`: The port the application actually listens on
- `protocol`: `HTTP` for web apps, `GRPC` for gRPC services, `TCP`/`UDP` for raw protocols
- `healthchecks`: Set a real health check path if the app has one (e.g., `/health`, `/api/health`, `/api/v1/health`). If the app has no health endpoint, use a TCP probe instead:
  ```json
  "healthchecks": {
    "liveness_probe": {
      "type": { "tcp": { "port": 8080 } },
      "initial_delay_seconds": 30,
      "period_seconds": 10,
      "timeout_seconds": 5,
      "success_threshold": 1,
      "failure_threshold": 3
    }
  }
  ```
- For static frontends (React/Vite with nginx), use port `80` and path `/`

### 4.6 Create Container Service (from Container Registry)

If the user has a pre-built image in a registry instead of source code:

```bash
# First, find the registry ID
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/containerRegistry" | jq '.results[] | {id, name, kind}'

# Then create the container service
curl -s -X POST "https://api.qovery.com/environment/{envId}/container" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-container",
    "registry_id": "{registryId}",
    "image_name": "my-image",
    "tag": "v1.0.0",
    "cpu": 500,
    "memory": 512,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {
        "internal_port": 8080,
        "external_port": 443,
        "protocol": "HTTP",
        "publicly_accessible": true,
        "name": "http"
      }
    ],
    "healthchecks": {}
  }' | jq '{id, name}'
```

### 4.7 Set Environment Variables

IMPORTANT: Use the right scope and mechanism to avoid duplication. See Phase 6 for the full guide on aliases, interpolation, and overrides.

**Set variables at the appropriate scope:**

```bash
# SERVICE scope — specific to one application (most common for quick path)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "PORT", "value": "8080"}'

# ENVIRONMENT scope — shared by ALL services in the environment
curl -s -X POST "https://api.qovery.com/environment/{envId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "NODE_ENV", "value": "production"}'

# PROJECT scope — shared across ALL environments in the project
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "warn"}'
```

**Add secrets (encrypted at rest, cannot be retrieved via API):**

```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "JWT_SECRET", "value": "super-secret-value"}'
```

**Create aliases for database connections (preferred — stays in sync automatically):**

For connecting to Qovery-managed databases (PostgreSQL, MySQL, MongoDB, Redis), ALWAYS prefer aliases over interpolation. An alias is a live pointer — if the database is redeployed and the host changes, the alias auto-updates.

```bash
# Create an alias: DATABASE_URL points to the built-in connection URI
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "alias_parent_id": "{sourceVariableId}"}'
```

**Use interpolation only when composing or transforming values (NOT for simple DB connections):**

```bash
# Compose a URL from multiple variables — valid use of interpolation
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "BACKEND_API_URL", "value": "https://{{BACKEND_HOST}}/api/v1"}'

# Add custom query params to a DB connection — valid use of interpolation
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "value": "{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL}}?sslmode=require&pool_size=20"}'
```

**Bulk import from .env file via CLI:**

```bash
qovery env import
```

Or via CLI commands:
```bash
# List current variables
qovery application env list

# Create at service scope
qovery application env create --key PORT --value 8080

# Create at environment scope
qovery environment env create --key NODE_ENV --value production --scope ENVIRONMENT

# Create a secret
qovery application env create --key JWT_SECRET --value "..." --secret
```

### 4.8 Deploy the Environment

```bash
# Deploy all services in the environment at once
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json"

# OR deploy a single application via CLI
qovery application deploy --application "my-app"

# OR deploy via CLI (whole environment)
qovery environment deploy
```

### 4.9 Monitor Deployment

```bash
# Check status (with live updates)
qovery status --watch

# View application logs
qovery log --application "my-app"

# List all services and their statuses
qovery service list

# Get application public URLs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/link" | jq '.results'
```

---

## PHASE 5: Deploy via Terraform Provider (Production Path)

Use this path when the user chose "Terraform" or wants a production-grade, reproducible setup. This is the RECOMMENDED approach for production environments.

### 5.1 Provider Configuration

Create a `qovery.tf` file (or `main.tf`) at the project root:

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = "~> 0.54.0"
    }
  }
}

provider "qovery" {
  token = var.qovery_access_token
}
```

### 5.2 Variables File

Create a `variables.tf`:

```hcl
variable "qovery_access_token" {
  description = "Qovery API token"
  type        = string
  sensitive   = true
}

variable "qovery_organization_id" {
  description = "Qovery Organization ID"
  type        = string
}

variable "qovery_project_id" {
  description = "Qovery Project ID"
  type        = string
}

variable "qovery_cluster_id" {
  description = "Qovery Cluster ID"
  type        = string
}

variable "environment_name" {
  description = "Name of the environment"
  type        = string
  default     = "production"
}

variable "environment_mode" {
  description = "Environment mode: PRODUCTION, STAGING, or DEVELOPMENT"
  type        = string
  default     = "PRODUCTION"
}

variable "git_repository_url" {
  description = "Git repository URL"
  type        = string
}

variable "git_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}

variable "auto_deploy_enabled" {
  description = "Enable auto-deploy on git push"
  type        = bool
  default     = true
}
```

### 5.3 Look Up Existing Resources (Alternative to hardcoding IDs)

If the user prefers looking up resources by name instead of providing IDs:

```hcl
data "qovery_organization" "my_org" {
  name = "My Organization"
}

data "qovery_project" "my_project" {
  organization_id = data.qovery_organization.my_org.id
  name            = "My Project"
}

data "qovery_cluster" "my_cluster" {
  organization_id = data.qovery_organization.my_org.id
  name            = "production"
}
```

Then use `data.qovery_project.my_project.id` instead of `var.qovery_project_id`, etc.

### 5.4 Environment

```hcl
resource "qovery_environment" "main" {
  project_id = var.qovery_project_id
  cluster_id = var.qovery_cluster_id
  name       = var.environment_name
  mode       = var.environment_mode
}
```

### 5.5 Deployment Stages

Deployment stages control the order in which services are deployed. This is critical for dependencies (e.g., database must be running before the backend starts).

```hcl
# Stage 1: Infrastructure (databases, terraform services)
resource "qovery_deployment_stage" "infrastructure" {
  environment_id = qovery_environment.main.id
  name           = "Infrastructure"
  description    = "Databases and cloud resources"
}

# Stage 2: Backend
resource "qovery_deployment_stage" "backend" {
  environment_id = qovery_environment.main.id
  name           = "Backend"
  description    = "Backend API services"
  is_after       = qovery_deployment_stage.infrastructure.id
}

# Stage 3: Frontend
resource "qovery_deployment_stage" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "Frontend"
  description    = "Frontend applications"
  is_after       = qovery_deployment_stage.backend.id
}

# Stage 4: Jobs (seed data, migrations, etc.)
resource "qovery_deployment_stage" "jobs" {
  environment_id = qovery_environment.main.id
  name           = "Jobs"
  description    = "Background jobs and data seeding"
  is_after       = qovery_deployment_stage.backend.id
}
```

### 5.6 Database — Container Mode (Dev/Test)

```hcl
resource "qovery_database" "postgres" {
  environment_id = qovery_environment.main.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "CONTAINER"
  storage        = 10
  cpu            = 250
  memory         = 512
  accessibility  = "PRIVATE"

  deployment_stage_id = qovery_deployment_stage.infrastructure.id
}
```

### 5.7 Database — Managed Mode (Production)

```hcl
resource "qovery_database" "postgres" {
  environment_id = qovery_environment.main.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "MANAGED"
  instance_type  = "db.t3.medium"
  storage        = 20
  accessibility  = "PRIVATE"

  deployment_stage_id = qovery_deployment_stage.infrastructure.id
}
```

### 5.8 Database — RDS Aurora via Terraform Service (Advanced Production)

For advanced database needs (Aurora Serverless, custom VPC configuration, etc.), use a Qovery Terraform service that runs your own Terraform module:

```hcl
resource "qovery_terraform_service" "rds_aurora" {
  environment_id      = qovery_environment.main.id
  deployment_stage_id = qovery_deployment_stage.infrastructure.id
  name                = "rds-aurora"
  description         = "AWS RDS Aurora Serverless v2 PostgreSQL"
  icon_uri            = "app://qovery-console/postgresql"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/terraform/rds-aurora"
  }

  auto_deploy = true

  engine = "TERRAFORM"
  engine_version = {
    explicit_version = "1.13"
  }

  # State managed inside the Kubernetes cluster (zero config)
  backend = {
    kubernetes = {}
  }

  job_resources = {
    cpu    = 500
    memory = 512
  }

  variables = [
    {
      key       = "aws_region"
      value     = "{{QOVERY_CLOUD_PROVIDER_REGION}}"
      is_secret = false
    },
    {
      key       = "vpc_id"
      value     = "{{QOVERY_KUBERNETES_CLUSTER_VPC_ID}}"
      is_secret = false
    },
    {
      key       = "cluster_name"
      value     = "my-aurora-cluster"
      is_secret = false
    }
  ]

  tfvars_files = []
}
```

The Terraform code in `/terraform/rds-aurora/` would be standard Terraform (e.g., `main.tf` with `aws_rds_cluster` resource). Qovery runs `terraform plan` and `terraform apply` inside a pod on the cluster, using the cluster's cloud credentials by default.

### 5.9 Application (Backend API)

```hcl
resource "qovery_application" "backend" {
  environment_id = qovery_environment.main.id
  name           = "backend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/backend"    # Adjust for monorepos, use "/" for single-app repos
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = 1
  max_running_instances = 2

  deployment_stage_id = qovery_deployment_stage.backend.id
  auto_deploy         = var.auto_deploy_enabled

  ports = [
    {
      internal_port       = 8080
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      name                = "api"
    }
  ]

  healthchecks = {
    liveness_probe = {
      type = {
        http = {
          port   = 8080
          scheme = "HTTP"
          path   = "/health"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
    readiness_probe = {
      type = {
        http = {
          port   = 8080
          scheme = "HTTP"
          path   = "/health"
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  environment_variables = [
    {
      key   = "PORT"
      value = "8080"
    },
    {
      key   = "NODE_ENV"
      value = var.environment_mode == "PRODUCTION" ? "production" : "development"
    }
  ]

  secrets = [
    {
      key   = "JWT_SECRET"
      value = var.jwt_secret
    }
  ]
}
```

IMPORTANT: Adapt `internal_port`, `healthchecks.path`, and `environment_variables` to match the user's actual application. The health check path should be a real endpoint that returns 200 OK when the app is healthy.

### 5.10 Application (Frontend — Next.js / React / Vite)

```hcl
resource "qovery_application" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "frontend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/frontend"    # Adjust for monorepos
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = 1
  max_running_instances = 2

  deployment_stage_id = qovery_deployment_stage.frontend.id
  auto_deploy         = var.auto_deploy_enabled

  ports = [
    {
      internal_port       = 3000    # 3000 for Next.js, 80 for nginx-served SPA
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      name                = "web"
    }
  ]

  healthchecks = {
    liveness_probe = {
      type = {
        http = {
          port   = 3000    # Match internal_port
          scheme = "HTTP"
          path   = "/"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  environment_variables = [
    {
      key   = "NODE_ENV"
      value = "production"
    },
    {
      key   = "NEXT_PUBLIC_API_URL"
      value = "https://{{BACKEND_HOST_EXTERNAL}}"
    }
  ]

  # Create an alias to reference the backend's external host
  environment_variable_aliases = [
    {
      key   = "BACKEND_HOST_EXTERNAL"
      value = "QOVERY_APPLICATION_Z${upper(element(split("-", qovery_application.backend.id), 0))}_HOST_EXTERNAL"
    }
  ]
}
```

IMPORTANT: The `QOVERY_APPLICATION_Z{ID_PREFIX}_HOST_EXTERNAL` pattern is how Qovery auto-generates environment variable names for service interconnection. The ID prefix is the first segment of the service UUID (before the first hyphen), uppercased, prefixed with `Z`. This alias lets the frontend reference the backend's public URL dynamically.

### 5.11 Container Service (from Registry)

```hcl
resource "qovery_container" "worker" {
  environment_id = qovery_environment.main.id
  name           = "worker"
  registry_id    = "{registry-uuid}"    # Get from Qovery Console > Organization Settings > Container Registries
  image_name     = "my-org/my-worker"
  tag            = "v1.0.0"

  cpu    = 500
  memory = 512
  min_running_instances = 1
  max_running_instances = 1

  deployment_stage_id = qovery_deployment_stage.backend.id
  auto_deploy         = true

  healthchecks = {
    liveness_probe = {
      type = {
        tcp = {
          port = 8080
        }
      }
      initial_delay_seconds = 10
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
}
```

### 5.12 Helm Chart

```hcl
# First, register the Helm repository (at organization level)
resource "qovery_helm_repository" "bitnami" {
  organization_id       = var.qovery_organization_id
  name                  = "bitnami"
  kind                  = "HTTPS"
  url                   = "https://charts.bitnami.com/bitnami"
  skip_tls_verification = false
}

# Deploy a Helm chart
resource "qovery_helm" "redis" {
  environment_id      = qovery_environment.main.id
  deployment_stage_id = qovery_deployment_stage.infrastructure.id
  name                = "redis"
  description         = "Redis cache"

  allow_cluster_wide_resources = false

  source = {
    helm_repository = {
      helm_repository_id = qovery_helm_repository.bitnami.id
      chart_name         = "redis"
      chart_version      = "20.0.0"
    }
  }

  auto_deploy = true
  timeout_sec = 600

  # Override Helm values — use qovery.env.VAR_NAME to inject Qovery env vars
  values_override = {
    file = {
      raw = {
        file1 = {
          content = <<-EOT
            architecture: standalone
            auth:
              enabled: true
              password: "qovery.env.REDIS_PASSWORD"
            master:
              resources:
                requests:
                  cpu: 250m
                  memory: 256Mi
          EOT
        }
      }
    }
  }

  ports = {
    "redis" = {
      service_name        = "redis-master"
      namespace           = null
      internal_port       = 6379
      external_port       = 6379
      protocol            = "TCP"
      publicly_accessible = false
      is_default          = true
    }
  }

  environment_variables = []
}
```

IMPORTANT: In Helm values, use `qovery.env.VARIABLE_NAME` to inject Qovery environment variables into chart values. This is a Qovery-specific macro that gets replaced at deploy time.

### 5.13 Lifecycle Job (DB Migrations / Seeding)

A lifecycle job runs automatically when an environment lifecycle event occurs (deploy, stop, or delete).

```hcl
resource "qovery_job" "db_migrate" {
  environment_id = qovery_environment.main.id
  name           = "db-migrate"

  source = {
    docker = {
      git_repository = {
        url       = var.git_repository_url
        branch    = var.git_branch
        root_path = "/backend"
      }
      dockerfile_path = "Dockerfile"
    }
  }

  # Runs on environment deploy (start)
  schedule = {
    on_start = {
      enabled   = true
      arguments = ["npm", "run", "migrate"]
    }
  }

  cpu    = 500
  memory = 512

  deployment_stage_id  = qovery_deployment_stage.backend.id
  max_duration_seconds = 600
  max_nb_restart       = 0
  auto_deploy          = true

  healthchecks = {
    liveness_probe = {
      type = {
        exec = {
          command = ["echo", "ok"]
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  # Use an alias for database connection — stays in sync automatically
  environment_variable_aliases = [
    {
      key   = "DATABASE_URL"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL"
    }
  ]
}
```

### 5.14 Cron Job

A cron job runs on a schedule defined with CRON syntax.

```hcl
resource "qovery_job" "daily_cleanup" {
  environment_id = qovery_environment.main.id
  name           = "daily-cleanup"

  source = {
    docker = {
      git_repository = {
        url       = var.git_repository_url
        branch    = var.git_branch
        root_path = "/jobs/cleanup"
      }
      dockerfile_path = "Dockerfile"
    }
  }

  schedule = {
    cronjob = {
      schedule = "0 2 * * *"    # Daily at 2 AM UTC
      command = {
        entrypoint = ""
        arguments  = []
      }
    }
  }

  cpu    = 250
  memory = 256

  deployment_stage_id  = qovery_deployment_stage.jobs.id
  max_duration_seconds = 1800
  max_nb_restart       = 0
  auto_deploy          = true

  healthchecks = {
    liveness_probe = {
      type = {
        exec = {
          command = ["echo", "ok"]
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
}
```

### 5.15 Terraform Service (S3, Lambda, CloudFront, etc.)

For any cloud resource not natively managed by Qovery, use a Terraform service. This runs your own Terraform code as a Qovery-managed job:

```hcl
resource "qovery_terraform_service" "s3_bucket" {
  environment_id      = qovery_environment.main.id
  deployment_stage_id = qovery_deployment_stage.infrastructure.id
  name                = "s3-bucket"
  description         = "AWS S3 storage bucket"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/terraform/s3-bucket"
  }

  auto_deploy = true

  engine = "TERRAFORM"    # Or "OPENTOFU" for OpenTofu
  engine_version = {
    explicit_version = "1.13"
  }

  # State managed inside the Kubernetes cluster (zero config, recommended)
  backend = {
    kubernetes = {}
  }

  job_resources = {
    cpu    = 500
    memory = 512
  }

  variables = [
    {
      key       = "aws_region"
      value     = "{{QOVERY_CLOUD_PROVIDER_REGION}}"
      is_secret = false
    },
    {
      key       = "bucket_name"
      value     = "my-app-storage"
      is_secret = false
    }
  ]

  tfvars_files = []
}
```

The Terraform code in `/terraform/s3-bucket/` would be standard Terraform (e.g., `main.tf` with `aws_s3_bucket` resource). Qovery runs `terraform plan` and `terraform apply` inside a pod on the cluster, using the cluster's cloud credentials by default.

### 5.16 Outputs

```hcl
output "environment_id" {
  value       = qovery_environment.main.id
  description = "Qovery Environment ID"
}

output "backend_id" {
  value       = qovery_application.backend.id
  description = "Backend Application ID"
}

output "backend_external_host" {
  value       = qovery_application.backend.external_host
  description = "Backend public URL"
}

output "frontend_external_host" {
  value       = qovery_application.frontend.external_host
  description = "Frontend public URL"
}

output "database_internal_host" {
  value       = qovery_database.postgres.internal_host
  description = "Database internal hostname (accessible within the cluster)"
}

output "database_port" {
  value       = qovery_database.postgres.port
  description = "Database port"
}
```

### 5.17 Terraform Values File

Create a `terraform.tfvars` (NEVER commit secrets to git — use environment variables):

```hcl
qovery_organization_id = "your-org-uuid"
qovery_project_id      = "your-project-uuid"
qovery_cluster_id      = "your-cluster-uuid"
environment_name       = "production"
environment_mode       = "PRODUCTION"
git_repository_url     = "https://github.com/user/repo"
git_branch             = "main"
auto_deploy_enabled    = true
```

For the API token, ALWAYS use an environment variable:
```bash
export TF_VAR_qovery_access_token="your-api-token"
```

### 5.18 Deploy with Terraform

```bash
# Initialize
terraform init

# Set API token (never hardcode this)
export TF_VAR_qovery_access_token="your-api-token"

# Preview changes
terraform plan

# Apply
terraform apply

# View outputs
terraform output
```

---

## PHASE 6: Environment Variables — Scopes, Aliases, Interpolation & Overrides

Qovery has a powerful environment variable system with three mechanisms that AVOID duplicating variables and keep configuration DRY. You MUST understand and use these properly.

### 6.1 Three Core Mechanisms

| Mechanism | What it does | When to use |
|---|---|---|
| **Alias** | Creates a live *reference* (pointer) to another variable. If the source changes, the alias auto-updates. | Renaming built-in variables to match what your app expects (e.g., `DATABASE_URL` as alias of `QOVERY_DATABASE_..._CONNECTION_URI`) |
| **Interpolation** | Substitutes `{{VAR_NAME}}` placeholders with variable values at deploy time. Allows composing values from multiple variables. | Building connection strings, composing URLs, embedding env names in bucket names |
| **Override** | Changes the value of a variable defined at a broader scope (project/environment) for a specific narrower scope (environment/service). | Different config per environment or service (e.g., `LOG_LEVEL=warn` at project, overridden to `debug` for one service) |

Key distinctions:
- **Alias** = "This variable IS that variable" (a live pointer — stays in sync)
- **Interpolation** = "This variable's value CONTAINS that variable's value" (string substitution at deploy time)
- **Override** = "This variable REPLACES the inherited value from a broader scope"

### 6.2 Variable Scopes & Override Hierarchy

Variables can be defined at three scopes. Narrower scopes automatically override broader ones:

```
Project Scope (broadest — shared across ALL environments)
  └── LOG_LEVEL=warn
  └── APP_NAME=myapp
  └── SUPPORT_EMAIL=support@acme.com

  Environment Scope (shared across all services in ONE environment)
    └── LOG_LEVEL=info              ← overrides project's "warn" for this env
    └── API_URL=https://staging.api.com

    Service Scope (narrowest — specific to ONE service)
      └── LOG_LEVEL=debug           ← overrides environment's "info" for this service
      └── PORT=8080
```

**Rule: Define variables at the BROADEST scope possible, override only where needed.**

In Terraform, use `environment_variable_overrides` to override a variable from a broader scope:

```hcl
# Set at environment level (applies to all services)
resource "qovery_environment" "main" {
  environment_variables = [
    { key = "LOG_LEVEL", value = "info" },
    { key = "NODE_ENV", value = "production" }
  ]
}

# Override at service level (only this service gets "debug")
resource "qovery_application" "backend" {
  # Regular service-specific variables
  environment_variables = [
    { key = "PORT", value = "8080" }
  ]

  # Override a variable from environment or project scope
  environment_variable_overrides = [
    { key = "LOG_LEVEL", value = "debug" }
  ]
}
```

Via CLI:
```bash
# Create at environment scope (shared by all services)
qovery environment env create --key LOG_LEVEL --value info --scope ENVIRONMENT

# Create at service scope (overrides the environment-level value for this service)
qovery application env create --key LOG_LEVEL --value debug

# Create a secret at service scope
qovery application env create --key JWT_SECRET --value "..." --secret
```

Via API:
```bash
# Create at project scope
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "warn"}'

# Create at environment scope
curl -s -X POST "https://api.qovery.com/environment/{envId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "info"}'

# Create at service scope (overrides broader scopes)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "LOG_LEVEL", "value": "debug"}'
```

### 6.3 Built-in Variables (Auto-Generated)

Qovery automatically generates and injects variables for databases, applications, and system info. These are read-only and always available in all services within the same environment.

#### Database Connection Variables

Pattern: `QOVERY_DATABASE_{TYPE}_{NAME}_{PROPERTY}`

The NAME is your database name with hyphens replaced by underscores and uppercased.

| Variable | Example (DB named "postgres") | Description |
|---|---|---|
| `..._HOST` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST` | External hostname |
| `..._HOST_INTERNAL` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL` | Internal hostname (use this for in-cluster communication) |
| `..._PORT` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_PORT` | Port number |
| `..._LOGIN` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_LOGIN` | Username |
| `..._PASSWORD` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD` | Password (secret) |
| `..._CONNECTION_URI` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI` | Full external connection URI |
| `..._CONNECTION_URI_INTERNAL` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL` | Internal connection URI (preferred) |
| `..._DEFAULT_DATABASE_NAME` | `QOVERY_DATABASE_POSTGRESQL_POSTGRES_DEFAULT_DATABASE_NAME` | Default database name |

#### Application Connection Variables

Pattern: `QOVERY_APPLICATION_{NAME}_{PROPERTY}`

| Variable | Description |
|---|---|
| `QOVERY_APPLICATION_{NAME}_HOST_INTERNAL` | Internal hostname (cluster network) |
| `QOVERY_APPLICATION_{NAME}_HOST_EXTERNAL` | Public hostname (if publicly accessible) |
| `QOVERY_APPLICATION_{NAME}_PORT` | Service port |

#### System Variables

```
QOVERY_PROJECT_ID              — Project UUID
QOVERY_ENVIRONMENT_ID          — Environment UUID
QOVERY_ENVIRONMENT_NAME        — Environment name (e.g., "production")
QOVERY_CLOUD_PROVIDER          — Cloud provider (AWS, GCP, AZURE, SCW)
QOVERY_CLOUD_PROVIDER_REGION   — Cloud region (e.g., "us-east-1")
QOVERY_KUBERNETES_CLUSTER_VPC_ID — VPC ID of the cluster (useful for Terraform services)
```

### 6.4 Aliases — Renaming Built-in Variables

Aliases create a **live reference** to another variable. Unlike interpolation, an alias is a pointer — if the source variable changes (e.g., database host changes on redeploy), the alias automatically reflects the new value.

Use aliases to make Qovery's built-in variable names match what your application expects.

In Terraform — use `environment_variable_aliases`:
```hcl
resource "qovery_application" "backend" {
  # ... other config ...

  # Aliases: create friendly names pointing to built-in variables
  environment_variable_aliases = [
    {
      key   = "DATABASE_URL"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL"
    },
    {
      key   = "DATABASE_HOST"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL"
    },
    {
      key   = "DATABASE_PASSWORD"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD"
    },
    {
      key   = "REDIS_URL"
      value = "QOVERY_CONTAINER_REDIS_HOST_INTERNAL"
    }
  ]
}
```

For referencing another application's host (the ID-based pattern):
```hcl
  environment_variable_aliases = [
    {
      key   = "BACKEND_HOST"
      value = "QOVERY_APPLICATION_Z${upper(element(split("-", qovery_application.backend.id), 0))}_HOST_EXTERNAL"
    }
  ]
```

IMPORTANT: The `value` in an alias is the **name** of the source variable (NOT its value, and NOT wrapped in `{{}}`). It's a reference, not interpolation.

Via API:
```bash
# Create an alias
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "DATABASE_URL",
    "alias_parent_id": "{sourceVariableId}"
  }'
```

### 6.5 Interpolation — Composing Values

Interpolation uses `{{VARIABLE_NAME}}` syntax inside a variable value. The placeholders are resolved at deploy time.

Use interpolation when you need to **compose** a value from multiple variables, or embed a variable value inside a larger string.

IMPORTANT: For simple database connections (no custom parameters), use an **alias** instead (see 6.4). Only use interpolation for database connections when you need to add custom query parameters or compose a connection string from parts.

```hcl
resource "qovery_application" "backend" {
  environment_variables = [
    # Compose a custom connection string WITH extra parameters — valid use of interpolation
    # (For simple DB connections without params, use an alias in environment_variable_aliases instead!)
    {
      key   = "DATABASE_URL_WITH_PARAMS"
      value = "postgresql://{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_LOGIN}}:{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD}}@{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL}}:{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_PORT}}/{{QOVERY_DATABASE_POSTGRESQL_POSTGRES_DEFAULT_DATABASE_NAME}}?sslmode=require&pool_size=20"
    },
    # Compose a URL from an alias or another variable
    {
      key   = "NEXT_PUBLIC_API_URL"
      value = "https://{{BACKEND_HOST}}/api/v1"
    },
    # Embed environment name in resource names
    {
      key   = "S3_BUCKET_NAME"
      value = "myapp-{{QOVERY_ENVIRONMENT_NAME}}-storage"
    },
    # Use system variables for cloud-aware configuration
    {
      key   = "AWS_REGION"
      value = "{{QOVERY_CLOUD_PROVIDER_REGION}}"
    }
  ]
}
```

Via API — interpolation works the same way in the `value` field:
```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "BACKEND_API_URL",
    "value": "https://{{BACKEND_HOST}}:{{BACKEND_PORT}}/api"
  }'
```

For Helm charts, use the `qovery.env.VARIABLE_NAME` macro in chart values instead of `{{...}}`:
```yaml
# In Helm values_override
database:
  host: "qovery.env.DATABASE_HOST"
  port: "qovery.env.DATABASE_PORT"
  password: "qovery.env.DATABASE_PASSWORD"
```

### 6.6 Alias vs Interpolation — When to Use Which

| Scenario | Use Alias | Use Interpolation |
|---|---|---|
| `DATABASE_URL` for PostgreSQL/MySQL/MongoDB/Redis (no custom params) | YES — alias on `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL` | NO |
| `DATABASE_URL` with custom query params (`?sslmode=require&pool_size=20`) | NO | YES — compose from parts |
| `REDIS_HOST` pointing to a Qovery-managed Redis | YES — alias on `QOVERY_CONTAINER_REDIS_HOST_INTERNAL` | NO |
| `DATABASE_HOST`, `DATABASE_PASSWORD` individually | YES — alias each to the built-in variable | NO |
| `API_URL` = `https://{host}/api/v1` | | YES — compose URL with path |
| `S3_BUCKET` = `myapp-{env-name}-storage` | | YES — embed env name |
| Frontend `NEXT_PUBLIC_API_URL` pointing to backend's external host | Use alias for the host, then interpolation for the full URL | |

General rule: **For Qovery-managed database connections, ALWAYS use aliases. Use interpolation only when you need to compose, transform, or add parameters.**

### 6.7 Variable as File

Qovery supports mounting an environment variable's value as a file at a specific path in the container filesystem. This is useful for config files, certificates, and SSH keys.

Via API:
```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "APP_CONFIG",
    "value": "server:\n  port: 8080\n  host: 0.0.0.0\n  log_level: info",
    "mount_path": "/etc/config/app.yaml"
  }'
```

Use cases:
- TLS certificates and private keys
- Application config files (YAML, JSON, TOML)
- SSH keys for private git access
- Nginx/Apache config snippets

### 6.8 CLI Commands for Variable Management

```bash
# === Import / Export ===

# Import .env file into a service (bulk import)
qovery env import

# Export current variables to .env file (for local development)
qovery env parse

# === Service-level variables ===

# List all variables for a service
qovery application env list

# Create a variable
qovery application env create --key PORT --value 8080

# Create a secret
qovery application env create --key JWT_SECRET --value "my-secret" --secret

# Update a variable
qovery application env update --key PORT --value 3000

# Delete a variable
qovery application env delete --key PORT

# === Environment-level variables ===

# List environment variables
qovery environment env list

# Create at environment scope (shared by all services)
qovery environment env create --key LOG_LEVEL --value info --scope ENVIRONMENT

# === Other service types ===
qovery container env list
qovery container env create --key MY_VAR --value my_value
qovery cronjob env list
qovery lifecycle env list
```

### 6.9 Best Practices — Avoid Duplication

Follow these rules to keep environment variables clean and DRY:

1. **Shared config → Project scope**: Variables identical across all environments (company name, support email, CDN URL). Define once, inherit everywhere.

2. **Environment-specific config → Environment scope**: Variables that differ per environment (API URLs, feature flags, log levels). Define at environment scope, not duplicated on every service.

3. **Service-unique config → Service scope**: Variables truly unique to one service (PORT, WORKERS, service-specific API keys). Only use service scope when the variable is NOT shared.

4. **NEVER duplicate built-in variables**: Use **aliases** instead. Don't create `DATABASE_URL` with a hardcoded copy of the connection string — create an alias pointing to `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL`. The alias stays in sync automatically.

5. **Use interpolation for composed values**: Don't copy-paste connection strings. Compose them from built-in variable parts using `{{...}}` syntax.

6. **Use overrides to customize per-environment or per-service**: If most environments need `LOG_LEVEL=warn` but staging needs `debug`, set `warn` at project scope and override it at the staging environment scope. Don't set `LOG_LEVEL` independently on every environment.

7. **Prefer `_INTERNAL` variants for in-cluster communication**: Always use `HOST_INTERNAL` and `CONNECTION_URI_INTERNAL` for services communicating within the same cluster. External variants route through the internet, adding latency and cost.

8. **Secrets are scoped too**: Secret overrides work the same way as regular variable overrides. Define a secret at project scope and override its value at environment scope for different environments.

---

## PHASE 7: Complete Example — Full-Stack Application

Here is a complete, production-ready Terraform configuration for a typical full-stack app (Next.js frontend + API backend + PostgreSQL database). Copy and adapt this as a starting point:

```hcl
# ============================================================
# qovery.tf — Complete Full-Stack Deployment on Qovery
# ============================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = "~> 0.54.0"
    }
  }
}

provider "qovery" {
  token = var.qovery_access_token
}

# --- Variables ---

variable "qovery_access_token" {
  type      = string
  sensitive = true
}

variable "qovery_project_id" { type = string }
variable "qovery_cluster_id" { type = string }
variable "git_repository_url" { type = string }

variable "git_branch" {
  type    = string
  default = "main"
}

variable "environment_name" {
  type    = string
  default = "production"
}

variable "environment_mode" {
  type    = string
  default = "PRODUCTION"
  # Valid values: PRODUCTION, STAGING, DEVELOPMENT
}

variable "use_managed_database" {
  description = "true = cloud-managed DB (production), false = container DB (dev/test)"
  type        = bool
  default     = false
}

variable "jwt_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# --- Environment ---
# Shared variables are set here — inherited by ALL services, avoiding duplication.

resource "qovery_environment" "main" {
  project_id = var.qovery_project_id
  cluster_id = var.qovery_cluster_id
  name       = var.environment_name
  mode       = var.environment_mode

  # Environment-scoped variables — shared by all services (no duplication!)
  environment_variables = [
    {
      key   = "NODE_ENV"
      value = var.environment_mode == "PRODUCTION" ? "production" : "development"
    },
    {
      key   = "LOG_LEVEL"
      value = var.environment_mode == "PRODUCTION" ? "warn" : "info"
    }
  ]
}

# --- Deployment Stages ---

resource "qovery_deployment_stage" "database" {
  environment_id = qovery_environment.main.id
  name           = "Database"
  description    = "Database must start before backend"
}

resource "qovery_deployment_stage" "backend" {
  environment_id = qovery_environment.main.id
  name           = "Backend"
  description    = "Backend API services"
  is_after       = qovery_deployment_stage.database.id
}

resource "qovery_deployment_stage" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "Frontend"
  description    = "Frontend applications"
  is_after       = qovery_deployment_stage.backend.id
}

# --- Database ---

resource "qovery_database" "postgres" {
  environment_id = qovery_environment.main.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = var.use_managed_database ? "MANAGED" : "CONTAINER"
  storage        = var.use_managed_database ? 20 : 10
  cpu            = var.use_managed_database ? 0 : 250
  memory         = var.use_managed_database ? 0 : 512
  accessibility  = "PRIVATE"

  deployment_stage_id = qovery_deployment_stage.database.id
}

# --- Backend API ---

resource "qovery_application" "backend" {
  environment_id = qovery_environment.main.id
  name           = "backend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/backend"
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = var.environment_mode == "PRODUCTION" ? 2 : 1
  max_running_instances = var.environment_mode == "PRODUCTION" ? 4 : 1

  deployment_stage_id = qovery_deployment_stage.backend.id
  auto_deploy         = true

  ports = [
    {
      internal_port       = 8080
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      name                = "api"
    }
  ]

  healthchecks = {
    liveness_probe = {
      type = {
        http = {
          port   = 8080
          scheme = "HTTP"
          path   = "/health"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
    readiness_probe = {
      type = {
        http = {
          port   = 8080
          scheme = "HTTP"
          path   = "/health"
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  # Service-specific variables (only what's unique to this service)
  environment_variables = [
    {
      key   = "PORT"
      value = "8080"
    }
  ]

  # Aliases: live pointers to built-in variables (stay in sync automatically)
  # Use aliases instead of duplicating connection strings!
  environment_variable_aliases = [
    {
      key   = "DATABASE_URL"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL"
    },
    {
      key   = "DATABASE_HOST"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL"
    },
    {
      key   = "DATABASE_PASSWORD"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD"
    }
  ]

  # Overrides: change the value of a variable inherited from environment scope
  # Backend needs debug logging — override the environment-level "warn"/"info"
  environment_variable_overrides = var.environment_mode != "PRODUCTION" ? [
    {
      key   = "LOG_LEVEL"
      value = "debug"
    }
  ] : []

  secrets = var.jwt_secret != "" ? [
    {
      key   = "JWT_SECRET"
      value = var.jwt_secret
    }
  ] : []
}

# --- Frontend ---

resource "qovery_application" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "frontend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/frontend"
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = 1
  max_running_instances = 2

  deployment_stage_id = qovery_deployment_stage.frontend.id
  auto_deploy         = true

  ports = [
    {
      internal_port       = 3000
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      name                = "web"
    }
  ]

  healthchecks = {
    liveness_probe = {
      type = {
        http = {
          port   = 3000
          scheme = "HTTP"
          path   = "/"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  # NODE_ENV and LOG_LEVEL are inherited from the environment scope — no need to set them here!
  # Only set service-specific variables.

  # Interpolation: compose a URL from an alias (resolved at deploy time)
  environment_variables = [
    {
      key   = "NEXT_PUBLIC_API_URL"
      value = "https://{{BACKEND_HOST_EXTERNAL}}"
    }
  ]

  # Aliases: create a friendly name that points to the backend's auto-generated host variable
  environment_variable_aliases = [
    {
      key   = "BACKEND_HOST_EXTERNAL"
      value = "QOVERY_APPLICATION_Z${upper(element(split("-", qovery_application.backend.id), 0))}_HOST_EXTERNAL"
    }
  ]
}

# --- Outputs ---

output "environment_id" {
  value = qovery_environment.main.id
}

output "backend_url" {
  value = qovery_application.backend.external_host
}

output "frontend_url" {
  value = qovery_application.frontend.external_host
}

output "database_host" {
  value = qovery_database.postgres.internal_host
}
```

---

## PHASE 8: Advanced Patterns

### 8.1 Custom Domains

After deployment, add custom domains:

Via API:
```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/customDomain" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain": "app.example.com"}'
```

Then create a CNAME DNS record pointing to the Qovery-generated domain. Qovery automatically provisions SSL/TLS certificates via Let's Encrypt.

### 8.2 Autoscaling

Configure horizontal pod autoscaling:

```hcl
resource "qovery_application" "backend" {
  # ... other config ...
  min_running_instances = 2
  max_running_instances = 10
  # HPA is automatically enabled when min != max
}
```

### 8.3 Persistent Storage

```hcl
resource "qovery_application" "backend" {
  # ... other config ...
  storage = [
    {
      type        = "FAST_SSD"
      size        = 10    # GB
      mount_point = "/data"
    }
  ]
}
```

### 8.4 Terraform Exporter

If the user already has services configured via the Qovery Console UI and wants to switch to Terraform:

1. Go to the environment in Qovery Console
2. Click environment settings (three dots) > "Export as Terraform"
3. Download the generated `.tf` files
4. Import existing resources to avoid recreating them:
   ```bash
   terraform import qovery_environment.main {environment-id}
   terraform import qovery_application.backend {application-id}
   terraform import qovery_database.postgres {database-id}
   ```
5. Run `terraform plan` — should show no or minimal changes

### 8.5 Git Provider Detection

Detect the git provider from the remote URL to set the correct `provider` field:

```bash
git remote get-url origin
```

- Contains `github.com` -> `GITHUB`
- Contains `gitlab.com` or a self-hosted GitLab domain -> `GITLAB`
- Contains `bitbucket.org` -> `BITBUCKET`

IMPORTANT: The user's Qovery organization must have the corresponding git provider connected (GitHub App installed, GitLab token, or Bitbucket integration). Check this at Organization Settings > Git Repository Access in the Qovery Console.

### 8.6 Monorepo Support

For monorepos with multiple services in subdirectories:

```
my-repo/
├── backend/
│   ├── Dockerfile
│   └── src/
├── frontend/
│   ├── Dockerfile
│   └── src/
├── jobs/
│   └── migrate/
│       └── Dockerfile
├── terraform/
│   └── s3-bucket/
│       └── main.tf
└── qovery.tf
```

Set `root_path` for each service:
- Backend: `root_path = "/backend"`
- Frontend: `root_path = "/frontend"`
- Migration job: `root_path = "/jobs/migrate"`
- Terraform service: `root_path = "/terraform/s3-bucket"`

Each service gets its own Dockerfile in its subdirectory.

### 8.7 Environment Cloning for Preview/Staging

Qovery supports cloning entire environments for preview or staging:

Via API:
```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "preview-pr-42",
    "mode": "DEVELOPMENT",
    "cluster_id": "{clusterId}"
  }'
```

This creates a full copy of the environment with all its services, databases, and configuration — ideal for preview environments on pull requests.

### 8.8 Secure Local Access via Port-Forward

Use `qovery port-forward` to create a secure encrypted tunnel from your local machine to any service in the cluster — without making it publicly accessible. This is the recommended way to connect to databases and internal services for development, debugging, and administration.

#### Connect to Databases Locally

Databases should NEVER be publicly exposed. Use port-forward instead:

```bash
# PostgreSQL
qovery port-forward --service "postgres" --port 5432:5432
# Then connect: psql -h localhost -p 5432 -U myuser -d mydatabase

# MySQL
qovery port-forward --service "mysql" --port 3306:3306
# Then connect: mysql -h 127.0.0.1 -P 3306 -u myuser -p mydatabase

# MongoDB
qovery port-forward --service "mongodb" --port 27017:27017
# Then connect: mongosh "mongodb://localhost:27017/mydatabase"

# Redis
qovery port-forward --service "redis" --port 6379:6379
# Then connect: redis-cli -h localhost -p 6379
```

#### Use a Different Local Port (Avoid Conflicts)

If the default port is already in use locally:

```bash
# Forward remote 5432 to local 15432
qovery port-forward --service "postgres" --port 15432:5432
# Connect on localhost:15432
```

#### Run Your Local App Against a Remote Database

This is extremely useful for development — run your app locally but connect to the real database in the cluster:

```bash
# Terminal 1: start the tunnel
qovery port-forward --service "postgres" --port 5432:5432

# Terminal 2: run your local app pointing to the forwarded port
DATABASE_URL=postgresql://user:pass@localhost:5432/mydb npm run dev
```

You can use `qovery env parse` to export all environment variables from the remote environment as a local `.env` file, then override `DATABASE_URL` to point to `localhost`.

#### Access Internal Services for Debugging

Forward to applications or containers that are not publicly exposed:

```bash
# Forward an internal backend API
qovery port-forward --service "backend" --port 8080:8080
curl http://localhost:8080/api/health

# Forward a Helm-deployed service (e.g., admin panel)
qovery port-forward --service "windmill" --port 8000:8000
```

#### Important Notes

- The tunnel is **encrypted and authenticated** via Kubernetes — no credentials traverse the public internet
- Keep the terminal running — press Ctrl+C to close the tunnel
- If the pod restarts, the tunnel drops and must be re-established (just re-run the command)
- The `--port` flag uses `local:remote` format (e.g., `5432:5432` or `15432:5432`)
- This is for **development and debugging** — for production service-to-service communication, use the internal hostnames (`_HOST_INTERNAL` variables)

---

## PHASE 9: Deployment Watching & Verification

After triggering a deployment (Phase 4 or Phase 5), you MUST actively watch it and verify success. Do NOT just tell the user "it's deploying" and walk away.

### 9.1 Offer to Watch

Immediately after deploying, ask the user:

> "The deployment is in progress. Would you like me to watch it and automatically diagnose and fix any issues if the deployment fails?"

If the user says yes (or doesn't object), enter the active watch loop below. If they explicitly decline, provide them with the manual verification commands and skip to 9.4.

### 9.2 Active Deployment Watch Loop

Watch the deployment and detect success or failure:

```bash
# Option A: CLI (interactive, real-time)
qovery status --watch

# Option B: API (scriptable, poll every 15-30 seconds)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, state, status_details: .status_details}],
    databases: [.databases[] | {id, state}],
    jobs: [.jobs[] | {id, state}],
    helms: [.helms[] | {id, state}],
    terraforms: [.terraforms[] | {id, state}]
  }'
```

Keep polling until the environment state is one of:
- **DEPLOYED** / **READY** -> Success! Go to 9.4
- **BUILD_ERROR** / **DEPLOYMENT_ERROR** / **STOP_ERROR** / **RESTART_ERROR** -> Failure! Go to Phase 10
- **CANCELED** -> Tell the user, ask if they want to retry

The `status_details` field for each service tells you exactly where it failed:
- `action`: What was being done (`DEPLOY`, `DELETE`, `RESTART`, `STOP`)
- `status`: Result (`QUEUED`, `ONGOING`, `SUCCESS`, `ERROR`, `CANCELED`)

The deployment step metrics tell you WHICH step failed:
- `GIT_CLONE` -> Git access issue
- `BUILD` -> Docker build failure
- `MIRROR_IMAGE` -> Registry push failure
- `DEPLOYMENT` -> Kubernetes deployment failure (health check, crash, OOM, etc.)
- `EXECUTING` -> Job or Terraform execution failure

### 9.3 Fetch Logs on Failure

When any service enters an error state, immediately fetch its logs:

```bash
# Via CLI — get last 10 minutes, filter for errors
qovery log --application "my-app" --since 10m
qovery log --application "my-app" --since 10m --filter "ERROR"
qovery log --application "my-app" --since 10m --filter "error"
qovery log --application "my-app" --since 10m --filter "FATAL"
qovery log --application "my-app" --since 10m --filter "panic"
qovery log --application "my-app" --since 10m --filter "Exit"

# Via API — get last 1000 log lines
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[-50:] | .[] | .message'

# Get deployment history to see which step failed and duration
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/deploymentHistory" | jq '.results[0]'
```

For other service types, replace the endpoint:
- Containers: `GET /container/{containerId}/log`
- Jobs: `GET /job/{jobId}/log`
- Databases: `GET /database/{databaseId}/log` (limited)
- Helm: `GET /helm/{helmId}/log`

After fetching logs, analyze them and proceed to Phase 10 for diagnosis and fix.

### 9.4 Verify Success

When all services are deployed successfully:

```bash
# 1. List all services and their statuses
qovery service list

# 2. Get the public URLs
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/link" | jq '.results'

# 3. Test the health endpoint
curl -s https://{app-url}/health

# 4. View recent logs to confirm healthy operation
qovery log --application "my-app" --tail 20

# 5. Open a shell into a running container (for debugging if needed)
qovery shell --application "my-app"

# 6. Port-forward to access internal services locally (secure tunnel, no public exposure)
qovery port-forward --service "my-app" --port 8080:8080

# 7. Port-forward to access the database locally (e.g., for pgAdmin, DBeaver, psql)
qovery port-forward --service "postgres" --port 5432:5432
# Then in another terminal: psql -h localhost -p 5432 -U myuser -d mydatabase
```

See Phase 8.8 for the full port-forward guide (all database types, different local ports, local dev workflows).

Tell the user:
- Their application is deployed and accessible at the Qovery-generated URL
- They can add a custom domain in the Qovery Console or via the API
- Auto-deploy is enabled: every git push to the configured branch triggers a new deployment
- They can monitor logs, metrics, and deployment history in the Qovery Console at https://console.qovery.com
- For the Terraform path: the `qovery.tf` file should be committed to git (but NEVER commit secrets or API tokens)

### 9.5 Token Cleanup

If you generated an API token earlier via `qovery token` during Phase 2, offer to delete it now that deployment is complete. This is good security practice — short-lived tokens reduce the blast radius if compromised.

```bash
# List tokens to find the one you created
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/apiToken" | jq '.results[] | {id, name, created_at}'

# Delete the token by ID
curl -s -X DELETE "https://api.qovery.com/organization/{orgId}/apiToken/{tokenId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Ask the user: "I generated an API token earlier for deployment. Would you like me to delete it now, or keep it for future use?"

- If the user wants to keep it: remind them to store it securely and that it can be managed at Qovery Console > Organization Settings > API Tokens
- If the user wants to delete it: delete via the API above
- If a JWT token was used instead (Method 2): no cleanup needed, it expires automatically

---

## PHASE 10: Troubleshooting & Auto-Fix

When a deployment fails, follow this phase to diagnose the issue, classify it, and either fix it automatically or ask the user for permission.

### CRITICAL RULE: What You Can and Cannot Fix Automatically

You MUST follow this rule strictly:

**AUTO-FIX ALLOWED (no permission needed):**
- Qovery service configuration: port numbers, health check paths, memory/CPU limits, deployment stage ordering, environment variables (non-secret), Dockerfile path, git branch, root_path, build_mode, instance counts
- Dockerfiles that YOU created during this session (Phase 3) — you are responsible for them
- .dockerignore files that YOU created
- next.config.js `output: 'standalone'` addition (required for Next.js Dockerfile you created)
- Adding gunicorn/uvicorn to requirements.txt if YOU created the Dockerfile that references them

**MUST ASK USER BEFORE FIXING:**
- Any changes to the user's application source code (fixing a bug, adding an import, changing a config)
- Any changes to a Dockerfile that already existed before you started (you did NOT create it)
- Adding, changing, or removing environment variables that contain secrets or sensitive values
- Changes to the user's database schema or migration files
- Changes to the user's package.json, go.mod, pom.xml, or other dependency files (unless you created the Dockerfile that requires a specific dependency like gunicorn)
- Any change where you are not 100% certain it will fix the issue

**WHEN ASKING, always:**
1. Explain the error clearly (quote the relevant log lines)
2. Explain what you think the root cause is
3. Show the exact change you propose
4. Wait for explicit approval before making the change

### 10.1 Error Classification & Diagnosis

Analyze the logs fetched in Phase 9.3 and classify the error:

#### BUILD_ERROR — Docker Build Failed

**Symptoms:** Service status is `BUILD_ERROR`. Build logs show Docker build output with an error.

**Common causes and fixes:**

| Log Pattern | Cause | Fix | Auto-Fix? |
|---|---|---|---|
| `Dockerfile not found` or `Cannot locate specified Dockerfile` | Wrong `dockerfile_path` in Qovery config | Update `dockerfile_path` via API: `PATCH /application/{appId}` with `{"dockerfile_path": "Dockerfile"}` | YES |
| `COPY failed: file not found` | File referenced in Dockerfile doesn't exist, or wrong `root_path` | Check if `root_path` is correct. If Dockerfile was created by you, fix the COPY path. | YES if your Dockerfile, ASK if user's |
| `npm ERR! Could not resolve dependency` or `pip install ... ERROR` | Dependency install failure | This is a code/dependency issue | ASK USER — explain which dependency failed |
| `RUN npm run build` fails with compilation errors | TypeScript/build errors in user code | This is a code issue | ASK USER — show the build errors |
| Base image not found (e.g., `manifest unknown`) | Wrong base image tag in Dockerfile | Fix the base image tag if you created the Dockerfile | YES if your Dockerfile |
| `no space left on device` | Disk too small for build | Increase disk size on cluster or optimize Dockerfile | YES — optimize Dockerfile layers |

**How to fix `dockerfile_path` via API:**
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"dockerfile_path": "Dockerfile"}'
```

#### DEPLOYMENT_ERROR — Container Fails to Start or Health Check Fails

**Symptoms:** Service status is `DEPLOYMENT_ERROR`. The Docker image built successfully, but the container crashes or never becomes healthy.

**Common causes and fixes:**

| Log Pattern | Cause | Fix | Auto-Fix? |
|---|---|---|---|
| `CrashLoopBackOff` + app error in logs | Application crashes on startup | Read the crash logs to identify the issue | DEPENDS — see below |
| No logs at all + `DEPLOYMENT_ERROR` | Health check fails before app starts | Increase `initial_delay_seconds` in health check, or fix the health check path | YES — Qovery config |
| `listening on port 3000` but health check is on port 8080 | Port mismatch between app and Qovery config | Update `ports[].internal_port` and health check port in Qovery config | YES — Qovery config |
| `ECONNREFUSED 127.0.0.1:5432` or `connection refused` to DB | Database not ready or wrong connection string | Check deployment stages (DB must deploy before app). Check `DATABASE_URL` env var | YES — fix deployment stage or env var |
| `Error: connect ECONNREFUSED` to external service | Missing env var for external service URL | Ask user for the correct URL/credentials | ASK USER |
| `OOMKilled` or `memory limit exceeded` | Application needs more memory than allocated | Increase `memory` in Qovery config (e.g., 512 -> 1024) | YES — Qovery config |
| `exec format error` | Architecture mismatch (ARM image on AMD64 node or vice versa) | Fix the build architecture in Dockerfile or cluster config | YES if your Dockerfile |
| `SIGKILL` after timeout | App takes too long to start | Increase `initial_delay_seconds` (e.g., 30 -> 60 or 120) | YES — Qovery config |
| Health check 404 on `/health` | App doesn't have a `/health` endpoint | Switch to TCP health check instead of HTTP, or add the endpoint | YES for TCP switch, ASK for code change |

**How to fix port mismatch via API:**
```bash
# Update application port
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ports": [{"internal_port": 3000, "external_port": 443, "protocol": "HTTP", "publicly_accessible": true, "name": "http"}]
  }'
```

**How to fix health check via API:**
```bash
# Switch to TCP health check (when app has no /health endpoint)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "healthchecks": {
      "liveness_probe": {
        "type": {"tcp": {"port": 3000}},
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    }
  }'
```

**How to increase memory via API:**
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"memory": 1024}'
```

**Debugging tip — use port-forward and shell to investigate live:**
```bash
# Open a shell into the running (or crashing) container
qovery shell --service "my-app"

# Port-forward to access the app locally and test it directly
qovery port-forward --service "my-app" --port 8080:8080
# Then: curl http://localhost:8080/health

# Port-forward to the database to verify it's accessible
qovery port-forward --service "postgres" --port 5432:5432
# Then: psql -h localhost -p 5432 -U myuser -d mydatabase
```

These commands create a secure tunnel — the services do NOT need to be publicly exposed.

#### GIT_CLONE Error — Cannot Access Repository

**Symptoms:** Step `GIT_CLONE` failed.

**Common causes:**
- Git provider (GitHub/GitLab/Bitbucket) not connected to the Qovery organization
- Repository is private and Qovery doesn't have access
- Wrong repository URL or branch name

**Fix:** Direct the user to Qovery Console > Organization Settings > Git Repository Access to connect their git provider. If the branch is wrong, update it via API:
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"git_repository": {"branch": "main"}}'
```

#### Database Connection Issues

**Symptoms:** Application logs show connection refused/timeout to database.

**Diagnosis steps:**
1. Check if the database service is actually running: `qovery service list`
2. Check deployment stages — the database MUST deploy in an earlier stage than the application
3. Check if `DATABASE_URL` or equivalent env var is set correctly — it should be an **alias** pointing to the built-in `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL` variable (not a hardcoded value, not interpolation for simple connections)
4. Check if the application is using `_INTERNAL` (cluster network) vs external URL — always prefer `_INTERNAL`

**Fixes (all auto-fixable — Qovery config):**
```bash
# Fix deployment stage ordering via API
curl -s -X PUT "https://api.qovery.com/deploymentStage/{stageId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"is_after": "{dbStageId}"}'

# Fix DATABASE_URL — create an alias to the built-in connection URI (preferred)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "alias_parent_id": "{sourceVariableId}"}'
# Note: get the sourceVariableId by listing the environment's built-in variables:
# GET /environment/{envId}/environmentVariable — find the QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL variable ID
```

#### Missing Environment Variable

**Symptoms:** Application logs show `Error: XYZ is not defined`, `KeyError: 'XYZ'`, `env var XYZ required`, `undefined`, etc.

**Diagnosis:**
1. Identify the missing variable name from the logs
2. Check if it's a standard variable (PORT, NODE_ENV, DATABASE_URL) or a custom one
3. Check if it's a secret (API keys, passwords, tokens) or non-secret

**Fix:**
- For standard non-secret variables (PORT, NODE_ENV, etc.): Auto-fix by adding the variable via API. **YES — auto-fix.**
- For database connection variables: Auto-fix using Qovery interpolation syntax. **YES — auto-fix.**
- For secrets (API keys, JWT secrets, third-party tokens): **ASK USER** for the value. Never guess or generate secrets without permission.

```bash
# Auto-fix example: add missing PORT variable
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "PORT", "value": "8080"}'

# For secrets — ask the user, then:
curl -s -X POST "https://api.qovery.com/application/{appId}/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "user-provided-value"}'
```

#### Terraform Service Errors

**Symptoms:** Terraform service shows `DEPLOYMENT_ERROR`. Execution step failed.

**Diagnosis:** Fetch terraform service logs to see the `terraform plan` or `terraform apply` output.

**Common causes:** Wrong variables, missing AWS permissions, resource conflicts, state lock.

**Fix:** These are complex and highly variable. Show the Terraform error output to the user and explain the likely cause. **ASK USER** before making changes to Terraform code.

#### Helm Chart Errors

**Symptoms:** Helm service shows `DEPLOYMENT_ERROR`.

**Diagnosis:** Fetch helm logs to see the `helm install/upgrade` output.

**Common causes:** Invalid values, missing dependencies, timeout, resource conflicts.

**Fix:** Show the Helm error to the user. If it's a values override issue (e.g., wrong port, missing config), you can auto-fix the `values_override` in Qovery config. For chart-level issues, **ASK USER**.

### 10.2 Fix and Redeploy Loop

After applying a fix (whether auto-fix or user-approved):

1. **Apply the fix** — API call to update Qovery config, or edit and commit a file (Dockerfile, next.config.js, etc.)

2. **Trigger a redeploy:**
   ```bash
   # Redeploy a single service
   curl -s -X POST "https://api.qovery.com/application/{appId}/restart" \
     -H "Authorization: Token $QOVERY_API_TOKEN"

   # Or redeploy the whole environment
   curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
     -H "Authorization: Token $QOVERY_API_TOKEN"

   # Or via CLI
   qovery application redeploy --application "my-app"
   ```

3. **Watch the new deployment** — Go back to Phase 9.2 and monitor again.

4. **Repeat** until success or until the issue clearly requires user intervention that you cannot resolve.

5. **Maximum retries**: Do not attempt more than 3 auto-fix cycles for the same service. If after 3 attempts the service still fails, present a full summary of what you tried, what the current error is, and ask the user how they want to proceed.

### 10.3 Common Fix Recipes

#### Recipe: Next.js standalone output not enabled

**Error:** Build succeeds but deployment fails — `.next/standalone` directory is missing.

**Fix (auto-fix — you created the Dockerfile that expects standalone):**
1. Check `next.config.js` or `next.config.mjs`
2. Add `output: 'standalone'` if missing
3. Commit and push
4. Redeploy

#### Recipe: Python missing gunicorn/uvicorn

**Error:** Build succeeds but container crashes with `gunicorn: command not found` or `uvicorn: command not found`.

**Fix (auto-fix — you created the Dockerfile that references it):**
1. Add `gunicorn` or `uvicorn` to `requirements.txt`
2. Commit and push
3. Redeploy

#### Recipe: App listens on 0.0.0.0 but health check uses wrong port

**Error:** Logs show `Server listening on port 3000` but Qovery health check is configured for port 8080.

**Fix (auto-fix — Qovery config):**
1. Update port config and health check port to 3000 via API
2. Redeploy

#### Recipe: Database not ready when app starts

**Error:** App crashes with `ECONNREFUSED` to database host on first deploy. Database is still provisioning.

**Fix (auto-fix — Qovery config):**
1. Ensure database is in an earlier deployment stage than the application
2. If deployment stages are correct, increase `initial_delay_seconds` on the app's health check to give the DB more time
3. Redeploy

#### Recipe: SPA returns 404 on page refresh

**Error:** React/Vite SPA works on the root URL but returns 404 when refreshing on a sub-route (e.g., `/dashboard`).

**Fix (auto-fix — you created the nginx Dockerfile):**
1. Verify the nginx config in the Dockerfile includes `try_files $uri $uri/ /index.html`
2. If missing, fix the nginx configuration in the Dockerfile
3. Commit and push
4. Redeploy

---

## Decision Tree Summary

```
User wants to deploy with Qovery
│
├─ Has Qovery account? ─── NO ──> Sign up at https://console.qovery.com
│
├─ Has API token? ──────── NO ──> Generate at Organization Settings > API Tokens
│
├─ Has a cluster? ──────── NO ──> Phase 2B: Cluster Setup
│                                  ├─ Choose cloud provider (AWS/GCP/Azure/Scaleway)
│                                  ├─ Create cloud credentials (CloudFormation / Cloud Shell / etc.)
│                                  ├─ Create cluster (Console recommended, or API, or Terraform)
│                                  └─ Wait 15-30 min for cluster to be ready
│
├─ Has Dockerfile? ─────── NO ──> Create one (Phase 3 templates)
│       │
│       YES
│
├─ Needs Database? ─────── NO ──> Skip database setup
│       │
│       YES
│       ├─ Dev/Test? ──────────> Database mode = CONTAINER (cheap, on-cluster)
│       └─ Production? ───────┬> Database mode = MANAGED (simple, cloud-managed RDS)
│                              └> Terraform service for RDS Aurora (advanced, full control)
│
├─ Needs cloud resources? ──> Terraform service (S3, Lambda, CloudFront, etc.)
│
├─ Has Helm charts? ────────> qovery_helm resource
│
├─ Has scheduled tasks? ────> Cron Job (qovery_job with schedule.cronjob)
│
├─ Needs DB migrations? ───> Lifecycle Job (qovery_job with schedule.on_start)
│
├─ Deployment method?
│       ├─ CLI + API (quick start) ─────────> Phase 4
│       └─ Terraform (recommended for prod) > Phase 5
│
├─ Deploy and watch ──> Phase 9
│       │
│       ├─ Deployment succeeds ──> Show URLs, done!
│       │
│       └─ Deployment fails ──> Phase 10: Diagnose & Fix
│               │
│               ├─ Qovery config issue (port, health check, memory, env var, stages)
│               │       └─> Auto-fix and redeploy (no permission needed)
│               │
│               ├─ Dockerfile issue (created by skill)
│               │       └─> Auto-fix and redeploy (no permission needed)
│               │
│               └─ User code issue or secret needed
│                       └─> Explain problem, show fix, ASK USER before changing
│
└─ Repeat watch-and-fix loop (max 3 retries per service)
```

---

## Reference Links

- **Qovery Documentation**: https://www.qovery.com/docs/getting-started/introduction
- **Qovery Console**: https://console.qovery.com
- **CLI Reference**: https://www.qovery.com/docs/cli/commands/overview
- **API Reference**: https://www.qovery.com/docs/api-reference/introduction
- **API Base URL**: `https://api.qovery.com`
- **API Auth Header**: `Authorization: Token YOUR_API_TOKEN`
- **Terraform Provider**: https://registry.terraform.io/providers/Qovery/qovery/latest/docs
- **Terraform Provider Source**: `qovery/qovery` version `~> 0.54.0`
- **Terraform Examples**: https://github.com/Qovery/terraform-examples
- **Real-World Example (Doktolib)**: https://github.com/evoxmusic/Doktolib/blob/main/qovery.tf
- **OpenAPI Spec**: https://raw.githubusercontent.com/qovery/qovery-openapi-spec/main/openapi.yaml
- **TypeScript SDK**: https://www.npmjs.com/package/@qovery/client
- **Go SDK**: https://github.com/Qovery/qovery-client-go
