# Social Media Posts — Qovery Agent Skill Launch

---

## Twitter/X

### Main announcement (thread)

**Tweet 1:**
We just released the Qovery Agent Skill — deploy any application to Kubernetes by telling your AI coding agent "deploy my app with Qovery."

Works with Claude Code, Cursor, OpenCode, VS Code Copilot, Gemini CLI, and 30+ more tools.

One command to install:
curl -fsSL https://skill.qovery.com/install.sh | bash

**Tweet 2 (reply):**
What the AI agent does for you:

- Analyzes your codebase (language, framework, ports, DB needs)
- Creates a Dockerfile if you don't have one
- Provisions databases (container for dev, managed RDS for production)
- Sets up env vars, health checks, deployment stages
- Deploys via CLI+API or Terraform
- Watches for failures and auto-fixes them

**Tweet 3 (reply):**
12+ Dockerfile templates included: Node.js, Next.js, React, Vite, Python (Flask/Django/FastAPI), Go, Java (Spring Boot), Ruby (Rails), PHP (Laravel), .NET

No Kubernetes knowledge required.

Open source (MIT): https://github.com/Qovery/qovery-skills

**Tweet 4 (reply):**
This complements our MCP Server:

- Agent Skill = forward engineering (code -> deployed app)
- MCP Server = operations (manage existing infra)

Use the skill to deploy. Use MCP to manage.

Docs: https://www.qovery.com/docs/getting-started/quickstart/ai-agent

---

## LinkedIn

### Post

**Deploy to Kubernetes with a Single Prompt**

We just open-sourced the Qovery Agent Skill — an AI agent skill that teaches Claude Code, Cursor, OpenCode, VS Code Copilot, Gemini CLI, and 30+ AI coding tools how to deploy any application to Kubernetes using Qovery.

Install it with one command:
curl -fsSL https://skill.qovery.com/install.sh | bash

Then just tell your AI agent: "deploy my application with Qovery"

The agent:
1. Analyzes your codebase and detects your stack
2. Creates a production-ready Dockerfile if you don't have one
3. Asks whether this is for dev or production
4. Provisions databases (container mode for dev, managed RDS for production)
5. Sets up environment variables using aliases (no duplication)
6. Deploys via Qovery CLI + API or generates a complete Terraform manifest
7. Watches the deployment and auto-fixes configuration issues

It supports Node.js, Next.js, React, Vite, Python, Go, Java, Ruby, PHP, .NET — and if your framework isn't listed, the agent creates a custom Dockerfile.

The skill follows the Agent Skills open standard (agentskills.io), so it works with any compatible tool. One install covers them all.

This complements our Qovery MCP Server:
- Agent Skill = forward engineering (source code to running app)
- MCP Server = day-2 operations (query, troubleshoot, manage)

Open source (MIT): https://github.com/Qovery/qovery-skills
Documentation: https://www.qovery.com/docs/getting-started/quickstart/ai-agent

#kubernetes #devops #aiagent #claudecode #cursor #opencode #deployment #terraform #infraascode #opensource

---

## Reddit

### r/devops

**Title:** We open-sourced an AI agent skill that deploys any app to Kubernetes via Qovery — works with Claude Code, Cursor, OpenCode, and 30+ tools

**Body:**

We just released the Qovery Agent Skill — it teaches AI coding agents how to deploy any application to Kubernetes using Qovery.

Install:
```
curl -fsSL https://skill.qovery.com/install.sh | bash
```

Then tell your AI agent: "deploy my application with Qovery"

What it does:

- Analyzes your codebase (language, framework, ports, database needs)
- Creates a Dockerfile if missing (Node.js, Next.js, React, Vite, Python, Go, Java, Ruby, PHP, .NET)
- Asks dev vs production, picks the right database mode (container vs managed RDS)
- Sets up env vars with proper scoping, aliases, and interpolation
- Deploys via CLI + API (quick) or generates a complete Terraform manifest (production)
- Watches the deployment and auto-fixes Qovery config issues (never modifies your code without asking)

It follows the Agent Skills standard (agentskills.io), so it works with Claude Code, Cursor, OpenCode, VS Code Copilot, Gemini CLI, Roo Code, Goose, Amp, Kiro, JetBrains Junie, and 20+ more.

