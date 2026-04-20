# Qovery Skills

[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-7C3AED)](https://agentskills.io)
[![Install](https://img.shields.io/badge/Install-curl_skill.qovery.com-2563EB)](https://skill.qovery.com/install.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/github/stars/Qovery/qovery-skills?style=social)](https://github.com/Qovery/qovery-skills)

AI agent skills for deploying and troubleshooting applications on Kubernetes using [Qovery](https://www.qovery.com). Compatible with **30+ AI coding tools** that support the [Agent Skills](https://agentskills.io) open standard.

| Skill | What it does |
|---|---|
| **qovery-deploy** | Deploy any application to Kubernetes — analyzes codebases, creates Dockerfiles, provisions databases, deploys via CLI+API or Terraform |
| **qovery-troubleshoot** | Diagnose and fix deployment failures, crashes, connectivity issues, performance problems — with MCP Server integration and runbook generation |
| **qovery-optimize** | Optimize costs and right-size resources — analyzes historical consumption, understands business context (seasonal, growth), estimates cloud costs, generates detailed reports with CSV export |

## Quick Install

**One command — installs both skills globally for all your projects:**

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

**Install in the current project only:**

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash -s -- --project
```

**Uninstall:**

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash -s -- --uninstall
```

That's it. The installer automatically places both skills in all the right directories so they're discovered by any compatible tool.

**Update to the latest version** — just run the install command again. It overwrites the previous versions:

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

## Compatible Tools

This skill follows the [Agent Skills](https://agentskills.io) open standard and works with:

| Tool | Status |
|------|--------|
| **Claude Code** | Supported |
| **OpenCode** | Supported |
| **Cursor** | Supported |
| **VS Code Copilot** | Supported |
| **Gemini CLI** | Supported |
| **Roo Code** | Supported |
| **Goose** | Supported |
| **Amp** | Supported |
| **Junie (JetBrains)** | Supported |
| **Kiro** | Supported |
| **OpenHands** | Supported |
| **OpenAI Codex** | Supported |
| **Mistral Vibe** | Supported |
| **TRAE** | Supported |

And any other tool that discovers skills from `.claude/skills/` or `.agents/skills/` directories.

## What it does

### qovery-deploy

When you tell your AI agent _"deploy my application with Qovery"_:

1. **Analyzes your codebase** — detects language, framework, ports, database needs, environment variables
2. **Creates a Dockerfile** if one is missing — production-ready templates for 12+ frameworks
3. **Asks the right questions** — dev vs production, database type, deployment method
4. **Sets up infrastructure** — cluster creation from scratch if needed (AWS, GCP, Azure, Scaleway)
5. **Deploys via CLI + API** (quick path) or **Terraform provider** (recommended for production)
6. **Provisions databases** — container mode for dev/test, managed mode (e.g. AWS RDS) for production, or Terraform services for advanced setups like RDS Aurora
7. **Sets up environment variables**, secrets, service interconnection, health checks, deployment stages
8. **Handles Helm charts, Terraform modules, lifecycle jobs, and cron jobs**
9. **Watches deployments and auto-fixes failures** — diagnoses build errors, port mismatches, health check failures, missing env vars, and OOM issues

### qovery-troubleshoot

When you tell your AI agent _"my Qovery deployment is failing, can you help?"_:

1. **Integrates with the Qovery MCP Server** for fast, structured diagnostics (falls back to CLI/API if MCP is not configured)
2. **Runs an 8-layer systematic diagnosis** — deployment status, build logs, runtime logs, health checks, environment variables, network/connectivity, resources/performance, cluster infrastructure
3. **Matches 20+ error patterns** — OOM kills, crash loops, connection refused, missing env vars, port mismatches, DNS failures, auth errors, database issues, and more
4. **Includes 10 pre-built playbooks** — App Won't Start, App Is Slow, Database Connection Fails, Deployment Stuck, Custom Domain Not Working, Terraform/Helm Errors, High Costs, OOM/Resource Exhaustion, Build Failing
5. **Auto-fixes Qovery configuration** (ports, health checks, memory, CPU, env vars, deployment stages) without permission; asks before modifying user code
6. **Generates runbooks** in `.qovery/runbooks/` to document what happened and how it was fixed — builds institutional knowledge over time
7. **Provides prevention recommendations** tailored to the specific issue that was fixed

### qovery-optimize

When you tell your AI agent _"optimize my Qovery costs"_:

1. **Gathers business context first** — asks about application type, traffic patterns (seasonal spikes, business-hours, steady), growth expectations, and reliability requirements before touching any metrics
2. **Analyzes historical resource consumption** — compares allocated CPU/memory vs actual peak usage over 7-day and 30-day windows, with safety buffers adjusted by environment type
3. **Analyzes 7 optimization dimensions** — service right-sizing, autoscaling, database mode, environment scheduling, cluster optimization (spot instances, instance types), build optimization, external resource costs
4. **Estimates external cloud resource costs** — calculates costs for RDS, ElastiCache, NAT Gateways, load balancers, and other infrastructure from configuration parameters and public cloud pricing, with clear methodology disclaimers
5. **Generates detailed cost reports** — markdown report with executive summary, per-cluster/environment/service breakdown, external resource estimates, and sorted recommendations with expected savings and risks. Also generates CSV for spreadsheet analysis
6. **Applies changes via the right tool** — uses Qovery API for immediate changes or generates Terraform diffs if the user manages infrastructure as code. Asks the user which tool they prefer
7. **Accounts for seasonal patterns** — never right-sizes below seasonal peaks, recommends pre-scaling before known peaks, suggests post-peak review
8. **Offers Kubecost deployment** for ongoing real-time cost visibility, and suggests sharing the report with Qovery support for professional review

## Usage

Just ask your AI agent:

```
Deploy my application with Qovery
```

```
My Qovery deployment is failing, can you help?
```

The deploy skill guides the agent through the entire deployment process. The troubleshoot skill systematically diagnoses and fixes issues.

**Prompts that trigger qovery-deploy:**
- _"Deploy my application with Qovery"_
- _"Set up Qovery for my project"_
- _"Deploy this to Kubernetes with Qovery"_
- _"Create a Qovery Terraform configuration for my app"_

**Prompts that trigger qovery-troubleshoot:**
- _"My deployment is failing"_
- _"My app is crashing on Qovery"_
- _"Why is my application not working?"_
- _"My database connection is failing"_
- _"My app is slow / out of memory"_
- _"My cluster is not responding"_

**Prompts that trigger qovery-optimize:**
- _"Optimize my Qovery costs"_
- _"My cloud bill is too high"_
- _"Right-size my applications"_
- _"Are my services over-provisioned?"_
- _"How much is my infrastructure costing me?"_
- _"Generate a cost report"_

## Prerequisites

Before deploying, you need:

1. **A Qovery account** — sign up at [console.qovery.com](https://console.qovery.com)
2. **A Qovery API token** — generate at Organization Settings > API Tokens (or let the skill generate one via the CLI)
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

## What the Skills Cover

### qovery-deploy

| Phase | Description |
|-------|-------------|
| **1. Discovery** | Asks questions to understand your project and deployment needs |
| **2. Prerequisites** | CLI install, authentication, API token generation |
| **2B. Cluster Setup** | Cloud provider credentials + cluster creation (AWS/GCP/Azure/Scaleway) — skipped if a cluster already exists |
| **3. Dockerfile** | Creates missing Dockerfiles and `.dockerignore` files |
| **4. CLI + API** | Quick deployment path using `qovery` CLI and `curl` API calls |
| **5. Terraform** | Production path with complete `.tf` manifests (applications, databases, Helm, jobs, terraform services, deployment stages) |
| **6. Environment Variables** | Scopes, aliases, interpolation, overrides — avoiding duplication |
| **7. Full-Stack Example** | Copy-pasteable `qovery.tf` for a typical frontend + backend + database stack |
| **8. Advanced** | Custom domains, autoscaling, storage, port-forwarding, Terraform exporter, monorepos |
| **9. Deployment Watch** | Active deployment monitoring, log fetching, success verification |
| **10. Auto-Fix** | Error classification, automatic Qovery config fixes, user-code changes only with permission |

### qovery-troubleshoot

| Phase | Description |
|-------|-------------|
| **1. Context Gathering** | Authenticate, list services, identify the failing service, understand the problem |
| **2. 8-Layer Diagnosis** | Systematic diagnostic workflow: deployment status, build logs, runtime logs, health checks, env vars, network, resources, cluster |
| **3. Playbooks** | 10 pre-built diagnostic sequences for common issues (crashes, slow apps, DB connection, stuck deployments, custom domains, Terraform/Helm errors, high costs, OOM, build failures) |
| **4. Fix & Redeploy** | Apply fixes (auto-fix for Qovery config, ask for user code), redeploy, and verify |
| **5. Verification** | Confirm the fix worked — check status, logs, health, and endpoints |
| **6. Runbook Generation** | Create `.qovery/runbooks/` documentation for the issue and resolution |
| **7. Prevention** | Tailored recommendations to prevent recurrence |

### qovery-optimize

| Phase | Description |
|-------|-------------|
| **1. Context & Business** | Authenticate, inventory all resources, understand business context (app type, traffic patterns, seasonal peaks, growth, reliability needs, IaC tool) |
| **2. Analysis Engine** | 7 optimization dimensions: service right-sizing, autoscaling, database mode, environment scheduling, cluster optimization, build optimization, external resource cost estimation |
| **3. Cost Report** | Detailed markdown report with executive summary, per-cluster/environment/service breakdown, external resource estimates with pricing methodology disclaimer, sorted recommendations. CSV export for spreadsheets |
| **4. Apply Changes** | User-approved changes via Qovery API (immediate) or Terraform diffs (IaC). Includes deployment rule setup for scheduling |
| **5. Ongoing Monitoring** | Kubecost deployment offer, cloud provider billing dashboard links, Qovery support review offer, report saved to `.qovery/reports/` with follow-up schedule |
| **6. Seasonal** | Specific guidance per business type: e-commerce pre-scaling, SaaS right-sizing, startup growth buffers, B2B scheduling, ML/AI GPU optimization |

## Deployment Methods

The skill supports two deployment paths — the user chooses which one:

### CLI + API (Quick Start)
Best for development and staging. Uses the Qovery CLI for monitoring and the REST API (`https://api.qovery.com`) for creating resources. Fast to set up, no files to commit.

### Terraform Provider (Recommended for Production)
Creates a `qovery.tf` file that defines your entire infrastructure as code. Reproducible, version-controlled, CI/CD-friendly. Uses the [Qovery Terraform Provider](https://registry.terraform.io/providers/Qovery/qovery/latest/docs) (`qovery/qovery` v0.54+).

## Manual Installation

If you prefer not to use the install script, copy the skill folders manually:

```bash
git clone https://github.com/Qovery/qovery-skills.git
cd qovery-skills

# Global install (pick the paths for your tools)
mkdir -p ~/.claude/skills && cp -r qovery-deploy qovery-troubleshoot qovery-optimize ~/.claude/skills/
mkdir -p ~/.config/opencode/skills && cp -r qovery-deploy qovery-troubleshoot qovery-optimize ~/.config/opencode/skills/
mkdir -p ~/.agents/skills && cp -r qovery-deploy qovery-troubleshoot qovery-optimize ~/.agents/skills/

# Or project-local install
mkdir -p .claude/skills && cp -r qovery-deploy qovery-troubleshoot qovery-optimize .claude/skills/
```

Verify the skills are discovered by checking if your tool lists `qovery-deploy`, `qovery-troubleshoot`, and `qovery-optimize` as available skills.

## Links

- [Qovery Documentation](https://www.qovery.com/docs/getting-started/introduction)
- [Qovery Console](https://console.qovery.com)
- [Qovery CLI Reference](https://www.qovery.com/docs/cli/commands/overview)
- [Qovery API Reference](https://www.qovery.com/docs/api-reference/introduction)
- [Qovery Terraform Provider](https://registry.terraform.io/providers/Qovery/qovery/latest/docs)
- [Real-World Example (Doktolib)](https://github.com/evoxmusic/Doktolib/blob/main/qovery.tf)
- [Agent Skills Standard](https://agentskills.io)

## License

MIT
