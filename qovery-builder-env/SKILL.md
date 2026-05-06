---
name: qovery-builder-env
description: Set up self-service builder environments for non-tech teams. Creates controlled remote dev environments with AI coding tools (OpenCode, Claude Code, VS Code + Copilot, Lovable-like) pre-installed, Qovery deployment built-in, and platform-team guardrails (RBAC, cost controls, audit trails, SSO). Enables sales, finance, and other business teams to build and deploy internal tools safely.
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: builder-environments
---

# Qovery Builder Environment Skill

You are an expert at setting up self-service builder platforms on Kubernetes using Qovery. When a platform engineer asks you to create controlled development environments for non-tech teams (sales, finance, operations, marketing), follow this skill to understand their needs, create environment templates with AI coding tools, configure RBAC and cost controls, provision individual builder workspaces, and optionally generate Terraform manifests for the entire setup.

## When to Use This Skill

Use this skill when the user says anything like:
- "Set up builder environments for non-tech teams"
- "Create remote dev environments for our sales/finance team"
- "I want to give non-tech employees the ability to build and deploy apps"
- "Set up a self-service platform for internal tool builders"
- "How do I enable our All Builders initiative with Qovery?"
- "Create a controlled environment where business teams can vibe-code"
- "Set up Lovable/Cursor/Claude Code environments managed by Qovery"
- "I need to provision dev environments for non-engineers"
- `/qovery-builder-env` (slash command)

---

## Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or `new-console.qovery.com`), extract the resource IDs directly from the URL path. For the builder environment skill, the user may paste a URL to an existing environment they want to use as a template, or to the organization where builder environments should be created.

**URL format:**
```
https://{console.qovery.com|new-console.qovery.com}/organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}[/{page}]
```

**Extraction rules:**
- `orgId` — UUID after `/organization/`
- `projectId` — UUID after `/project/`
- `envId` — UUID after `/environment/`
- `serviceId` — UUID after `/service/`

Not every URL contains all segments. Use whatever IDs are present:
- URL with `orgId` -> organization is known, skip org selection
- URL with `envId` -> user may be pointing to an existing environment to use as reference
- URL with `projectId` -> project context is known

**After extracting IDs, resolve names and status via the API:**
```bash
# Get organization name
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | select(.id == "{orgId}") | {id, name}'

# Get clusters in the organization
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'

# Get environment details
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, name: .name, state}],
    databases: [.databases[] | {id, name: .name, state}]
  }'
```

**Use the extracted IDs directly** in all subsequent API calls.

---

## PHASE 1: Understand the Builder Use Case

Before setting up anything, understand who the builders are, what they need, and what the platform requirements are. Ask questions conversationally — NOT as a wall of text.

### 1.1 Authenticate

Use the same authentication flow as the other Qovery skills:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set in the environment
2. If not, check if the CLI is authenticated: look for `~/.qovery/context.json` with a valid `access_token`
3. If the CLI is authenticated, you can generate a token via `qovery token --name "builder-env-skill"`
4. As a fallback, the CLI's JWT token from `~/.qovery/context.json` can be used directly with `Authorization: Bearer <jwt>` instead of `Authorization: Token <api-token>`
- Only ask the user to manually create a token at Qovery Console > Organization Settings > API Tokens if none of the above options work

### 1.2 Understand Who Will Build

Ask the platform engineer about the builders:

1. **Who are the builders?** — Which teams will use the builder environments?
   - Sales (building internal tools, dashboards, CRM extensions)
   - Finance (building analytics tools, reporting dashboards)
   - Operations (building automation workflows, monitoring tools)
   - Marketing (building landing pages, campaign tools)
   - Product (building prototypes, internal tools)
   - Everyone (company-wide "All Builders" initiative)

2. **How many builders?** — This determines the provisioning strategy:
   - 1-5: Manual provisioning is fine
   - 5-20: Semi-automated (script-assisted)
   - 20+: Fully automated with bulk provisioning

3. **What will they build?** — This determines the template contents:
   - Internal tools (dashboards, CRUD apps, workflows)
   - Customer-facing prototypes
   - Data analysis tools
   - Automation scripts
   - API integrations

4. **What's their technical level?** — This determines the IDE choice:
   - **Zero coding experience** -> visual builder (Lovable-like, Bolt.new)
   - **Some scripting / HTML-CSS** -> VS Code with Copilot (guided, visual)
   - **Comfortable with code** -> Claude Code / OpenCode (terminal, powerful)

5. **What data do they need access to?** — This determines security requirements:
   - Public data only -> minimal restrictions
   - Internal CRM/sales data -> needs access controls
   - Customer PII / financial data -> needs strict RBAC + audit + compliance
   - Production databases -> read-only replicas recommended

### 1.3 Understand Platform Requirements

Ask about infrastructure and compliance:

1. **SSO provider?** — Google Workspace, Okta, Azure AD, OneLogin, or none
2. **Compliance requirements?** — SOC2, ISO 27001, HIPAA, HDS, GDPR, or none
   - Qovery is SOC2 Type II certified out of the box and working on ISO 27001 and HDS
3. **Cloud provider?** — AWS, GCP, Azure, or Scaleway
   - If they don't have a Qovery cluster yet -> reference the qovery-onboard skill
4. **Existing Qovery setup?** — Already have org/cluster/projects, or starting from scratch?
5. **Budget constraints?** — Any per-builder cost limits? Total budget for the builder program?

6. **Isolation level?** — How should builder environments be isolated from each other?
   > 1. **Shared project** — all builder environments live in one Qovery project. Simpler to manage. Builders can see each other's environment names (but not access them, thanks to RBAC). Good for small teams with no sensitive data.
   > 2. **Project-per-builder** (recommended for security) — each builder gets their own Qovery project containing their environment. Full isolation — builders cannot see each other's environments at all. Better for sensitive data, compliance, or larger organizations.

7. **Environment TTL (time-to-live)?** — How long should each builder environment stay alive?
   > Builder environments should be temporary to avoid wasting resources. Choose a default TTL:
   > - **8 hours** — environment stops after a workday
   > - **24 hours** — environment stops after a day
   > - **48 hours** — environment stops after two days
   > - **1 week** — environment stops after a week
   > - **Custom** — specify a duration or a specific date
   > - **No TTL** — environments stay alive until manually stopped (not recommended)
   >
   > After stopping, should the environment be **automatically deleted** after an additional period?
   > - Yes, delete after {N days} of being stopped
   > - No, keep it stopped indefinitely (can be restarted later)

8. **Deployment targets?** — Internal only, or some apps may go to production?
   - If production is possible -> enable Phase 7B (Production Graduation)

### 1.4 Choose the Builder Experience

Based on the technical level from 1.2, present the AI tool options:

**Tier 1: Visual Builder (Zero-Code)**
Best for: Sales, marketing, finance with no coding experience.
- Browser-based visual interface (Lovable-like, Bolt.new, v0)
- Drag-and-drop UI building
- AI describes-and-builds approach
- Deployed as a web application container in the builder's environment

**Tier 2: VS Code + Copilot (Low-Code)**
Best for: Product managers, analysts, technically curious non-engineers.
- VS Code in the browser (code-server or OpenVSCode Server)
- GitHub Copilot for AI-assisted coding
- Familiar IDE interface with file explorer, terminal, extensions
- Qovery CLI + skills pre-installed for one-command deployment

**Tier 3: Terminal + Claude Code / OpenCode (Code-Comfortable)**
Best for: Technical PMs, data scientists, engineers from other teams.
- Full terminal environment with AI coding agents
- Claude Code or OpenCode for conversational coding
- Maximum power and flexibility
- Web terminal via ttyd or similar

Ask:
> "Based on your builders' profiles, which experience(s) do you want to offer? You can choose multiple — each builder will get the tier that matches their level."

---

## PHASE 2: Set Up the Platform Foundation

### 2.1 Resolve Organization & Cluster

**Shortcut:** If the user provided a Qovery Console URL, extract the organization ID from it.

After authenticating, list all organizations:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | {id, name}'
```

- **If 1 organization**: Confirm and move on.
- **If multiple**: Present the list and ask which one to use.

Then list all clusters:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'
```

