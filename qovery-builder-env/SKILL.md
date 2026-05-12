---
name: qovery-builder-env
description: Set up self-service builder environments (Remote Development Environments) for non-tech and tech teams. Ships an opinionated workspace blueprint (VS Code + OpenCode + Claude Code) that works out of the box. Uses the Qovery CLI `qovery rde` commands for lifecycle management. Use when a platform engineer wants to give teams the ability to build and deploy apps on Qovery.
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: builder-environments
---

# Qovery Builder Environment Skill

Ships an opinionated, production-ready builder workspace that works out of the box. One combined container with VS Code (code-server), OpenCode, Claude Code, RTK (60-90% token savings), GitHub CLI, Qovery CLI, Node.js, Python, and Git. Non-tech builders use the VS Code UI; tech builders open the integrated terminal and run `opencode` or `claude`.

Setup takes under 5 minutes: check CLI, authenticate, pick org/cluster, optionally provide an Anthropic API key, and the skill creates a blueprint environment. Then use `qovery rde create` to provision isolated environments for each builder.

## When to Use This Skill

Trigger phrases:
- "Set up builder environments for non-tech teams"
- "Create remote dev environments for our sales/finance team"
- "Give non-tech employees the ability to build and deploy apps"
- "Set up a self-service platform for internal tool builders"
- "Create a controlled environment where business teams can vibe-code"
- "Set up remote dev environments managed by Qovery"
- `/qovery-builder-env` (slash command)

## Workflow checklist

```
Builder Environment Setup:
- [ ] Phase 1 — Setup: check CLI installed, auth, org/cluster, API key
- [ ] Phase 2 — Blueprint: generate Dockerfile + entrypoint.sh, create project + workspace via API, register blueprint, deploy, validate, stop
- [ ] Phase 3 — Provision: `qovery rde create` per builder, list, share URLs
```

## What's in the blueprint

