# Qovery Skills

[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-7C3AED)](https://agentskills.io)
[![Install](https://img.shields.io/badge/Install-curl_skill.qovery.com-2563EB)](https://skill.qovery.com/install.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/github/stars/Qovery/qovery-skills?style=social)](https://github.com/Qovery/qovery-skills)

AI agent skills for deploying and troubleshooting applications on Kubernetes using [Qovery](https://www.qovery.com). Compatible with **30+ AI coding tools** that support the [Agent Skills](https://agentskills.io) open standard.

| Skill | What it does |
|---|---|
| **qovery** | Entry point — routes to the right skill based on intent, handles quick operations (list, status, stop, restart, logs, clone, scale, custom domains, deployment history). Use when mentioning Qovery generically |
| **qovery-onboard** | Guided onboarding — acts as a personal cloud architect, understands your role/experience/constraints, recommends and sets up the optimal Qovery config (cloud provider, cluster, environments, RBAC, security, cost defaults), handles BYOK and platform migrations |
| **qovery-deploy** | Deploy any application to Kubernetes — analyzes codebases, creates Dockerfiles, provisions databases, deploys via CLI+API or Terraform |
| **qovery-troubleshoot** | Diagnose and fix deployment failures, crashes, connectivity issues, performance problems — with MCP Server integration and runbook generation |
| **qovery-optimize** | Optimize costs and right-size resources — analyzes historical consumption, understands business context (seasonal, growth), estimates cloud costs, generates detailed reports with CSV export |
| **qovery-speedup** | Speed up deployments — measures pipeline timeline, identifies bottlenecks (build, startup, health check, scheduling), classifies user vs Qovery responsibility, proposes Dockerfile and config fixes |
| **qovery-preview** | Create preview environments from PRs — detects/creates blueprint environments, clones for each PR, switches branches, configures auto-shutdown (stop/delete/recycle), provides cleanup. Includes `/qovery-preview` slash command |
| **qovery-builder-env** | Set up self-service builder environments for non-tech teams (sales, finance, ops) — creates controlled workspaces with AI coding tools (VS Code + Copilot, Claude Code, OpenCode), Qovery deployment built-in, RBAC, cost controls, SSO, and optional Terraform IaC |
| **qovery-builder-portal** | Generate and deploy a self-service web portal for builders — SSO login, one-click environment creation from templates, dashboard with status/URLs/TTL, start/stop/extend/delete controls. Built with Vite + React + TanStack Router + Tailwind + Express. Deployed on Qovery |

## Quick Install

**One command — installs all eight skills globally for all your projects:**

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

That's it. The installer automatically places all eight skills (with their `reference/`, `templates/`, and `examples/` sub-directories) in all the right locations so they're discovered by any compatible tool.

**Update to the latest version** — just run the install command again. It overwrites the previous versions:

```bash
curl -fsSL https://skill.qovery.com/install.sh | bash
```

## Compatible Tools

These skills follow the [Agent Skills](https://agentskills.io) open standard and work with:

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

### qovery-onboard

When you tell your AI agent _"I'm new to Qovery, help me get started"_:

1. **Understands who you are** — asks about your role (developer, DevOps, CTO, founder, non-technical), experience level with cloud infrastructure, and whether you know what Kubernetes is
2. **Understands what you have** — existing cloud provider account, existing K8s cluster (BYOK path), applications to deploy, migration from another platform
3. **Understands what you need** — primary goal, industry compliance (HIPAA, PCI-DSS, SOC2, GDPR), constraints (region, budget, private networking), team size
4. **Recommends the optimal setup** — cloud provider + region, cluster type (managed or BYOK), environment structure (dev/staging/prod), security defaults, cost defaults, RBAC roles
5. **Executes the full setup** with Console links at every step — cloud credentials, cluster creation (with progress updates while waiting), project/environments, deployment rules, git provider connection
6. **Invites team members** with appropriate RBAC roles (Admin, DevOps, Viewer, or custom roles for enterprise)
7. **Handles BYOK** (Bring Your Own Kubernetes) — guides through `qovery cluster install` for existing clusters
8. **Handles migrations** — detailed guides for Heroku (env var import via `qovery env parse --heroku-json`, concept mapping, FAQ), Vercel/Netlify, Render/Railway, and manual Kubernetes
9. **Encodes best practices by default** — private databases, internal networking, secrets encryption, deployment stages, deployment rules for cost savings — NOT optional recommendations, but the default setup

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

### qovery-speedup

When you tell your AI agent _"my deployments are slow, can you speed them up?"_:

1. **Measures the full deployment pipeline** using the V2 deployment history API — total time, per-stage, per-service, with structured durations
2. **Breaks down sub-step timing** by parsing deployment logs: git clone, Docker build, image push, pod scheduling, app startup, health check pass
3. **Generates build runner usage reports** (Grafana snapshots showing CPU, memory, network I/O during builds) using the deployment build usage API
4. **Classifies each bottleneck as user-controllable or Qovery infrastructure** — clear ownership for every slow step
5. **Proposes Dockerfile optimizations** — layer ordering, `.dockerignore`, multi-stage builds, build cache mounts, alpine base images, dev dependency removal (10+ patterns with before/after diffs)
6. **Tunes health check configuration** — right-sizes `initial_delay_seconds`, `period_seconds`, and `failure_threshold` based on actual measured startup time
7. **Optimizes deployment stage parallelism** — identifies independent services in serial stages that can run in parallel
8. **Optimizes container image pull time** — image size reduction, layer sharing between services, registry proximity
9. **Generates diagnostic reports for Qovery support** when the bottleneck is infrastructure-side (queue time, build runner capacity, registry push, Karpenter scheduling)

## Usage

Just ask your AI agent:

```
I'm new to Qovery, help me get started
```

```
Deploy my application with Qovery
```

```
My Qovery deployment is failing, can you help?
```

The onboard skill acts as your personal cloud architect. The deploy skill handles application deployment. The troubleshoot skill diagnoses and fixes issues.

**Prompts that trigger qovery (generic entry point):**
- _"Help me with Qovery"_
- _"I want to use Qovery"_
- _"List my Qovery environments"_
- _"Stop my Qovery service"_
- _"Check status of my deployment"_
- _"Show me logs"_
- `/qovery` (slash command)

**Prompts that trigger qovery-onboard:**
- _"I'm new to Qovery, help me get started"_
- _"Set up Qovery for my organization"_
- _"Help me onboard onto Qovery"_
- _"I have an existing Kubernetes cluster, can I use Qovery?"_
- _"I'm migrating from Heroku to Qovery"_
- _"Configure Qovery for my company"_

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

**Prompts that trigger qovery-speedup:**
- _"My deployments are slow"_
- _"Speed up my Qovery deployment"_
- _"Why does my deployment take so long?"_
- _"Optimize my build time"_
- _"My Docker build is slow"_
- _"My app takes too long to start"_

**Prompts that trigger qovery-preview:**
- _"Create a preview environment for the current branch"_
- _"Create a PR environment for PR-123"_
- _"Set up preview environments for my project"_
- _"I want to test my PR in isolation"_
- _"Preview this branch on Qovery"_
- `/qovery-preview` (slash command)

**Prompts that trigger qovery-builder-env:**
- _"Set up builder environments for non-tech teams"_
- _"Create remote dev environments for our sales team"_
- _"I want to give non-tech employees the ability to build and deploy apps"_
- _"Set up a self-service platform for internal tool builders"_
- _"How do I enable our All Builders initiative with Qovery?"_
- `/qovery-builder-env` (slash command)

**Prompts that trigger qovery-builder-portal:**
- _"Set up a builder portal"_
- _"Create a self-service web portal for builders"_
- _"I want non-tech users to spin up their own environments"_
- _"Deploy the builder self-service interface"_
- `/qovery-builder-portal` (slash command)

## Slash Commands

Each skill includes a slash command for quick invocation. Type `/` followed by the command name in your AI tool's chat:

| Command | What it does | Example |
|---------|-------------|---------|
| `/qovery` | Route to the right skill or run quick operations | `/qovery` or `/qovery status` or `/qovery stop my-env` |
| `/qovery-deploy` | Deploy the current project to Kubernetes | `/qovery-deploy` or `/qovery-deploy my-app` |
| `/qovery-troubleshoot` | Diagnose and fix a failing service | `/qovery-troubleshoot` or `/qovery-troubleshoot backend` |
| `/qovery-onboard` | Start guided Qovery onboarding | `/qovery-onboard` or `/qovery-onboard migrating from Heroku` |
| `/qovery-optimize` | Analyze costs and right-size resources | `/qovery-optimize` or `/qovery-optimize production` |
| `/qovery-speedup` | Analyze and fix deployment bottlenecks | `/qovery-speedup` or `/qovery-speedup my-service` |
| `/qovery-preview` | Create a preview environment for a PR | `/qovery-preview` or `/qovery-preview PR-123` |
| `/qovery-builder-env` | Set up builder environments for non-tech teams | `/qovery-builder-env` or `/qovery-builder-env sales 5` |
| `/qovery-builder-portal` | Deploy a self-service web portal for builders | `/qovery-builder-portal` or `/qovery-builder-portal google` |

Commands are installed automatically by the install script. They accept optional arguments (service name, environment name, Console URL) and auto-detect context from your git workspace.

**Manual command installation** (if not using the install script):
```bash
mkdir -p ~/.config/opencode/commands
cp qovery-*/commands/*.md ~/.config/opencode/commands/
```

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

### qovery-onboard

| Phase | Description |
|-------|-------------|
| **1. Understand the User** | Role, experience level, K8s knowledge, existing cloud/cluster, apps to deploy, migration source, goal, compliance, constraints, team size |
| **2. Recommend Setup** | Cloud provider + region, cluster type (managed/BYOK), environment structure, security defaults (baked in), cost defaults (baked in), RBAC roles |
| **3. Execute Setup** | Cloud credentials, cluster creation (with Console links and progress), project/environments, deployment rules, git provider, team invitations |
| **4. BYOK Path** | Prerequisites check, CLI install, `qovery cluster install`, verification, seamless continuation to project setup |
| **5. Migration** | Heroku (detailed: concept mapping, Dockerfile, env var import, DB migration, FAQ), Vercel/Netlify, Render/Railway, manual K8s |
| **6. Next Steps** | Persona-adapted next steps (bootstrapper vs platform team vs enterprise), reference all other skills, enterprise recommendations (RBAC, private networking, SSO) |

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

### qovery-speedup

| Phase | Description |
|-------|-------------|
| **1. Measure** | V2 deployment history API for structured stage/service timing, build runner Grafana snapshot, deployment log parsing for sub-step timing, trend analysis across 5-10 deployments |
| **2. Classify** | Each bottleneck classified as user-controllable, Qovery infrastructure, or mixed — with clear decision tree |
| **3. Diagnose** | Deep analysis: Dockerfile optimization (10+ patterns), build runner resources, app startup, health check tuning, pod scheduling, container image pull, deployment stage parallelism |
| **4. Fix & Verify** | Apply fixes, trigger new deployment, re-measure, present before/after comparison with percentage improvement |
| **5. Qovery Support** | For infrastructure bottlenecks: generate diagnostic report with timeline, Grafana snapshot, and applied optimizations — offer to share with support |
| **6. Targets & Monitoring** | Deployment time targets by framework, benchmark report, maintenance checklist, re-analysis triggers |

### qovery-preview

| Phase | Description |
|-------|-------------|
| **1. Context** | Authenticate, detect PR/branch (git, GitHub CLI, user input), resolve org/cluster, check for existing blueprint environment |
| **2. Blueprint** | Find deployed source environment, clone to create blueprint, configure base branches + `auto_preview`, validate (deploy, health check), stop to save resources |
| **3. Clone** | Clone blueprint as preview environment with `PREVIEW` mode, switch git branches on services matching the PR's repository |
| **4. Auto-Shutdown** | Ask lifecycle strategy (auto-stop, auto-delete, recycle, manual, PR-merge), create cron job with raw Dockerfile (`curlimages/curl`) + Qovery API token, or generate CI/CD workflow |
| **5. Summary** | Present full deployment plan (org, cluster, blueprint, services, branch changes, auto-shutdown config, warnings), get explicit user confirmation |
| **6. Deploy** | Deploy preview environment, active watch loop, fetch logs on failure, verify health, present preview URLs and console link |
| **7. Cleanup** | Delete preview environment, clean up shutdown tokens, blueprint maintenance guidance, bulk cleanup for sprint resets |

### qovery-builder-env

| Phase | Description |
|-------|-------------|
| **1. Understand** | Authenticate, understand builders (who, how many, tech level, data needs), platform requirements (SSO, compliance, cloud), choose builder experience tier (visual/VS Code/terminal) |
| **2. Foundation** | Resolve org/cluster (recommend dedicated builder cluster), create builder project, set up RBAC with custom "Builder" role, configure SSO |
| **3. Template** | Design environment blueprint, build AI coding tool container (3 Dockerfiles: VS Code Server, OpenVSCode, terminal), configure AI API keys as platform secrets, create and validate template |
| **4. Provision** | Clone template per builder, invite builders with Builder role, automation script for bulk provisioning, share access URLs |
| **5. Cost Controls** | Auto-stop schedules (business hours), resource limits per builder, cost monitoring and alerts, cleanup policy for inactive environments |
| **6. Summary** | Present full platform plan (infra, RBAC, template, builders, costs, security), get explicit confirmation |
| **7. Execute** | Create project, role, secrets, template, clone per builder, deploy, invite, verify. Optional 7B: production graduation workflow |
| **8. IaC** | Generate config folder structure, save to git repo, optional Terraform manifests (Qovery provider), commit and push |
| **9. Onboarding** | Generate builder quick-start guide (non-technical) and platform team runbook (operations, adding/removing builders, key rotation, troubleshooting) |

### qovery-builder-portal

| Phase | Description |
|-------|-------------|
| **1. Requirements** | Authenticate, check for builder-platform-config.yaml (prerequisite), configure portal (SSO provider, branding, max environments, templates, TTL extension, delete permissions) |
| **2. Generate App** | Generate complete Vite + React + TanStack Router + Tailwind frontend and Express + TypeScript backend. Inline critical code (Qovery API client, provisioner, SSO auth, environment CRUD). Agent generates UI components with branding |
| **3. Configure** | Set environment variables (11 vars, 4 secrets), SSO setup guide (Google/Okta/Azure AD/OIDC), multi-template configuration |
| **4. Summary** | Present portal deployment plan, get explicit confirmation |
| **5. Deploy** | Save generated code to git, create Qovery project + application, set env vars + secrets, configure custom domain, deploy, verify SSO + environment creation flow |
| **6. Operations** | Generate operations guide: add templates, change branding, rotate credentials, monitoring, troubleshooting |

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
mkdir -p ~/.claude/skills && cp -r qovery qovery-onboard qovery-deploy qovery-troubleshoot qovery-optimize qovery-speedup qovery-preview qovery-builder-env qovery-builder-portal ~/.claude/skills/
mkdir -p ~/.config/opencode/skills && cp -r qovery qovery-onboard qovery-deploy qovery-troubleshoot qovery-optimize qovery-speedup qovery-preview qovery-builder-env qovery-builder-portal ~/.config/opencode/skills/
mkdir -p ~/.agents/skills && cp -r qovery qovery-onboard qovery-deploy qovery-troubleshoot qovery-optimize qovery-speedup qovery-preview qovery-builder-env qovery-builder-portal ~/.agents/skills/

# Install all slash commands (Claude Code, OpenCode, etc.)
mkdir -p ~/.claude/commands && cp qovery-*/commands/*.md ~/.claude/commands/
mkdir -p ~/.config/opencode/commands && cp qovery-*/commands/*.md ~/.config/opencode/commands/

# Or project-local install
mkdir -p .claude/skills && cp -r qovery qovery-onboard qovery-deploy qovery-troubleshoot qovery-optimize qovery-speedup qovery-preview qovery-builder-env qovery-builder-portal .claude/skills/
```

Verify the skills are discovered by checking if your tool lists all nine Qovery skills.

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