**Recommendation:** Use a **dedicated cluster** for builder environments, separate from production. This provides:
- Cost isolation (builder costs are clearly separated)
- Security isolation (builders can't accidentally affect production)
- Different instance types (smaller, cheaper nodes for dev workloads)
- Independent scaling

If no suitable cluster exists, reference the qovery-onboard skill: "Say 'Set up Qovery for my organization' to create a new cluster."

### 2.2 Create the Builder Project(s)

Based on the isolation level chosen in Phase 1.3, create the project structure:

**Option A: Shared Project** (all builders in one project)

Create a single project for the blueprint template and all builder environments:

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-workspaces", "description": "Self-service builder environments for non-tech teams"}'
```

This project will contain:
- The builder environment blueprint (template)
- All individual builder environments (one per builder — NOT shared)

Simpler to manage, but builders can see each other's environment names in the Qovery Console (though RBAC prevents them from modifying each other's environments).

**Option B: Project-per-Builder** (full isolation — recommended for security)

Create a **blueprints project** for the template, then a **separate project per builder** during provisioning (Phase 4):

```bash
# Create the blueprints project (holds only the template — builders don't see this)
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-blueprints", "description": "Blueprint templates for builder environments (platform team only)"}'
```

Individual builder projects will be created during provisioning (Phase 4.2) — one project per builder named `builder-{name}`. Each builder's RBAC role is scoped to their own project only, so they cannot see anyone else's environments or data.

This is the recommended approach when:
- Builders work with sensitive data (CRM, financial, customer PII)
- Compliance requires environment isolation (SOC2, ISO 27001, HIPAA)
- The organization has many builders (20+)
- Different teams should not see each other's work

### 2.3 Set Up RBAC — Create a "Builder" Custom Role

Create a custom role with restricted permissions so builders can deploy their own environments but cannot touch production or other projects.

**Step 1: Create the custom role**
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/customRole" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Builder", "description": "Non-tech builders: can deploy dev environments, no production access"}'
```

**Step 2: Configure cluster permissions**

The cluster permission is the same regardless of isolation mode:
```bash
curl -s -X PUT "https://api.qovery.com/organization/{orgId}/customRole/{roleId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Builder",
    "description": "Non-tech builders: can deploy dev environments, no production access",
    "cluster_permissions": [
      {"cluster_id": "{builderClusterId}", "permission": "ENV_CREATOR"},
      {"cluster_id": "{prodClusterId}", "permission": "VIEWER"}
    ],
    "project_permissions": []
  }'
```

**Step 3: Configure project permissions (depends on isolation mode)**

**If shared project** (Option A):
Add the shared project to the role so all builders can access it:
```bash
# Add project permissions for the shared builder-workspaces project
# All builders share this role and can see each other's environments
"project_permissions": [
  {
    "project_id": "{builderWorkspacesProjectId}",
    "is_admin": false,
    "permissions": [
      {"environment_type": "DEVELOPMENT", "permission": "DEPLOYER"},
      {"environment_type": "STAGING", "permission": "VIEWER"},
      {"environment_type": "PRODUCTION", "permission": "NO_ACCESS"},
      {"environment_type": "PREVIEW", "permission": "DEPLOYER"}
    ]
  }
]
```

**If project-per-builder** (Option B):
Do NOT add project permissions at role creation time. Instead, each builder's project permissions are added **dynamically** during provisioning (Phase 4.2) when their project is created. This means:
- The base "Builder" role has cluster permissions only (no project permissions yet)
- When a builder is provisioned, the provisioning script updates the role OR creates a unique per-builder role that includes their specific project
- Each builder can ONLY see their own project

IMPORTANT: With project-per-builder isolation, you have two approaches:
1. **One role, dynamically updated**: Add each new builder's project to the shared "Builder" role. Simpler, but all builders share the same role definition. They can't actually access each other's environments because DEPLOYER only lets them deploy within their own project's environments.
2. **Per-builder roles**: Create a unique role per builder (e.g., "Builder-Alice") scoped to only their project. Maximum isolation — each builder has their own role with access to only their project. The provisioning script handles role creation automatically.

Recommend approach 2 (per-builder roles) for maximum security.

This ensures builders can:
- Deploy and manage their own DEVELOPMENT environments
- See logs, access URLs, and manage environment variables in THEIR environment only
- Access their environment via web IDE URL
- NOT touch production environments
- NOT see other builders' projects or environments (project-per-builder mode)
- NOT modify cluster settings

### 2.4 Configure SSO (if applicable)

If the company uses SSO (Google Workspace, Okta, Azure AD, etc.):

1. Guide the platform engineer to Qovery Console > Organization Settings > Authentication
2. Configure SAML or SSO integration
3. Ensure builders authenticate with company credentials
4. Map SSO groups to the "Builder" custom role if supported

> "SSO ensures builders log in with their company credentials. This means:
> - No separate passwords to manage
> - Automatic deprovisioning when someone leaves the company
> - Audit trail tied to real identities"

---

## PHASE 3: Create the Builder Environment Template

The template is a fully configured environment that will be cloned for each builder. It contains the AI coding tools, Qovery CLI, pre-installed skills, and optionally a database and starter application.

### 3.1 Design the Environment Blueprint

Based on the answers from Phase 1, determine which services the template needs:

**Always included:**
1. **AI Coding Tool** — the builder's primary interface (Container service)
   - Choice from Phase 1.4: VS Code Server, OpenVSCode, or Terminal

**Included if builders need data storage:**
2. **Database** — PostgreSQL (container mode for dev)
   - Pre-configured with connection variables
   - Builders can access it from their applications

**Included if builders need a starter project:**
3. **Backend API template** — pre-scaffolded API (Application service)
   - Express.js / FastAPI / Go starter
   - Connected to database via environment variables
   - Health check endpoint configured

4. **Frontend template** — pre-scaffolded UI (Application service)
   - React / Next.js / Vite starter
   - Connected to backend API

### 3.2 Build the AI Coding Tool Container

Create a Dockerfile for the builder's primary workspace. Choose ONE of the following options based on Phase 1.4.

**Option A: VS Code Server + Copilot + Qovery CLI**

Best for: Low-code builders who want a familiar IDE experience.

```dockerfile
# Builder Workspace — VS Code Server
# Includes: VS Code, GitHub Copilot, Qovery CLI, Qovery Skills, Node.js, Python, Git
FROM codercom/code-server:4.99.4

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Install Qovery Skills (deploy, troubleshoot, builder-env)
RUN mkdir -p /home/coder/.local/share/code-server/skills \
    && curl -fsSL https://skill.qovery.com/install.sh | bash

# Install Claude Code (AI coding agent)
RUN npm install -g @anthropic-ai/claude-code 2>/dev/null || true

# Install OpenCode (AI coding agent)
RUN curl -fsSL https://opencode.ai/install.sh | bash 2>/dev/null || true

# Pre-install VS Code extensions
RUN code-server --install-extension github.copilot 2>/dev/null || true \
    && code-server --install-extension ms-python.python 2>/dev/null || true \
    && code-server --install-extension bradlc.vscode-tailwindcss 2>/dev/null || true \
    && code-server --install-extension esbenp.prettier-vscode 2>/dev/null || true

# Configure code-server
RUN mkdir -p /home/coder/.config/code-server
COPY <<'EOF' /home/coder/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF

# Set correct ownership
RUN chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder/project

EXPOSE 8080

ENTRYPOINT ["code-server", "--host", "0.0.0.0", "--port", "8080"]
```

**Option B: OpenVSCode Server (Lighter Weight)**

Best for: Same as Option A but uses Gitpod's lighter OpenVSCode Server.

```dockerfile
# Builder Workspace — OpenVSCode Server
# Lighter than code-server, same VS Code experience
FROM gitpod/openvscode-server:latest

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Install Qovery Skills
RUN curl -fsSL https://skill.qovery.com/install.sh | bash

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code 2>/dev/null || true

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install.sh | bash 2>/dev/null || true

USER openvscode-server
WORKDIR /home/workspace/project

EXPOSE 3000

ENTRYPOINT ["/home/.openvscode-server/bin/openvscode-server", "--host", "0.0.0.0", "--port", "3000", "--without-connection-token"]
```

**Option C: Terminal-Only (OpenCode + Claude Code)**

Best for: Code-comfortable builders who prefer terminal-based AI agents.

```dockerfile
# Builder Workspace — Terminal Only
# Includes: OpenCode, Claude Code, Qovery CLI, web terminal (ttyd)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    ca-certificates \
    build-essential \
    tmux \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd (web-based terminal)
RUN curl -fsSL -o /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# Install Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Install Qovery Skills
RUN curl -fsSL https://skill.qovery.com/install.sh | bash

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install.sh | bash

# Create non-root user
RUN useradd -m -s /bin/bash builder
USER builder
WORKDIR /home/builder/project

EXPOSE 8080

# Launch web terminal
ENTRYPOINT ["ttyd", "--port", "8080", "--writable", "bash"]
```

### 3.3 Configure AI API Keys as Platform Secrets

AI coding tools need API keys to function. These are managed **entirely by the platform team** — builders never see or configure them.

Set API keys at the **project level** so all builder environments inherit them:

```bash
# Anthropic API key (for Claude Code)
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "ANTHROPIC_API_KEY", "value": "{key}", "scope": "PROJECT", "is_secret": true}'

# OpenAI API key (for Copilot / GPT-based tools)
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "OPENAI_API_KEY", "value": "{key}", "scope": "PROJECT", "is_secret": true}'
```

Or via CLI:
```bash
qovery project env create --key ANTHROPIC_API_KEY --value "{key}" --scope PROJECT --secret
qovery project env create --key OPENAI_API_KEY --value "{key}" --scope PROJECT --secret
```

IMPORTANT:
- Keys are set as **secrets** — the values are encrypted and never displayed, not even to admins viewing env vars in the Console.
- Keys are set at **project scope** — every environment in the "builder-workspaces" project inherits them automatically.
- Builders **cannot** see the key values. They just work transparently in the background.
- The platform team is responsible for key rotation. To rotate: update the project-level secret, then redeploy the affected environments.

### 3.4 Create the Template Environment in Qovery

Create the template environment with all the services designed in Phase 3.1:

**Step 1: Create the environment**
```bash
curl -s -X POST "https://api.qovery.com/project/{projectId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "builder-template",
    "cluster": "{clusterId}",
    "mode": "DEVELOPMENT"
  }' | jq '{id, name, mode}'
```

**Step 2: Add the IDE container service**

The IDE is deployed as a Container service using the Dockerfile from Phase 3.2. Since the Dockerfile needs to live in a git repository for Qovery to build it, create a repository for the builder workspace images:

```bash
# Option A: If the platform team has a git repo for infrastructure
# Push the Dockerfile to a path like: infra/builder-workspace/Dockerfile

# Option B: Use a pre-built image from a container registry
# Build the Dockerfile locally and push to the org's container registry
# Then reference the image directly as a Container service
```

Create the application:
```bash
curl -s -X POST "https://api.qovery.com/environment/{templateEnvId}/application" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "workspace",
    "description": "AI-powered builder workspace",
    "git_repository": {
      "url": "{git-repo-url}",
      "branch": "main",
      "root_path": "/builder-workspace",
      "provider": "GITHUB"
    },
    "build_mode": "DOCKER",
    "dockerfile_path": "Dockerfile",
    "cpu": 1000,
    "memory": 2048,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {"internal_port": 8080, "external_port": 443, "publicly_accessible": true, "protocol": "HTTP", "is_default": true, "name": "ide"}
    ],
    "healthchecks": {
      "readiness_probe": {
        "type": {"tcp": {"port": 8080}},
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "failure_threshold": 9
      }
    },
    "auto_preview": false,
    "auto_deploy": false
  }'
```

**Step 3: Add a database (if needed)**
```bash
curl -s -X POST "https://api.qovery.com/environment/{templateEnvId}/database" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "postgres",
    "type": "POSTGRESQL",
    "version": "16",
    "mode": "CONTAINER",
    "accessibility": "PRIVATE",
    "cpu": 250,
    "memory": 256,
    "storage": 10
  }'
```

### 3.5 Deploy and Validate the Template

**Step 1: Deploy**
```bash
curl -s -X POST "https://api.qovery.com/environment/{templateEnvId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

**Step 2: Watch deployment**
```bash
# Poll until environment is DEPLOYED
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{templateEnvId}/statuses" | jq '{
    environment: .environment.state,
    services: [
      (.applications[] | {name: .name, state, type: "app"}),
      (.databases[] | {name: .name, state, type: "db"})
    ]
  }'
