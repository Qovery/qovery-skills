# Qovery Deploy Skill

An AI agent skill that deploys any application to Kubernetes using [Qovery](https://www.qovery.com). Works with OpenCode, Claude Code, and any agent that supports the `SKILL.md` convention.

## What it does

When you tell your AI agent _"deploy my application with Qovery"_, the skill:

1. **Analyzes your codebase** — detects language, framework, ports, database needs, environment variables
2. **Creates a Dockerfile** if one is missing — production-ready templates for 12+ frameworks
3. **Asks the right questions** — dev vs production, database type, deployment method
4. **Sets up infrastructure** — cluster creation from scratch if needed (AWS, GCP, Azure, Scaleway)
5. **Deploys via CLI + API** (quick path) or **Terraform provider** (recommended for production)
6. **Provisions databases** — container mode for dev/test, managed mode (e.g. AWS RDS) for production, or Terraform services for advanced setups like RDS Aurora
7. **Sets up environment variables**, secrets, service interconnection, health checks, deployment stages
8. **Handles Helm charts, Terraform modules, lifecycle jobs, and cron jobs**
9. **Watches deployments and auto-fixes failures** — diagnoses build errors, port mismatches, health check failures, missing env vars, and OOM issues. Fixes Qovery configuration automatically; asks for permission before modifying user code

## Installation

Copy the `qovery-deploy/` folder into your project's skill directory. The folder name **must** match the skill name (`qovery-deploy`).

### OpenCode

```bash
# Per-project
mkdir -p .opencode/skills
cp -r qovery-deploy .opencode/skills/

# Global (all projects)
mkdir -p ~/.config/opencode/skills
cp -r qovery-deploy ~/.config/opencode/skills/
```

### Claude Code

```bash
# Per-project
mkdir -p .claude/skills
cp -r qovery-deploy .claude/skills/

# Global
mkdir -p ~/.claude/skills
cp -r qovery-deploy ~/.claude/skills/
```

### Generic Agents

```bash
# Per-project
mkdir -p .agents/skills
cp -r qovery-deploy .agents/skills/

# Global
mkdir -p ~/.agents/skills
cp -r qovery-deploy ~/.agents/skills/
```

### Verify

After installing, check that the file exists at one of these paths:

```
.opencode/skills/qovery-deploy/SKILL.md
.claude/skills/qovery-deploy/SKILL.md
.agents/skills/qovery-deploy/SKILL.md
```

The agent will automatically discover it and list `qovery-deploy` as an available skill.

## Usage

Just ask your AI agent:

```
Can you deploy my application with Qovery?
```

The skill guides the agent through the entire process — from analyzing your project to a running deployment. It will ask you questions along the way (Qovery account, database needs, dev vs production, etc.).

Other prompts that trigger the skill:

- _"Set up Qovery for my project"_
- _"Deploy this to Kubernetes with Qovery"_
- _"Create a Qovery Terraform configuration for my app"_

## Prerequisites

Before deploying, you need:

1. **A Qovery account** — sign up at [console.qovery.com](https://console.qovery.com)
2. **A Qovery API token** — generate at Organization Settings > API Tokens
3. **A Kubernetes cluster** — AWS EKS, GCP GKE, Azure AKS, or Scaleway Kapsule
4. **A git repository** connected to Qovery (GitHub, GitLab, or Bitbucket)

**New account?** The skill handles cluster creation from scratch — including cloud provider credential setup (AWS CloudFormation, GCP Cloud Shell, Azure Cloud Shell), cluster provisioning via the Qovery Console, API, or Terraform, and waiting for the cluster to be ready. It supports all four cloud providers.

## Supported Frameworks

The skill includes production-ready Dockerfile templates for:

| Language | Frameworks |
|----------|-----------|
| **Node.js** | Express, Fastify, NestJS |
| **Next.js** | SSR with standalone output |
| **React / Vite** | SPA served via nginx |
| **Python** | Flask, Django, FastAPI |
| **Go** | Any (net/http, Gin, Echo, Fiber, etc.) |
| **Java** | Spring Boot (Maven & Gradle) |
| **Ruby** | Rails |
| **PHP** | Laravel |
| **.NET** | ASP.NET Core |

If your framework is not listed, the agent will create a custom Dockerfile based on your project structure.

## What the Skill Covers

| Phase | Description |
|-------|-------------|
| **1. Discovery** | Asks questions to understand your project and deployment needs |
| **2. Prerequisites** | CLI install, authentication, Terraform setup |
| **2B. Cluster Setup** | Cloud provider credentials + cluster creation (AWS/GCP/Azure/Scaleway) — skipped if a cluster already exists |
| **3. Dockerfile** | Creates missing Dockerfiles and `.dockerignore` files |
| **4. CLI + API** | Quick deployment path using `qovery` CLI and `curl` API calls |
| **5. Terraform** | Production path with complete `.tf` manifests (applications, databases, Helm, jobs, terraform services, deployment stages) |
| **6. Environment Variables** | Auto-generated DB vars, aliases, interpolation, scopes |
| **7. Full-Stack Example** | Copy-pasteable `qovery.tf` for a typical frontend + backend + database stack |
| **8. Advanced** | Custom domains, autoscaling, storage, Terraform exporter, monorepos |
| **9. Deployment Watch** | Active deployment monitoring, log fetching, success verification |
| **10. Auto-Fix** | Error classification, automatic Qovery config fixes, user-code changes only with permission |

## Deployment Methods

The skill supports two deployment paths — the user chooses which one:

### CLI + API (Quick Start)
Best for development and staging. Uses the Qovery CLI for monitoring and the REST API (`https://api.qovery.com`) for creating resources. Fast to set up, no files to commit.

### Terraform Provider (Recommended for Production)
Creates a `qovery.tf` file that defines your entire infrastructure as code. Reproducible, version-controlled, CI/CD-friendly. Uses the [Qovery Terraform Provider](https://registry.terraform.io/providers/Qovery/qovery/latest/docs) (`qovery/qovery` v0.54+).

## Links

- [Qovery Documentation](https://www.qovery.com/docs/getting-started/introduction)
- [Qovery Console](https://console.qovery.com)
- [Qovery CLI Reference](https://www.qovery.com/docs/cli/commands/overview)
- [Qovery API Reference](https://www.qovery.com/docs/api-reference/introduction)
- [Qovery Terraform Provider](https://registry.terraform.io/providers/Qovery/qovery/latest/docs)
- [Real-World Example (Doktolib)](https://github.com/evoxmusic/Doktolib/blob/main/qovery.tf)
- [OpenCode Skills Documentation](https://opencode.ai/docs/skills/)

## License

MIT
