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