```

**Step 3: Validate the workspace is accessible**
```bash
# Get the workspace URL
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{workspaceAppId}/link" | jq '.results'
```

Open the URL in a browser and verify:
- The IDE loads correctly (VS Code Server, OpenVSCode, or web terminal)
- Qovery CLI is available: run `qovery version` in the terminal
- Qovery skills are installed: check skills directory
- AI coding tools work: try a simple prompt
- Database is accessible (if included): check connection environment variables

**Step 4: Stop the template to save resources**
```bash
curl -s -X POST "https://api.qovery.com/environment/{templateEnvId}/stop" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Confirm:
> "Builder template environment validated and stopped. It will be used as the base for all builder workspaces."

---

## PHASE 4: Provision Builder Environments

### 4.1 Strategy — One Environment Per Builder (Never Shared)

Each builder gets their **own isolated environment** cloned from the blueprint. Environments are **NEVER shared** between builders — this is a fundamental security and auditability requirement.

**How it works:**
1. The **blueprint environment** (created in Phase 3) serves as a template. It is never used directly by builders — it exists solely to be cloned.
2. Each builder gets a **clone of the blueprint** via the Qovery clone API. The clone includes all services (IDE, database, etc.) with an identical configuration.
3. Each builder connects to **their own environment** via a unique URL. They cannot see or access other builders' environments.
4. If project-per-builder isolation was chosen (Phase 1.3), each builder's environment lives in its **own Qovery project**, providing complete visibility isolation.

This ensures:
- **Isolation**: Builders can't interfere with each other's work — each has their own services, database, and data
- **Independence**: Each builder can deploy, restart, and manage their own environment without affecting others
- **Audit**: All actions are tracked per-environment, tied to the builder's identity
- **Cost tracking**: Per-builder cost visibility — you know exactly what each builder costs
- **Security**: With project-per-builder mode, builders cannot see each other's environment variables, secrets, or data

Naming convention: `builder-{name}` (e.g., `builder-alice`, `builder-bob`)

### 4.2 Clone Blueprint for Each Builder

For each builder, clone the blueprint environment into their own workspace. The exact steps depend on the isolation mode chosen in Phase 1.3.

**If project-per-builder isolation (Option B) — create the builder's project first:**

```bash
# 1. Create a dedicated project for this builder
PROJECT_ID=$(curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-{name}", "description": "Builder workspace for {name} ({team})"}' | jq -r '.id')

# 2. Create a per-builder RBAC role scoped to this project
ROLE_ID=$(curl -s -X POST "https://api.qovery.com/organization/{orgId}/customRole" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Builder-{name}", "description": "Builder role for {name} — access to builder-{name} project only"}' | jq -r '.id')

# 3. Configure the role with access to only this builder's project
curl -s -X PUT "https://api.qovery.com/organization/{orgId}/customRole/$ROLE_ID" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Builder-{name}\",
    \"cluster_permissions\": [
      {\"cluster_id\": \"{builderClusterId}\", \"permission\": \"ENV_CREATOR\"}
    ],
    \"project_permissions\": [
      {
        \"project_id\": \"$PROJECT_ID\",
        \"is_admin\": false,
        \"permissions\": [
          {\"environment_type\": \"DEVELOPMENT\", \"permission\": \"DEPLOYER\"},
          {\"environment_type\": \"STAGING\", \"permission\": \"VIEWER\"},
          {\"environment_type\": \"PRODUCTION\", \"permission\": \"NO_ACCESS\"},
          {\"environment_type\": \"PREVIEW\", \"permission\": \"DEPLOYER\"}
        ]
      }
    ]
  }"

# 4. Clone the blueprint into this builder's project
ENV_ID=$(curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"workspace\", \"cluster_id\": \"{clusterId}\", \"mode\": \"DEVELOPMENT\", \"project_id\": \"$PROJECT_ID\"}" | jq -r '.id')
```

Note: The clone API supports a `project_id` parameter that places the cloned environment into a different project than the source. This is how the blueprint (in the `builder-blueprints` project) is cloned into each builder's own project.

**If shared project (Option A) — clone directly into the shared project:**

```bash
# Clone the blueprint into the shared project (no project_id needed — it stays in the same project)
ENV_ID=$(curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-{name}", "cluster_id": "{clusterId}", "mode": "DEVELOPMENT"}' | jq -r '.id')
```

**Via CLI (shared project mode):**
```bash
qovery environment clone --environment "builder-template" --name "builder-{name}"
```

**After cloning (both modes), deploy the builder's environment:**
```bash
curl -s -X POST "https://api.qovery.com/environment/$ENV_ID/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

### 4.3 Invite Builders to Qovery

For each builder, invite them to the Qovery organization with the "Builder" custom role:

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/inviteMember" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "{builder-email}",
    "role_id": "{builderRoleId}"
  }'
```

The builder will receive an email invitation. With SSO configured, they log in with their company credentials.

### 4.4 Provisioning Script — The Platform Team's Main Tool

Generate a comprehensive provisioning script that the platform team uses to onboard new builders. This is the **primary operational tool** — it reads the platform configuration, creates everything needed for a new builder, and outputs the workspace URL.

The script handles both isolation modes and includes TTL lifecycle job creation.

**Single builder provisioning (`provision-builder.sh`):**