| Service | What | Port | Notes |
|---------|------|------|-------|
| workspace | VS Code + Claude Code sidebar + OpenCode + RTK + GitHub CLI + Qovery CLI + Node.js + Python + Git + Live Preview + WELCOME.md + builder skill + startup extension | 8080 | Template: [evoxmusic/remote-dev-env-template](https://github.com/evoxmusic/remote-dev-env-template) |
| ttl-auto-shutdown | Cron job — stops env after 24h | — | `curlimages/curl:8.11.1` via Docker Hub registry |

When a builder opens the workspace URL:
- The **Claude Code sidebar** auto-opens on the left (via the builder-startup-extension)
- A **WELCOME.md** guide opens in the editor — walks non-tech users through their first build in 2 minutes
- A **CLAUDE.md** file is generated with calibrated instructions (zero-jargon for beginners, technical for devs)
- If `GIT_REPO_URL` is set, the project is auto-cloned and dependencies installed
- If a `package.json` with a `dev` script exists, a VS Code task auto-starts the dev server on port 3100
- The **Live Preview** extension shows the app inline in VS Code

Non-tech builders talk to Claude in the sidebar — they never need to touch the terminal. Tech builders open the terminal (Ctrl+\`) and run `opencode` or `claude`. RTK auto-compresses shell output to reduce LLM token costs by 60-90%.

Need a database? Builders can ask the AI tools ("I need a PostgreSQL database") and Qovery will provision one on demand. See [customization guide](reference/customization.md) to add a database to the blueprint.

A visual builder service (Lovable-like) can be added to the blueprint later — see [customization guide](reference/customization.md).

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Auth | [reference/auth.md](reference/auth.md) | Token handling + security rules |
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from Console URLs |
| Phase 1 | [reference/phase1-setup.md](reference/phase1-setup.md) | Check CLI, auth, org/cluster, API key |
| Phase 2 | [reference/phase2-blueprint.md](reference/phase2-blueprint.md) | Generate Dockerfile, create project + workspace via API, register blueprint, deploy, validate |
| Phase 3 | [reference/phase3-provision.md](reference/phase3-provision.md) | `qovery rde create` per builder, list, share URLs |
| Customize | [reference/customization.md](reference/customization.md) | TTL, resources, isolation, SSO, visual builder, Terraform, production graduation |

## Builder Workspace Template

The workspace container is defined in a public template repository:

**https://github.com/evoxmusic/remote-dev-env-template.git**

This repository contains everything the workspace needs:

| File/Directory | Purpose |
|---|---|
| `Dockerfile` | All-in-one container: code-server + Claude Code + OpenCode + RTK + GitHub CLI + Qovery CLI + Node.js + Python + Git + Live Preview |
| `entrypoint.sh` | Startup: git clone, dep install, WELCOME.md generation, CLAUDE.md generation, VS Code tasks auto-config, code-server start |
| `builder-skill/CLAUDE.md` | Instructions for Claude Code — calibrated for non-tech users (zero jargon mode, communication rules, technical defaults) |
| `builder-skill/SKILL.md` | Same instructions for OpenCode discovery |
| `builder-startup-extension/` | Custom VS Code extension: auto-opens Claude Code sidebar + WELCOME.md on workspace start |

The blueprint workspace application points directly to this repository. No need to copy or push files — the template repo is the source.

**To customize:** fork the template repo and update the blueprint's git URL. See [customization guide](reference/customization.md).

All lifecycle management (provision, list, stop, start, upgrade, delete) is handled by the `qovery rde` CLI commands.

## Defaults (customizable later)

| Setting | Default | Change via |
|---------|---------|-----------|
| Workspace CPU | 1000m (1 core) | Qovery Console or API |
| Workspace memory | 2048MB (2GB) | Qovery Console or API |
| Database | Not included (add on demand or via blueprint) | See [customization.md](reference/customization.md) |
| TTL (auto-stop) | 24 hours | Edit cron job schedule |
| Isolation | Project-per-builder (`rde-<name>`) | See [customization.md](reference/customization.md) |
| AI tools | OpenCode + Claude Code | Add API keys as project secrets |
| Visual builder | Not included (add later) | See [customization.md](reference/customization.md) |
| Preview | Live Preview extension + auto port forwarding | Built-in |

### Per-builder environment variables (optional)

Set these on each builder's Qovery environment to auto-load a project on startup:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GIT_REPO_URL` | No | — | HTTPS URL of the repo to clone (e.g., `https://github.com/org/project.git`) |
| `GIT_TOKEN` | No | — | Git personal access token (secret). Auto-detects provider (GitHub/GitLab/Bitbucket) |
| `GIT_BRANCH` | No | `main` | Branch to checkout |
| `GIT_USER_NAME` | No | — | Git author name for commits |
| `GIT_USER_EMAIL` | No | — | Git author email for commits |

If `GIT_REPO_URL` is not set, the workspace starts with an empty project directory. On container restart, the entrypoint pulls the latest changes instead of re-cloning.

## Quick reference — `qovery rde` CLI

```bash
# Prerequisite: install the Qovery CLI
curl -s https://get.qovery.com | bash
qovery rde --help    # Verify rde command is available

# Blueprint management
qovery rde blueprint register -o "org" -p "rde-blueprint"
qovery rde blueprint deploy -o "org" -p "rde-blueprint"
qovery rde blueprint stop -o "org" -p "rde-blueprint"
qovery rde blueprint status -o "org" -p "rde-blueprint"
qovery rde blueprint list -o "org"

# Create builders (one command per builder — handles project, RBAC, clone, TTL, invite, deploy)
qovery rde create -n alice -e alice@company.com -b rde-blueprint -c "cluster" -o "org"
qovery rde create -n bob -e bob@company.com -b rde-blueprint -c "cluster" -o "org"

# List and status
qovery rde list -o "org"
qovery rde list -o "org" --json
qovery rde status -n alice -o "org"
qovery rde urls -o "org"

# Lifecycle
qovery rde stop -n alice -o "org"
qovery rde stop-all -o "org"
qovery rde start -n alice -o "org"
qovery rde start-all -o "org"

# Upgrade after blueprint changes
qovery rde upgrade -o "org" -s image              # Redeploy all (fast)
qovery rde upgrade -o "org" -s reclone            # Re-clone all (clean slate)
qovery rde upgrade -n alice -o "org" -s reclone   # Re-clone one

# Delete (full cleanup: env + project + RBAC role + TTL token)
qovery rde delete -n alice -o "org"
qovery rde delete-all -o "org"

# Logs and info
qovery rde logs -n alice -o "org"
qovery rde info -o "org"
```

### API endpoints (used during blueprint creation in Phase 2)

```
POST   /organization/{orgId}/project                  Create project
POST   /project/{projectId}/environment               Create environment
POST   /environment/{envId}/application               Create workspace service
POST   /environment/{envId}/job                       Create TTL job
POST   /project/{projectId}/environmentVariable       Set project secrets (API keys)
GET    /organization/{orgId}/containerRegistry         List registries (Docker Hub ID)
GET    /application/{appId}/link                      Get workspace URL
```

## Next steps

- **Add more builders**: `qovery rde create -n name -e email -b rde-blueprint -c cluster -o org`
- **Self-service portal**: say *"Set up a builder portal"* or run `/qovery-builder-portal`
- **Add a visual builder**: see [customization guide](reference/customization.md)
- **Terraformize**: run `/qovery-terraform` (coming soon)
- **Customize**: see [customization guide](reference/customization.md)

## Reference links

- **Qovery Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **Qovery CLI**: <https://www.qovery.com/docs/cli/commands/overview>
- **Qovery API**: <https://www.qovery.com/docs/api-reference/introduction>
- **code-server**: <https://github.com/coder/code-server>
- **OpenCode**: <https://opencode.ai>
