---
name: qovery-deploy
description: Deploys any application, database, Helm chart, or Terraform module to Kubernetes via Qovery. Analyzes the user's codebase, creates missing Dockerfiles, provisions databases (container or managed), sets up environment variables, and deploys via Qovery CLI + API or Terraform provider. Supports Node.js, Python, Go, Java, Ruby, PHP, .NET, React, Vite, Next.js and more. Use when the user asks to deploy, ship, set up, or release an application on Qovery or Kubernetes via Qovery.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: deployment
---

# Qovery Deploy Skill

This skill deploys applications to Kubernetes via Qovery. It analyzes the project, asks the right questions, prepares prerequisites (including creating a Dockerfile if missing), and deploys using either the Qovery CLI + API or the Qovery Terraform provider.

## When to Use This Skill

Trigger phrases:
- "Deploy my application with Qovery"
- "Set up Qovery for my project"
- "I want to deploy this to Kubernetes"
- "Help me deploy to the cloud with Qovery"
- "Can you create a Qovery configuration for my app?"
- `/qovery-deploy` (slash command)

For preview environments per PR use `qovery-preview`. For diagnosing failed deployments use `qovery-troubleshoot`.

---

## Workflow checklist

Copy this checklist and check off each step as it completes:

```
Deployment Progress:
- [ ] Phase 1 — Discovery & questionnaire
- [ ] Phase 2 — Prerequisites & authentication
- [ ] Phase 2B — Cluster setup (only if no cluster exists)
- [ ] Phase 3 — Codebase analysis & Dockerfile creation
- [ ] Phase 3B — Deployment plan summary + USER CONFIRMATION
- [ ] Phase 4 OR Phase 5 — Deploy (CLI+API vs Terraform)
- [ ] Phase 6 — Environment variables (scopes, aliases, interpolation)
- [ ] Phase 9 — Watch deployment to ready state
- [ ] Phase 10 — Auto-fix any failures (max 3 retries per service)
```

**Critical checkpoint:** never run Phase 4 or Phase 5 without explicit user confirmation of the Phase 3B plan.

---

## Reference materials (load on demand)

When entering each phase, read the matching reference file via the bash Read tool. Do **not** load every file upfront — only what the current phase needs.

| Phase | File | Purpose |
|---|---|---|
| Console URL Detection | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract org/project/env/service IDs from a Qovery Console URL |
| Authentication | [reference/auth.md](reference/auth.md) | API token + JWT fallback chain |
| Phase 1 | [reference/phase1-discovery.md](reference/phase1-discovery.md) | User questionnaire: account, cluster, project, services, DB, deployment method |
| Phase 2 | [reference/phase2-prereq-auth.md](reference/phase2-prereq-auth.md) | CLI install, login, context, API token |
| Phase 2B | [reference/phase2b-cluster-setup.md](reference/phase2b-cluster-setup.md) | First-time cluster on AWS / GCP / Azure / Scaleway |
| Phase 3 | [reference/phase3-dockerfiles.md](reference/phase3-dockerfiles.md) | Production Dockerfile templates for 12+ stacks |
| Phase 3B | [reference/phase3b-deployment-plan.md](reference/phase3b-deployment-plan.md) | Plan summary template + confirmation gate |
| Phase 4 | [reference/phase4-cli-api.md](reference/phase4-cli-api.md) | Deploy via CLI + API (quick path) |
| Phase 5 | [reference/phase5-terraform.md](reference/phase5-terraform.md) | Deploy via Terraform provider (production path) |
| Phase 6 | [reference/phase6-env-vars.md](reference/phase6-env-vars.md) | Variable scopes, aliases, interpolation, overrides |
| Phase 8 | [reference/phase8-advanced-patterns.md](reference/phase8-advanced-patterns.md) | Helm charts, Terraform services, lifecycle/cron jobs, monorepos |
| Phase 9 | [reference/phase9-watching.md](reference/phase9-watching.md) | Watching, verifying, fetching public URLs |
| Phase 10 | [reference/phase10-troubleshooting.md](reference/phase10-troubleshooting.md) | Auto-fix loop for deployment failures |
| Full example | [examples/fullstack.md](examples/fullstack.md) | End-to-end full-stack walkthrough |

---

## Phase 1 — Discovery (summary)

Gather four groups of information conversationally (do not dump as a wall of text):

1. **Account & infrastructure** — Qovery org (auto-list via API), cluster (must be `DEPLOYED`/`READY`), project, environment.
2. **Project analysis** — language, framework, port, public accessibility, monorepo paths.
3. **Database & services** — type, mode (`CONTAINER` for dev, `MANAGED` for prod), extra cloud resources.
4. **Deployment method** — CLI + API (quick) or Terraform (production).

Detailed questions and API calls live in [reference/phase1-discovery.md](reference/phase1-discovery.md). If the user shared a Qovery Console URL, extract the IDs first using [reference/console-url-detection.md](reference/console-url-detection.md) and skip the corresponding questions.

---

## Phase 3B — Deployment plan (must confirm)

Before any resource creation, present the full plan and **wait for explicit confirmation**:

> **Deployment Plan**
>
> Target: organization, cluster (provider/region), project, environment (mode)
> Services: name / type / source / port / public / cpu / memory
> Databases: name / type / version / mode / storage
> Stages (execution order): infra → backend → frontend
> Variables: scoped list (service / environment / project), secrets, aliases
> Files to create/modify: Dockerfiles, .dockerignore, next.config.mjs, etc.
> Warnings: missing health endpoint, container DB in prod, etc.

Full template + change-handling protocol in [reference/phase3b-deployment-plan.md](reference/phase3b-deployment-plan.md).

**CRITICAL:** Do NOT proceed to Phase 4 / Phase 5 until the user explicitly confirms.

---

## Decision tree

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

## Reference links

- **Qovery Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **CLI Reference**: <https://www.qovery.com/docs/cli/commands/overview>
- **API Reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **API Base URL**: `https://api.qovery.com`
- **API Auth Header**: `Authorization: Token YOUR_API_TOKEN`
- **Terraform Provider**: <https://registry.terraform.io/providers/Qovery/qovery/latest/docs>
- **Terraform Provider Source**: `qovery/qovery` version `~> 0.54.0`
- **Terraform Examples**: <https://github.com/Qovery/terraform-examples>
- **Real-world example (Doktolib)**: <https://github.com/evoxmusic/Doktolib/blob/main/qovery.tf>
- **OpenAPI Spec**: <https://raw.githubusercontent.com/qovery/qovery-openapi-spec/main/openapi.yaml>
- **TypeScript SDK**: <https://www.npmjs.com/package/@qovery/client>
- **Go SDK**: <https://github.com/Qovery/qovery-client-go>