```bash
#!/usr/bin/env bash
# provision-builder.sh — Provision a single new builder environment
# Usage: ./provision-builder.sh <name> <email> <team>
# Example: ./provision-builder.sh alice alice@company.com sales
#
# Reads platform preferences from builder-platform-config.yaml
# Creates: project (if project-per-builder), environment (cloned from blueprint),
#          TTL lifecycle job, RBAC role, member invitation

set -euo pipefail

# --- Arguments ---
BUILDER_NAME="${1:?Usage: $0 <name> <email> <team>}"
BUILDER_EMAIL="${2:?Usage: $0 <name> <email> <team>}"
BUILDER_TEAM="${3:?Usage: $0 <name> <email> <team>}"

# --- Load platform config ---
CONFIG_FILE="$(dirname "$0")/../builder-platform-config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  echo "Run the qovery-builder-env skill first to generate the platform config."
  exit 1
fi

# Parse YAML config (requires yq or fallback to grep)
parse_config() {
  if command -v yq &>/dev/null; then
    yq -r "$1" "$CONFIG_FILE"
  else
    grep -A0 "$(echo "$1" | tr '.' '\n' | tail -1):" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"'
  fi
}

ORG_ID=$(parse_config '.organization_id')
CLUSTER_ID=$(parse_config '.cluster_id')
BLUEPRINT_ENV_ID=$(parse_config '.blueprint_env_id')
ISOLATION=$(parse_config '.isolation')
TTL_STOP_AFTER=$(parse_config '.ttl.stop_after')
TTL_DELETE_AFTER=$(parse_config '.ttl.delete_after')
SHARED_PROJECT_ID=$(parse_config '.shared_project_id')
BASE_ROLE_ID=$(parse_config '.builder_role_id')

API_TOKEN="${QOVERY_API_TOKEN:?Set QOVERY_API_TOKEN environment variable}"
BASE_URL="https://api.qovery.com"

echo "========================================="
echo "Provisioning builder: $BUILDER_NAME"
echo "  Email: $BUILDER_EMAIL"
echo "  Team:  $BUILDER_TEAM"
echo "  Mode:  $ISOLATION"
echo "========================================="
echo ""

# --- Step 1: Create project (if project-per-builder) ---
if [ "$ISOLATION" = "project-per-builder" ]; then
  echo "[1/6] Creating project: builder-$BUILDER_NAME"
  PROJECT_ID=$(curl -sf -X POST "$BASE_URL/organization/$ORG_ID/project" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"builder-$BUILDER_NAME\", \"description\": \"Builder workspace for $BUILDER_NAME ($BUILDER_TEAM)\"}" | jq -r '.id')
  echo "  Project created: $PROJECT_ID"
else
  echo "[1/6] Using shared project: $SHARED_PROJECT_ID"
  PROJECT_ID="$SHARED_PROJECT_ID"
fi

# --- Step 2: Create per-builder RBAC role (if project-per-builder) ---
if [ "$ISOLATION" = "project-per-builder" ]; then
  echo "[2/6] Creating RBAC role: Builder-$BUILDER_NAME"
  ROLE_ID=$(curl -sf -X POST "$BASE_URL/organization/$ORG_ID/customRole" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"Builder-$BUILDER_NAME\", \"description\": \"Builder role for $BUILDER_NAME — access to builder-$BUILDER_NAME project only\"}" | jq -r '.id')

  curl -sf -X PUT "$BASE_URL/organization/$ORG_ID/customRole/$ROLE_ID" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Builder-$BUILDER_NAME\",
      \"cluster_permissions\": [{\"cluster_id\": \"$CLUSTER_ID\", \"permission\": \"ENV_CREATOR\"}],
      \"project_permissions\": [{
        \"project_id\": \"$PROJECT_ID\",
        \"is_admin\": false,
        \"permissions\": [
          {\"environment_type\": \"DEVELOPMENT\", \"permission\": \"DEPLOYER\"},
          {\"environment_type\": \"STAGING\", \"permission\": \"VIEWER\"},
          {\"environment_type\": \"PRODUCTION\", \"permission\": \"NO_ACCESS\"},
          {\"environment_type\": \"PREVIEW\", \"permission\": \"DEPLOYER\"}
        ]
      }]
    }" > /dev/null
  echo "  Role created: $ROLE_ID"
else
  echo "[2/6] Using shared role: $BASE_ROLE_ID"
  ROLE_ID="$BASE_ROLE_ID"
fi

# --- Step 3: Clone the blueprint environment ---
echo "[3/6] Cloning blueprint into builder-$BUILDER_NAME"
CLONE_BODY="{\"name\": \"workspace\", \"cluster_id\": \"$CLUSTER_ID\", \"mode\": \"DEVELOPMENT\""
if [ "$ISOLATION" = "project-per-builder" ]; then
  CLONE_BODY="$CLONE_BODY, \"project_id\": \"$PROJECT_ID\""
else
  CLONE_BODY="{\"name\": \"builder-$BUILDER_NAME\", \"cluster_id\": \"$CLUSTER_ID\", \"mode\": \"DEVELOPMENT\""
fi
CLONE_BODY="$CLONE_BODY}"

ENV_ID=$(curl -sf -X POST "$BASE_URL/environment/$BLUEPRINT_ENV_ID/clone" \
  -H "Authorization: Token $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CLONE_BODY" | jq -r '.id')
echo "  Environment cloned: $ENV_ID"

# --- Step 4: Create TTL lifecycle job (auto-stop/delete) ---
if [ "$TTL_STOP_AFTER" != "null" ] && [ "$TTL_STOP_AFTER" != "none" ]; then
  echo "[4/6] Creating TTL lifecycle job (stop after $TTL_STOP_AFTER)"

  # Generate a shutdown token for this builder
  SHUTDOWN_TOKEN=$(curl -sf -X POST "$BASE_URL/organization/$ORG_ID/apiToken" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"builder-ttl-$BUILDER_NAME\", \"description\": \"Auto-shutdown token for builder-$BUILDER_NAME\"}" | jq -r '.token')

  # Calculate cron schedule based on TTL
  # For simplicity, this uses a relative approach — the cron job runs periodically
  # and checks if the environment has been running longer than the TTL
  CRON_SCHEDULE="0 */1 * * *"  # Check every hour

  # Create the TTL cron job
  TTL_JOB_ID=$(curl -sf -X POST "$BASE_URL/environment/$ENV_ID/job" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"ttl-auto-shutdown\",
      \"description\": \"Automatically stops this environment after $TTL_STOP_AFTER of uptime\",
      \"cpu\": 250,
      \"memory\": 256,
      \"max_nb_restart\": 0,
      \"max_duration_seconds\": 60,
      \"auto_preview\": false,
      \"auto_deploy\": false,
      \"healthchecks\": {},
      \"source\": {
        \"docker\": {
          \"dockerfile_raw\": \"FROM curlimages/curl:8.11.1\nENTRYPOINT [\\\"sh\\\", \\\"-c\\\"]\"
        }
      },
      \"schedule\": {
        \"cronjob\": {
          \"entrypoint\": \"sh\",
          \"arguments\": [\"-c\", \"curl -sf -X POST https://api.qovery.com/environment/$ENV_ID/stop -H 'Authorization: Token '\\''\$SHUTDOWN_TOKEN'\\'' && echo 'Environment stopped by TTL job' || echo 'Stop request failed or already stopped'\"],
          \"scheduled_at\": \"$CRON_SCHEDULE\",
          \"timezone\": \"Etc/UTC\"
        }
      }
    }" | jq -r '.id')

  # Set the shutdown token as a secret on the job
  curl -sf -X POST "$BASE_URL/application/$TTL_JOB_ID/secret" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"SHUTDOWN_TOKEN\", \"value\": \"$SHUTDOWN_TOKEN\"}" > /dev/null
  echo "  TTL job created: $TTL_JOB_ID"
else
  echo "[4/6] No TTL configured — skipping lifecycle job"
fi

# --- Step 5: Invite the builder ---
echo "[5/6] Inviting $BUILDER_EMAIL with role $ROLE_ID"
curl -sf -X POST "$BASE_URL/organization/$ORG_ID/inviteMember" \
  -H "Authorization: Token $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$BUILDER_EMAIL\", \"role_id\": \"$ROLE_ID\"}" > /dev/null 2>&1 || echo "  (already invited)"
echo "  Invitation sent"

# --- Step 6: Deploy the environment ---
echo "[6/6] Deploying builder-$BUILDER_NAME"
curl -sf -X POST "$BASE_URL/environment/$ENV_ID/deploy" \
  -H "Authorization: Token $API_TOKEN" > /dev/null
echo "  Deployment triggered"

echo ""
echo "========================================="
echo "Builder provisioned successfully!"
echo "  Name:        $BUILDER_NAME"
echo "  Email:       $BUILDER_EMAIL"
echo "  Team:        $BUILDER_TEAM"
echo "  Project:     $PROJECT_ID"
echo "  Environment: $ENV_ID"
echo "  Isolation:   $ISOLATION"
echo "  TTL:         ${TTL_STOP_AFTER:-none}"
echo ""
echo "  Console: https://console.qovery.com/organization/$ORG_ID/project/$PROJECT_ID/environment/$ENV_ID"
echo ""
echo "  The workspace URL will be available once deployment completes."
echo "  Check status: curl -s -H 'Authorization: Token \$QOVERY_API_TOKEN' \\"
echo "    'https://api.qovery.com/environment/$ENV_ID/statuses' | jq '.environment.state'"
echo "========================================="
```