This is different from our MCP Server — the skill is for forward engineering (code to deployed), MCP is for managing existing infrastructure. They complement each other.

Open source (MIT): https://github.com/Qovery/qovery-skills

Docs: https://www.qovery.com/docs/getting-started/quickstart/ai-agent

Happy to answer questions.

---

### r/kubernetes

**Title:** AI agent skill that deploys apps to Kubernetes (EKS/GKE/AKS) via Qovery — open source, works with Claude Code, Cursor, and 30+ tools

**Body:**

We built an Agent Skill that teaches AI coding agents (Claude Code, Cursor, OpenCode, etc.) how to deploy applications to Kubernetes using Qovery as the deployment platform.

The agent analyzes your project, creates Dockerfiles, provisions databases, sets up health checks and env vars, configures deployment stages, and deploys — either via CLI+API or by generating a complete Terraform manifest using the Qovery Terraform provider.

It supports EKS, GKE, AKS, and Scaleway Kapsule. For new accounts, it even guides through cluster creation from scratch (including cloud provider credential setup).

The interesting part for this community: the Terraform output it generates includes deployment stages, health checks (liveness + readiness probes), autoscaling, environment variable aliases (no duplication), and proper database connection handling using aliases instead of hardcoded connection strings.

Install: `curl -fsSL https://skill.qovery.com/install.sh | bash`

GitHub: https://github.com/Qovery/qovery-skills

---

### r/ClaudeAI

**Title:** Built an Agent Skill for Claude Code that deploys any app to Kubernetes — analyzes your code, creates Dockerfiles, provisions databases, deploys and auto-fixes failures

**Body:**

I built a comprehensive Agent Skill for Claude Code (also works with Cursor, OpenCode, and 30+ tools) that handles end-to-end application deployment on Kubernetes via Qovery.

Install:
```
curl -fsSL https://skill.qovery.com/install.sh | bash
```

Then just ask: "deploy my application with Qovery"

Claude Code loads the skill automatically and walks you through:

1. Codebase analysis (detects language, framework, ports, DB needs)
2. Dockerfile creation if missing (12+ templates: Node.js, Next.js, React, Vite, Python, Go, Java, Ruby, PHP, .NET)
3. Database provisioning (container for dev, managed RDS for production)
4. Environment variables setup using aliases and interpolation
5. Deployment via CLI+API or Terraform
6. Active monitoring — if the deployment fails, it diagnoses the issue and auto-fixes Qovery configuration. It never modifies your code without asking first.

The skill is 3,300+ lines of instructions covering every deployment scenario: applications, containers, Helm charts, Terraform modules, lifecycle jobs, cron jobs, and Terraform services for cloud resources (S3, Lambda, RDS Aurora, etc.).

It follows the Agent Skills standard (agentskills.io) and works with Claude Code, Cursor, VS Code Copilot, Gemini CLI, and many more.

Open source: https://github.com/Qovery/qovery-skills

---

## Hacker News

**Title:** Show HN: Deploy any app to Kubernetes with one AI prompt (open-source Agent Skill)

**Body:**

We released an open-source Agent Skill that teaches AI coding agents (Claude Code, Cursor, OpenCode, etc.) how to deploy applications to Kubernetes using Qovery.

Install: `curl -fsSL https://skill.qovery.com/install.sh | bash`
Then ask your AI agent: "deploy my application with Qovery"

The agent analyzes your codebase, creates a Dockerfile if missing (12+ framework templates), provisions databases (container for dev, managed RDS for prod), sets up environment variables with proper scoping and aliases, and deploys via CLI+API or Terraform.

If the deployment fails, it diagnoses the issue from logs and auto-fixes configuration problems. It never modifies your code without asking.

The skill is 3,300 lines of deployment knowledge covering: applications from Git repos, pre-built container images, Helm charts, Terraform modules, lifecycle jobs, cron jobs, and cloud resources (S3, Lambda, RDS Aurora via Terraform services).

It follows the Agent Skills open standard (https://agentskills.io) — compatible with 30+ AI coding tools.

GitHub: https://github.com/Qovery/qovery-skills
Docs: https://www.qovery.com/docs/getting-started/quickstart/ai-agent
