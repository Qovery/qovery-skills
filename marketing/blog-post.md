# Deploy to Kubernetes with a Single Prompt — Introducing the Qovery Agent Skill

*Deploy any application to Kubernetes using Claude Code, Cursor, OpenCode, or any AI coding agent. No Kubernetes knowledge required.*

---

Deploying an application to Kubernetes still involves too many steps. Even with platforms like Qovery simplifying the process, developers still need to learn the Console UI, write Dockerfiles, configure health checks, set up environment variables, provision databases, and manage deployment pipelines.

What if you could just tell your AI coding agent: **"deploy my application with Qovery"** — and it handles everything?

Today we're releasing the **Qovery Agent Skill** — an open-source skill that teaches AI coding agents how to deploy any application to Kubernetes using Qovery. It works with Claude Code, Cursor, OpenCode, VS Code Copilot, Gemini CLI, and 30+ other tools that support the [Agent Skills](https://agentskills.io) open standard.

## Install in One Command

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

Then open your AI coding tool and ask:

```
Deploy my application with Qovery
```

That's it. The agent takes over from there.

## What Happens When You Ask

The skill guides the AI agent through a complete deployment workflow. Here's what it does, step by step:

### 1. Analyzes Your Codebase

The agent looks at your project files — `package.json`, `go.mod`, `requirements.txt`, `pom.xml`, `Dockerfile`, `docker-compose.yml`, `.env` files — and determines your language, framework, ports, and dependencies. It tells you what it found and asks you to confirm.

### 2. Creates a Dockerfile (If You Don't Have One)

No Dockerfile? No problem. The skill includes production-ready, multi-stage Dockerfile templates for:

- **Node.js** (Express, Fastify, NestJS)
- **Next.js** (standalone SSR output)
- **React / Vite** (SPA served via nginx)
- **Python** (Flask, Django, FastAPI)
- **Go**
- **Java** (Spring Boot with Maven or Gradle)
- **Ruby** (Rails)
- **PHP** (Laravel)
- **.NET** (ASP.NET Core)

Each template follows best practices: multi-stage builds, non-root users, minimal final images, and proper `.dockerignore` files.

### 3. Asks the Right Questions

The agent asks you about:

- **Database needs** — PostgreSQL, MySQL, MongoDB, Redis?
- **Environment** — Development/testing or production?
- **Deployment method** — Quick (CLI + API) or production-grade (Terraform)?
- **Additional services** — S3 buckets, Redis cache, Helm charts?

Based on your answers, it chooses the right configuration. For example: dev environment gets a container-mode database (cheap, on-cluster); production gets a managed database (AWS RDS with backups and high availability).

### 4. Sets Up Everything

The agent creates all the Qovery resources needed:

- **Project and environment** (if they don't exist)
- **Application** with the right ports, health checks, and autoscaling
- **Database** in the appropriate mode
- **Environment variables** using Qovery's alias system (no duplication, stays in sync)
- **Deployment stages** (database deploys before the backend, backend before the frontend)

### 5. Deploys and Watches

The agent triggers the deployment and actively monitors it. If something fails — a build error, a port mismatch, a health check misconfiguration, an OOM kill — it diagnoses the problem and fixes it automatically.

The key rule: **Qovery configuration issues are auto-fixed. Your application code is never modified without your permission.**

## Two Deployment Paths

The skill supports two approaches — you choose which one:

### CLI + API (Quick Start)

Uses the Qovery CLI for monitoring and the REST API for creating resources. Fast to set up, no files to commit. Best for development and staging environments.

### Terraform Provider (Production)

Generates a complete `qovery.tf` file that defines your entire stack as infrastructure as code — environments, deployment stages, applications, databases, Helm charts, Terraform services, lifecycle jobs, cron jobs, environment variables with proper scoping and aliases. Reproducible, version-controlled, CI/CD-friendly.

The skill includes a complete, copy-pasteable full-stack example (frontend + backend + database) with deployment stages, health checks, autoscaling, and environment variable aliases.

## Works with 30+ AI Coding Tools

The Qovery Agent Skill follows the [Agent Skills](https://agentskills.io) open standard — the same format supported by Claude Code, Cursor, VS Code Copilot, Gemini CLI, OpenCode, Roo Code, Goose, Amp, Kiro, Junie (JetBrains), OpenHands, OpenAI Codex, and many more.

The installer places the skill in all the right directories automatically. One install command covers every compatible tool.

## How It Complements the Qovery MCP Server

If you're already using the [Qovery MCP Server](https://www.qovery.com/docs/copilot/mcp-server), the Agent Skill is a natural complement:

- **Agent Skill** = Forward engineering. Takes your source code and deploys it on Qovery. Creates Dockerfiles, provisions databases, sets up everything.
- **MCP Server** = Operations. Manages existing infrastructure. Query environments, troubleshoot deployments, monitor services.

Use the skill to deploy, then the MCP Server to manage. Both work from the same AI coding tools.

## Open Source

The skill is fully open source (MIT license) and available at [github.com/Qovery/qovery-skills](https://github.com/Qovery/qovery-skills). Contributions welcome.

## Get Started

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

Then ask your AI agent:

```
Deploy my application with Qovery
```

---

**Links:**

- [Install the skill](https://skill.qovery.com/install.sh)
- [GitHub repository](https://github.com/Qovery/qovery-skills)
- [Documentation](https://www.qovery.com/docs/getting-started/quickstart/ai-agent)
- [Agent Skills standard](https://agentskills.io)
- [Qovery MCP Server](https://www.qovery.com/docs/copilot/mcp-server)