**Bulk provisioning (`bulk-provision.sh`):**

```bash
#!/usr/bin/env bash
# bulk-provision.sh — Provision multiple builder environments from CSV
# Usage: ./bulk-provision.sh builders.csv
#
# CSV format: name,email,team
# Example:
#   alice,alice@company.com,sales
#   bob,bob@company.com,finance
#   carol,carol@company.com,ops

set -euo pipefail

CSV_FILE="${1:?Usage: $0 <builders.csv>}"
SCRIPT_DIR="$(dirname "$0")"

echo "Bulk provisioning from: $CSV_FILE"
echo ""

count=0
while IFS=, read -r name email team; do
  # Skip header row if present
  [[ "$name" == "name" ]] && continue
  # Skip empty lines
  [[ -z "$name" ]] && continue

  count=$((count + 1))
  echo "--- Builder $count: $name ---"
  "$SCRIPT_DIR/provision-builder.sh" "$name" "$email" "$team"
  echo ""
done < "$CSV_FILE"

echo "========================================="
echo "Bulk provisioning complete: $count builders provisioned."
echo "========================================="
```

### 4.5 Share Access URLs and Quick Start

After all environments are deployed, collect the workspace URLs:

```bash
# For each builder environment, get the workspace URL
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{workspaceAppId}/link" | jq '.results[0].url'
```

Present a summary to the platform engineer:

> **Builder Environments Provisioned**
>
> | Builder | Team | Environment | Workspace URL | Status |
> |---------|------|-------------|--------------|--------|
> | Alice | Sales | builder-alice | https://builder-alice-workspace.{domain} | DEPLOYED |
> | Bob | Finance | builder-bob | https://builder-bob-workspace.{domain} | DEPLOYING |
> | Carol | Ops | builder-carol | https://builder-carol-workspace.{domain} | DEPLOYED |
>
> **Console:** https://console.qovery.com/organization/{orgId}/project/{projectId}
>
> Share the workspace URLs with each builder along with the onboarding guide (Phase 9).

---

## PHASE 5: Cost Controls & Lifecycle Management

### 5.1 TTL Lifecycle Job — Auto-Stop and Auto-Delete

Each builder environment has a **TTL (time-to-live)** — a lifecycle job that automatically stops or deletes the environment after a configured duration. This is the primary cost control mechanism. The TTL was configured by the platform engineer in Phase 1.3 and is created automatically by the provisioning script (Phase 4.4).

**How the TTL lifecycle job works:**

1. A **cron job** is created inside each builder environment using a raw Dockerfile (`curlimages/curl:8.11.1` — no git repo needed)
2. The job runs on a schedule (e.g., every hour) and calls the Qovery API to **stop** the environment
3. A dedicated API token (`SHUTDOWN_TOKEN`) is stored as a secret on the job — the builder cannot see or modify it
4. The platform team controls the TTL via the `builder-platform-config.yaml` file

**TTL cron job creation (via API):**

This is already handled by the provisioning script (Phase 4.4, Step 4), but here's the standalone API call for reference:

```bash
# 1. Generate a shutdown token
SHUTDOWN_TOKEN=$(curl -sf -X POST "https://api.qovery.com/organization/{orgId}/apiToken" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-ttl-{name}", "description": "Auto-shutdown token for builder-{name}"}' | jq -r '.token')

# 2. Create the TTL cron job
JOB_ID=$(curl -sf -X POST "https://api.qovery.com/environment/{builderEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-shutdown",
    "description": "Automatically stops this environment after the configured TTL",
    "cpu": 250,
    "memory": 256,
    "max_nb_restart": 0,
    "max_duration_seconds": 60,
    "auto_preview": false,
    "auto_deploy": false,
    "healthchecks": {},
    "source": {
      "docker": {
        "dockerfile_raw": "FROM curlimages/curl:8.11.1\nENTRYPOINT [\"sh\", \"-c\"]"
      }
    },
    "schedule": {
      "cronjob": {
        "entrypoint": "sh",
        "arguments": ["-c", "curl -sf -X POST https://api.qovery.com/environment/{builderEnvId}/stop -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo \"Environment stopped by TTL\" || echo \"Already stopped or failed\""],
        "scheduled_at": "0 20 * * 1-5",
        "timezone": "Europe/Paris"
      }
    }
  }' | jq -r '.id')

# 3. Set the shutdown token as a secret
curl -sf -X POST "https://api.qovery.com/application/$JOB_ID/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"SHUTDOWN_TOKEN\", \"value\": \"$SHUTDOWN_TOKEN\"}"
```

**Common TTL cron schedules:**

| TTL | Cron Expression | Description |
|-----|----------------|-------------|
| Business hours | `0 20 * * 1-5` | Stop at 8pm weekdays |
| 8 hours | `0 */8 * * *` | Stop every 8 hours |
| 24 hours | `0 0 * * *` | Stop at midnight daily |
| 1 week | `0 0 * * 0` | Stop every Sunday midnight |
| Specific date | `0 10 15 6 *` | Stop at 10am on June 15 |

**Auto-delete after extended inactivity (optional):**

If the platform engineer configured a `delete_after` TTL in addition to `stop_after`, create a **second cron job** that deletes the environment if it has been stopped for longer than the specified period:

```bash
# Delete job — runs weekly, checks if environment has been stopped for > N days
curl -sf -X POST "https://api.qovery.com/environment/{builderEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-delete",
    "description": "Deletes this environment if stopped for more than 7 days",
    "cpu": 250,
    "memory": 256,
    "max_nb_restart": 0,
    "max_duration_seconds": 60,
    "auto_preview": false,
    "auto_deploy": false,
    "healthchecks": {},
    "source": {
      "docker": {
        "dockerfile_raw": "FROM curlimages/curl:8.11.1\nENTRYPOINT [\"sh\", \"-c\"]"
      }
    },
    "schedule": {
      "cronjob": {
        "entrypoint": "sh",
        "arguments": ["-c", "curl -sf -X DELETE https://api.qovery.com/environment/{builderEnvId} -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo \"Environment deleted by TTL\" || echo \"Delete failed or already deleted\""],
        "scheduled_at": "0 0 * * 0",
        "timezone": "Etc/UTC"
      }
    }
  }'
```

### 5.2 Business Hours Schedule (Complementary to TTL)

In addition to the TTL lifecycle job, configure deployment rules to stop environments during off-hours for additional savings:

**Business hours schedule (recommended):**
- Start: weekdays at 8:00 AM (builder's timezone)
- Stop: weekdays at 8:00 PM (builder's timezone)
- Weekends: stopped all day

This works alongside the TTL — the business hours schedule handles daily stop/start, while the TTL handles the overall environment lifetime.

### 5.2 Resource Limits Per Builder

Set per-environment resource limits to prevent cost overruns:

| Resource | Recommended for Dev | Notes |
|----------|-------------------|-------|
| IDE CPU | 1000m (1 core) | Enough for VS Code + AI tools |
| IDE Memory | 2048MB (2GB) | Increase to 4GB for heavy AI workloads |
| Database CPU | 250m | Container mode only for dev |
| Database Memory | 256MB | Increase for larger datasets |
| Database Storage | 10GB | Sufficient for dev data |

These are set when creating the template (Phase 3.4) and inherited by all cloned environments.

### 5.3 Cost Monitoring & Alerts

Show the platform engineer how to monitor builder costs:

```bash
# View all builder environments and their statuses
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '[.results[] | {name, mode, cluster_id}]'
```

Recommendations:
- Use the Qovery Console dashboard for visual cost monitoring
- Set up budget alerts in your cloud provider (AWS Budgets, GCP Budgets, Azure Cost Alerts)
- Reference the qovery-optimize skill for deeper cost analysis: "Say 'Optimize my Qovery costs' for a detailed cost report"

### 5.4 Environment Cleanup Policy

Establish a cleanup policy for inactive builder environments:

- **30 days inactive** -> warn the builder, ask if still needed
- **60 days inactive** -> stop the environment automatically
- **90 days inactive** -> delete the environment (with warning)

Track last activity via the Qovery API:
```bash
# Check deployment history (last activity) for each environment
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/deploymentHistory?version=v2" | jq '.results[0].created_at'
```

---

## PHASE 6: Deployment Plan Summary

Before executing any operations, present a complete summary and get explicit confirmation.

### 6.1 Generate the Summary

> **Builder Environment Platform Plan**
>
> **Target Infrastructure:**
> - Organization: **{org_name}** (`{org_id}`)
> - Cluster: **{cluster_name}** ({cloud_provider}, {region}) — dedicated for builders
> - Project: **builder-workspaces** *(new — will be created)*
>
> **RBAC:**
> - Custom role: **Builder** — DEPLOYER on DEV, VIEWER on staging, NO_ACCESS on production
> - Cluster permission: ENV_CREATOR on builder cluster
>
> **Builder Template:**
>
> | Service | Type | Image / Config | CPU | Memory | Port |
> |---------|------|---------------|-----|--------|------|
> | workspace | Application | VS Code Server (code-server) | 1000m | 2048MB | 8080 |
> | postgres | Database | PostgreSQL 16 (container) | 250m | 256MB | 5432 |
>
> **Pre-installed tools:** {VS Code + Copilot, Qovery CLI, Qovery Skills, Claude Code, OpenCode}
>
> **AI API Keys (platform-managed secrets):**
> - `ANTHROPIC_API_KEY` — set at project scope (secret)
> - `OPENAI_API_KEY` — set at project scope (secret)
>
> **Builders to provision:** {count}
> {list of builders with name, email, team}
>
> **Cost Controls:**
> - Auto-stop: weekdays 8pm-8am, weekends all day
> - Resource limits: {CPU}m CPU, {Memory}MB RAM per builder
> - Estimated cost: ~${X}/builder/month (stopped overnight)
>
> **Security:**
> - SSO: {provider or "not configured"}
> - Compliance: {SOC2, ISO 27001, etc. or "Qovery default (SOC2)"}
> - Audit trail: all operations tracked per-builder
>
> **Infrastructure as Code:** {Terraform / Scripts / Local only}
>
> **Warnings:**
> - Database data is per-builder (not shared) — each builder gets an empty database
> - AI API keys will be billed to the platform team's accounts
> - Builder environments consume cluster resources while running

### 6.2 Get Confirmation

> "Does this plan look correct? I'll proceed with creating the platform once you confirm. Let me know if you want to change anything."

**CRITICAL: Do NOT proceed until the user explicitly confirms.**

### 6.3 Handle Changes

If the user wants to modify the plan, adjust and re-present the full summary. Common changes:
- Different cluster
- Different IDE option
- Add/remove builders
- Change resource limits
- Change auto-stop schedule
- Add/remove database

---

## PHASE 7: Execute & Verify

Execute the plan in order:

### 7.1 Create the Builder Project
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-workspaces"}'
```

### 7.2 Create the "Builder" Custom Role
(Phase 2.3 commands)

### 7.3 Set AI API Keys as Project Secrets
(Phase 3.3 commands)

### 7.4 Create the Template Environment + IDE Container + Database
(Phase 3.4 commands)

### 7.5 Deploy and Validate the Template
(Phase 3.5 commands — deploy, watch, verify IDE access, stop)

### 7.6 Clone Template for Each Builder
(Phase 4.2 commands — loop over builders list)

### 7.7 Deploy All Builder Environments
(Phase 4.2 deploy commands)

### 7.8 Invite Builders to Qovery
(Phase 4.3 commands — loop over builders list)

### 7.9 Collect and Share Workspace URLs
(Phase 4.5 commands — get URLs, present summary)

Watch each deployment and verify all builder environments are accessible. If any fail, fetch logs and diagnose:
```bash
qovery log --service "workspace" --since 10m --filter "ERROR"
```

---

## PHASE 7B: Production Graduation (Optional)

When a builder's application is ready to serve real users (internal or external), it needs to go through a controlled promotion process. This phase is optional — only include it if the platform engineer indicated in Phase 1.3 that some builder apps may go to production.

### 7B.1 Review Process

When a builder requests production deployment:

1. **Platform team reviews the application:**
   - Code quality (AI-generated code should be reviewed)
   - Security (no hardcoded secrets, proper authentication, input validation)
   - Dependencies (no vulnerable packages, no unnecessary dependencies)
   - Data handling (PII protection, GDPR compliance if applicable)

2. **Create a staging environment:**
   ```bash
   curl -s -X POST "https://api.qovery.com/environment/{builderEnvId}/clone" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "staging-{app-name}",
       "cluster_id": "{prodClusterId}",
       "mode": "STAGING"
     }'
   ```

3. **Deploy to staging and validate:**
   - Run health checks
   - Test with production-like data (anonymized if PII)
   - Load test if the app will serve many users
   - Security scan

### 7B.2 Promote to Production

If the staging review passes:

1. **Clone the staging environment to production:**
   ```bash
   curl -s -X POST "https://api.qovery.com/environment/{stagingEnvId}/clone" \
     -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "prod-{app-name}",
       "cluster_id": "{prodClusterId}",
       "mode": "PRODUCTION"
     }'
   ```

2. **Upgrade resources for production:**
   - Switch database from container mode to managed (e.g., RDS):
     Delete the container database and create a managed one
   - Increase CPU/memory for the application
   - Configure autoscaling if needed
   - Set up a custom domain
   - Enable monitoring and alerts

3. **Set up CI/CD:**
   - Configure auto-deploy from the application's git branch
   - Set up the review/approval process for future changes

IMPORTANT: The builder should NOT have direct access to the production environment. Only the platform team (Admin/DevOps role) can manage production resources.

---

## PHASE 8: Version Control & Infrastructure as Code

All platform configuration should be version-controlled so the setup is reproducible, auditable, and maintainable.

### 8.1 Generate Config Folder Structure

Propose a folder structure for all platform configuration:

```
qovery-builder-platform/
├── builder-platform-config.yaml       # Platform preferences (isolation, TTL, resources, IDs)
├── README.md                          # Platform documentation
├── dockerfiles/
│   ├── vscode-server/
│   │   └── Dockerfile                 # VS Code Server workspace image
│   ├── openvscode/
│   │   └── Dockerfile                 # OpenVSCode workspace image
│   └── terminal/
│       └── Dockerfile                 # Terminal-only workspace image
├── scripts/
│   ├── provision-builder.sh           # Provision a single new builder (reads config)
│   ├── bulk-provision.sh              # Bulk provision from CSV
│   ├── cleanup-inactive.sh            # Remove unused environments
│   └── rotate-api-keys.sh            # Rotate AI API keys across all envs
├── builders/
│   └── builders.csv                   # List of builders (name,email,team)
├── templates/
│   ├── builder-onboarding.md          # Guide sent to new builders
│   └── platform-runbook.md            # Platform team operations guide
└── terraform/                         # (if Terraform chosen)
    ├── main.tf                        # Qovery project, template env, RBAC
    ├── variables.tf                   # Input variables
    ├── terraform.tfvars               # Values (org ID, cluster ID, keys)
    ├── outputs.tf                     # Workspace URLs, env IDs
    └── modules/
        └── builder-env/               # Reusable module per builder
            ├── main.tf
            ├── variables.tf
            └── outputs.tf
```

**The platform config file (`builder-platform-config.yaml`)** stores all preferences from Phase 1 and IDs generated during Phase 7. It is read by the provisioning script:

```yaml
# builder-platform-config.yaml
# Generated by qovery-builder-env skill — do not edit manually unless you know what you're doing.

# Qovery identifiers
organization_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
cluster_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
blueprint_env_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Isolation mode: "shared-project" or "project-per-builder"
isolation: "project-per-builder"

# Only used if isolation is "shared-project"
shared_project_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# Only used if isolation is "shared-project"
builder_role_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# IDE tier: "vscode-server", "openvscode", or "terminal"
ide_tier: "vscode-server"

# TTL (time-to-live) for builder environments
ttl:
  stop_after: "24h"       # Stop after this duration (e.g., "8h", "24h", "48h", "1w", "none")
  delete_after: "7d"      # Delete after being stopped for this duration (e.g., "7d", "30d", "none")
  cron_schedule: "0 20 * * 1-5"  # Cron for business hours stop (8pm weekdays)

# Resource limits per builder environment
resources:
  workspace_cpu: 1000     # millicores
  workspace_memory: 2048  # MB
  database_enabled: true
  database_cpu: 250       # millicores
  database_memory: 256    # MB
  database_storage: 10    # GB

# Dockerfile location
ide_git_repository_url: "https://github.com/{org}/qovery-builder-platform"
ide_dockerfile_path: "dockerfiles/vscode-server/Dockerfile"
```

This file is:
- **Generated** by the skill during Phase 7 (after the platform is set up)
- **Read** by `provision-builder.sh` to create new builder environments
- **Version-controlled** alongside the rest of the platform config
- **Updated** when the platform team changes preferences (e.g., different TTL, resource limits)

### 8.2 Ask Where to Save

> "Where should I save the platform configuration?"
>
> 1. **Create a new git repository** — I'll initialize a new repo (e.g., `qovery-builder-platform`)
> 2. **Add to an existing repository** — provide the path or clone URL
> 3. **Save locally only** — generate the files without git

If they choose option 1 or 2, also ask:
> "Should I push the configuration to the remote repository?"

### 8.3 Terraform Option

> "Do you want to manage the platform setup via Terraform?"
>
> This generates `.tf` manifests using the [Qovery Terraform provider](https://registry.terraform.io/providers/Qovery/qovery/latest/docs) so your entire builder platform is defined as infrastructure-as-code. Changes are version-controlled and reproducible.
>
> - **Yes (Recommended for production)** — generates complete Terraform manifests
> - **No** — saves the API/CLI commands as shell scripts instead

If yes, generate the Terraform manifests:

**terraform/variables.tf:**
```hcl
variable "qovery_organization_id" {
  description = "Qovery organization ID"
  type        = string
}

variable "qovery_cluster_id" {
  description = "Cluster ID for builder environments"
  type        = string
}

variable "isolation" {
  description = "Isolation mode: 'shared-project' or 'project-per-builder'"
  type        = string
  default     = "project-per-builder"
}

variable "ttl_stop_cron" {
  description = "Cron schedule for TTL auto-stop (e.g., '0 20 * * 1-5' for 8pm weekdays)"
  type        = string
  default     = "0 20 * * 1-5"
}

variable "ttl_delete_cron" {
  description = "Cron schedule for TTL auto-delete (e.g., '0 0 * * 0' for weekly). Set to empty string to disable."
  type        = string
  default     = ""
}

variable "builders" {
  description = "Map of builders to provision"
  type = map(object({
    email = string
    team  = string
  }))
  default = {}
}

variable "ide_git_repository_url" {
  description = "Git repository URL containing the workspace Dockerfile"
  type        = string
}

variable "ide_dockerfile_path" {
  description = "Path to the Dockerfile within the repository"
  type        = string
  default     = "dockerfiles/vscode-server/Dockerfile"
}

variable "workspace_cpu" {
  description = "CPU allocation for workspace (millicores)"
  type        = number
  default     = 1000
}

variable "workspace_memory" {
  description = "Memory allocation for workspace (MB)"
  type        = number
  default     = 2048
}

variable "include_database" {
  description = "Include a PostgreSQL database in each builder environment"
  type        = bool
  default     = true
}
```

**terraform/main.tf:**
```hcl
terraform {
  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = ">= 0.54.0"
    }
  }
}

provider "qovery" {}

# Data source for the organization
data "qovery_organization" "main" {
  id = var.qovery_organization_id
}

# Blueprints project (holds the template — not accessed by builders)
resource "qovery_project" "blueprints" {
  organization_id = var.qovery_organization_id
  name            = var.isolation == "project-per-builder" ? "builder-blueprints" : "builder-workspaces"
  description     = var.isolation == "project-per-builder" ? "Blueprint templates (platform team only)" : "Self-service builder environments for non-tech teams"
}

# Builder blueprint environment (template — cloned for each builder)
resource "qovery_environment" "blueprint" {
  project_id = qovery_project.blueprints.id
  cluster_id = var.qovery_cluster_id
  name       = "builder-blueprint"
  mode       = "DEVELOPMENT"
}

# Workspace IDE application (in the blueprint)
resource "qovery_application" "workspace_blueprint" {
  environment_id = qovery_environment.blueprint.id
  name           = "workspace"

  git_repository = {
    url       = var.ide_git_repository_url
    branch    = "main"
    root_path = "/"
  }

  build_mode      = "DOCKER"
  dockerfile_path = var.ide_dockerfile_path
  cpu             = var.workspace_cpu
  memory          = var.workspace_memory

  min_running_instances = 1
  max_running_instances = 1
  auto_preview          = false
  auto_deploy           = false

  ports = {
    "ide" = {
      internal_port       = 8080
      external_port       = 443
      publicly_accessible = true
      protocol            = "HTTP"
      is_default          = true
    }
  }

  healthchecks = {
    readiness_probe = {
      type = {
        tcp = {
          port = 8080
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      failure_threshold     = 9
    }
  }
}

# Database (in the blueprint)
resource "qovery_database" "postgres_blueprint" {
  count          = var.include_database ? 1 : 0
  environment_id = qovery_environment.blueprint.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "CONTAINER"
  accessibility  = "PRIVATE"
  cpu            = 250
  memory         = 256
  storage        = 10
}

# AI API keys as project-level secrets
# Note: Secrets must be managed via the Qovery API or Console — Terraform
# does not expose secret values for security. Set these manually:
#   ANTHROPIC_API_KEY, OPENAI_API_KEY
# at project scope on the blueprints project (inherited by cloned environments).

# Individual builder environments (one per builder — NEVER shared)
module "builder" {
  source   = "./modules/builder-env"
  for_each = var.builders

  organization_id  = var.qovery_organization_id
  builder_name     = each.key
  builder_email    = each.value.email
  builder_team     = each.value.team
  shared_project_id = qovery_project.blueprints.id
  cluster_id       = var.qovery_cluster_id
  blueprint_env_id = qovery_environment.blueprint.id
  isolation        = var.isolation
  ttl_stop_cron    = var.ttl_stop_cron
  ttl_delete_cron  = var.ttl_delete_cron
}
```

**terraform/modules/builder-env/main.tf:**
```hcl
variable "organization_id" { type = string }
variable "builder_name" { type = string }
variable "builder_email" { type = string }
variable "builder_team" { type = string }
variable "shared_project_id" { type = string }
variable "cluster_id" { type = string }
variable "blueprint_env_id" { type = string }
variable "isolation" { type = string }
variable "ttl_stop_cron" { type = string }
variable "ttl_delete_cron" { type = string }

# Step 1: Create per-builder project (if project-per-builder isolation)
resource "qovery_project" "builder" {
  count           = var.isolation == "project-per-builder" ? 1 : 0
  organization_id = var.organization_id
  name            = "builder-${var.builder_name}"
  description     = "Builder workspace for ${var.builder_name} (${var.builder_team})"
}

locals {
  project_id = var.isolation == "project-per-builder" ? qovery_project.builder[0].id : var.shared_project_id
}

# Step 2: Clone the blueprint environment into the builder's project
# Note: Environment cloning is not natively supported in the Qovery Terraform provider.
# Use a null_resource with the Qovery API to clone the blueprint.
resource "null_resource" "clone_blueprint" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -sf -X POST "https://api.qovery.com/environment/${var.blueprint_env_id}/clone" \
        -H "Authorization: Token $QOVERY_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "workspace", "cluster_id": "${var.cluster_id}", "mode": "DEVELOPMENT", "project_id": "${local.project_id}"}'
    EOT
  }

  triggers = {
    builder_name = var.builder_name
    project_id   = local.project_id
  }

  depends_on = [qovery_project.builder]
}

# Step 3: Invite the builder
resource "null_resource" "invite_builder" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -sf -X POST "https://api.qovery.com/organization/${var.organization_id}/inviteMember" \
        -H "Authorization: Token $QOVERY_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"email": "${var.builder_email}", "role_id": "TODO_ROLE_ID"}' || true
    EOT
  }

  triggers = {
    builder_email = var.builder_email
  }

  depends_on = [null_resource.clone_blueprint]
}

# Note: The TTL lifecycle job and per-builder RBAC role creation are handled
# by the provisioning script (provision-builder.sh) since they require
# dynamic API calls that are complex to express in Terraform.
# For full automation, use the provisioning script alongside Terraform.

output "project_id" {
  value = local.project_id
}

output "builder_name" {
  value = "builder-${var.builder_name}"
}
```

**terraform/terraform.tfvars:**
```hcl
qovery_organization_id = "{org-id}"
qovery_cluster_id      = "{cluster-id}"
isolation              = "project-per-builder"  # or "shared-project"
ttl_stop_cron          = "0 20 * * 1-5"         # Stop at 8pm weekdays
ttl_delete_cron        = ""                      # Empty = no auto-delete
ide_git_repository_url = "https://github.com/{org}/qovery-builder-platform"
ide_dockerfile_path    = "dockerfiles/vscode-server/Dockerfile"
workspace_cpu          = 1000
workspace_memory       = 2048
include_database       = true

# Each builder gets their own isolated environment (NEVER shared)
builders = {
  alice = { email = "alice@company.com", team = "sales" }
  bob   = { email = "bob@company.com",   team = "finance" }
  carol = { email = "carol@company.com", team = "ops" }
}

# To add a new builder: add a line here and run `terraform apply`
# To remove a builder: remove the line and run `terraform apply`
```

### 8.4 Commit and Push

Generate all the files into the config folder structure, then:

```bash
# Initialize git repo (if new)
cd qovery-builder-platform
git init
git add -A
git commit -m "feat: initial builder platform configuration

- Dockerfiles for VS Code Server, OpenVSCode, and terminal workspaces
- Provisioning scripts (single + bulk)
- Terraform manifests for Qovery project, environments, and RBAC
- Builder onboarding guide and platform runbook
- Builder list (CSV)"

# Push to remote (if provided)
git remote add origin {remote-url}
git push -u origin main
```

Tell the platform team:
> "Your builder platform configuration is version-controlled at **{url}**.
>
> To add a new builder:
> - **Terraform**: Add an entry to `builders` in `terraform.tfvars` and run `terraform apply`
> - **Scripts**: Add a row to `builders/builders.csv` and run `./scripts/provision-builder.sh`
>
> To update the workspace image: modify the Dockerfile, push, and redeploy the template."

---

## PHASE 9: Builder Onboarding Guide

Generate two documents for the platform team to use.

### 9.1 Builder Quick Start Guide

Generate a simple, non-technical guide to share with each builder:

> # Welcome to Your Builder Workspace!
>
> ## Getting Started
>
> 1. **Open your workspace:** Click the link you received from the platform team
>    - URL: `{workspace-url}`
> 2. **Log in** with your company credentials ({SSO provider})
> 3. **Start building!** Your workspace has an AI assistant built in.
>    - Describe what you want to create in plain language
>    - The AI will help you build it step by step
> 4. **Deploy your app** when ready:
>    - Type `deploy this with Qovery` in the terminal
>    - Follow the prompts — your app will be live in minutes
>
> ## What You Can Build
>
> - Internal dashboards and analytics tools
> - Sales and CRM tools
> - Automation workflows
> - Data visualization tools
> - Anything that helps your team work better!
>
> ## What You Don't Need to Worry About
>
> - Server setup (handled by the platform)
> - Security configuration (handled by the platform)
> - Database management (pre-configured for you)
> - API keys (pre-configured by the platform team)
>
> ## Need Help?
>
> - **Ask the AI**: It can help with coding, debugging, and deployment
> - **Platform team**: Reach out on {Slack channel / email}
> - **Qovery Console**: https://console.qovery.com (for monitoring your apps)
>
> ## Rules
>
> - Your workspace auto-stops at {time} to save costs. It restarts at {time}.
> - Want to deploy something to production? Contact the platform team for review.
> - Don't share your workspace URL — it's your personal environment.

### 9.2 Platform Team Runbook

Generate a technical runbook for the platform team:

> # Builder Platform — Operations Runbook
>
> ## Adding a New Builder
> 1. Add the builder to `builders/builders.csv`
> 2. Run `./scripts/provision-builder.sh {name} {email} {team}`
>    OR add to `terraform.tfvars` and run `terraform apply`
> 3. Share the workspace URL + onboarding guide with the builder
>
> ## Removing a Builder
> 1. Delete the builder's environment:
>    `qovery environment delete --environment "builder-{name}"`
> 2. Remove the builder from the Qovery organization:
>    Console > Organization Settings > Members > Remove
>
> ## Updating the Workspace Image
> 1. Edit the Dockerfile in `dockerfiles/{chosen-option}/Dockerfile`
> 2. Commit and push to git
> 3. Redeploy the template: `qovery environment deploy --environment "builder-template"`
> 4. For existing builders: redeploy their environments to pick up the new image
>
> ## Rotating AI API Keys
> 1. Get new keys from the AI provider dashboard
> 2. Update the project-level secrets:
>    `qovery project env update --key ANTHROPIC_API_KEY --value "{new-key}" --scope PROJECT --secret`
> 3. Redeploy all builder environments to pick up the new keys
>
> ## Monitoring Costs
> - Qovery Console > Clusters > {builder-cluster} for overall cost
> - Each builder environment's cost is visible in the Console
> - Set up AWS Budgets / GCP Budgets for alerts
> - Run `qovery-optimize` skill for detailed cost analysis
>
> ## Handling Production Graduation Requests
> 1. Review the builder's code (security, quality, dependencies)
> 2. Clone to staging: `qovery environment clone --environment "builder-{name}" --name "staging-{app}"`
> 3. Test in staging
> 4. If approved, promote to production (see Phase 7B in the skill)
>
> ## Troubleshooting
> - Builder can't access workspace: check environment status in Console
> - IDE not loading: check workspace container logs
> - Database connection issues: verify env vars are set correctly
> - Deployment fails: run `qovery-troubleshoot` skill
> - Cost spike: check which environments are running, stop unused ones

---

## Next Step: Self-Service Portal (Optional)

Want to give builders a web interface to create and manage their own environments without any technical knowledge?

Say **"Set up a builder portal"** or run `/qovery-builder-portal` to generate and deploy a self-service web portal. The portal provides:
- **SSO login** with company credentials (Google Workspace, Okta, Azure AD)
- **One-click environment creation** from templates configured by the platform team
- **Dashboard** with environment status, service URLs, and TTL countdown
- **Start / Stop / Extend / Delete** controls — no Qovery knowledge needed
- **Multi-template support** — offer different workspace types per team (Sales Tools, Data Analytics, etc.)

The portal is a Vite + TypeScript + React application deployed on Qovery itself. It reads the `builder-platform-config.yaml` generated by this skill and calls the Qovery API behind the scenes.

---

## Quick Reference

### CLI Commands

```bash
# Project management
qovery project create --name "builder-workspaces"

# Template management
qovery environment create --name "builder-template"
qovery environment deploy --environment "builder-template"
qovery environment stop --environment "builder-template"

# Builder provisioning
qovery environment clone --environment "builder-template" --name "builder-{name}"
qovery environment deploy --environment "builder-{name}"

# Builder management
qovery environment list                                    # List all environments
qovery environment stop --environment "builder-{name}"     # Stop a builder
qovery environment delete --environment "builder-{name}"   # Remove a builder

# Monitoring
qovery status --watch                                      # Watch deployments
qovery log --service "workspace" --follow                  # Stream workspace logs
qovery service list                                        # List services in current env

# Secrets management
qovery project env create --key ANTHROPIC_API_KEY --value "{key}" --scope PROJECT --secret
qovery project env update --key ANTHROPIC_API_KEY --value "{new-key}" --scope PROJECT --secret
```

### API Endpoints

```bash
# Base URL: https://api.qovery.com
# Auth: Authorization: Token $QOVERY_API_TOKEN

# Project
POST   /organization/{orgId}/project                # Create project
GET    /organization/{orgId}/project                 # List projects

# Environment
POST   /project/{projectId}/environment              # Create environment
POST   /environment/{envId}/clone                    # Clone environment (provision builder)
POST   /environment/{envId}/deploy                   # Deploy environment
POST   /environment/{envId}/stop                     # Stop environment
DELETE /environment/{envId}                           # Delete environment
GET    /environment/{envId}/statuses                  # All service statuses
GET    /project/{projectId}/environment               # List all environments

# Applications
POST   /environment/{envId}/application               # Create application (IDE container)
GET    /application/{appId}/link                      # Get public URLs

# Databases
POST   /environment/{envId}/database                  # Create database

# RBAC
POST   /organization/{orgId}/customRole               # Create custom role
PUT    /organization/{orgId}/customRole/{roleId}       # Configure role permissions
GET    /organization/{orgId}/customRole                # List custom roles

# Members
POST   /organization/{orgId}/inviteMember              # Invite builder
GET    /organization/{orgId}/member                    # List members
PUT    /organization/{orgId}/member                    # Change member role

# Secrets
POST   /project/{projectId}/environmentVariable        # Set project-level secret
PUT    /project/{projectId}/environmentVariable/{id}    # Update secret
```

---

## Reference Links

- **Qovery Documentation**: https://www.qovery.com/docs/getting-started/introduction
- **Qovery Console**: https://console.qovery.com
- **Qovery CLI Reference**: https://www.qovery.com/docs/cli/commands/overview
- **Qovery API Reference**: https://www.qovery.com/docs/api-reference/introduction
- **Qovery Terraform Provider**: https://registry.terraform.io/providers/Qovery/qovery/latest/docs
- **Qovery Custom Roles (RBAC)**: https://www.qovery.com/docs/using-qovery/configuration/organization/members-rbac
- **Qovery SSO/SAML**: https://www.qovery.com/docs/using-qovery/configuration/organization/authentication
- **code-server (VS Code in browser)**: https://github.com/coder/code-server
- **OpenVSCode Server**: https://github.com/gitpod-io/openvscode-server
- **ttyd (web terminal)**: https://github.com/tsl0922/ttyd
- **Qovery Deploy Skill**: https://github.com/Qovery/qovery-skills (for initial deployments)
- **Qovery Troubleshoot Skill**: https://github.com/Qovery/qovery-skills (for diagnosing failures)
- **Qovery Optimize Skill**: https://github.com/Qovery/qovery-skills (for cost optimization)
