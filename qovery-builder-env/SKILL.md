---
name: qovery-builder-env
description: Set up self-service builder environments for non-tech and tech teams. Ships an opinionated workspace blueprint (VS Code + OpenCode + Claude Code + PostgreSQL) that works out of the box. One Dockerfile, 2 questions, under 5 minutes to first builder environment. Customizable after setup. Use when a platform engineer wants to give teams the ability to build and deploy apps on Qovery.
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: builder-environments
---

# Qovery Builder Environment Skill

Ships an opinionated, production-ready builder workspace that works out of the box. One combined container with VS Code (code-server), OpenCode, Claude Code, RTK (60-90% token savings), GitHub CLI, Qovery CLI, Node.js, Python, and Git. Non-tech builders use the VS Code UI; tech builders open the integrated terminal and run `opencode` or `claude`.

Setup takes under 5 minutes: authenticate, pick org/cluster, optionally provide an Anthropic API key, and the skill creates a blueprint environment that gets cloned for each builder. Each builder gets their own isolated project and environment — never shared.

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
- [ ] Phase 1 — Setup: auth, org/cluster, API key (1-2 questions)
- [ ] Phase 2 — Blueprint: create project + workspace + database + TTL job, deploy, validate, stop
- [ ] Phase 3 — Provision: clone per builder, invite, share URLs, provide provisioning script
```

## What's in the blueprint

| Service | What | Port | Notes |
|---------|------|------|-------|
| workspace | VS Code (code-server) + OpenCode + Claude Code + RTK + GitHub CLI + Qovery CLI + Node.js + Python + Git | 8080 | All-in-one container — `templates/Dockerfile` |
| ttl-auto-shutdown | Cron job — stops env after 24h | — | `curlimages/curl:8.11.1` via Docker Hub registry |

Non-tech builders open the workspace URL in a browser and get VS Code. Tech builders open the integrated terminal (Ctrl+\`) and run `opencode` or `claude` for AI-powered coding. RTK auto-compresses shell output to reduce LLM token costs by 60-90%. GitHub CLI (`gh`) is pre-installed for repo operations. Git credential helper is configured — set `$GITHUB_TOKEN` to clone private repos.

Need a database? Builders can ask the AI tools ("I need a PostgreSQL database") and Qovery will provision one on demand. See [customization guide](reference/customization.md) to add a database to the blueprint if most builders need one.

A visual builder service (Lovable-like) can be added to the blueprint later — see [customization guide](reference/customization.md).

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Auth | [reference/auth.md](reference/auth.md) | Token handling + security rules |
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from Console URLs |
| Phase 1 | [reference/phase1-setup.md](reference/phase1-setup.md) | Auth, org/cluster, API key (1-2 questions) |
| Phase 2 | [reference/phase2-blueprint.md](reference/phase2-blueprint.md) | Create project, workspace, database, TTL job, deploy, validate, stop |
| Phase 3 | [reference/phase3-provision.md](reference/phase3-provision.md) | Clone per builder, RBAC role, invite, deploy, share URLs |
| Customize | [reference/customization.md](reference/customization.md) | TTL, resources, isolation, SSO, visual builder, Terraform, production graduation |

## Code templates (copy and adapt)

```
templates/
├── Dockerfile                    # Combined workspace (all-in-one)
├── entrypoint.sh                 # Startup: git clone, dep install, start code-server
├── scripts/
│   ├── provision-builder.sh      # Per-builder provisioning (clone + TTL + invite)
│   ├── smoke-test-workspace.sh   # Validate workspace after provisioning
│   ├── ttl-stop-job.sh           # Auto-stop cron job reference
│   └── ttl-delete-job.sh         # Auto-delete cron job reference
```

The provisioning script (`templates/scripts/provision-builder.sh`) is the platform team's main tool for onboarding new builders. Fill in the IDs at the top after Phase 2 (`ORG_ID`, `CLUSTER_ID`, `BLUEPRINT_ENV_ID`, `DOCKER_HUB_REGISTRY_ID`) and run `./provision-builder.sh <name> <email>`. The script is idempotent — safe to run multiple times.

## Defaults (customizable later)

| Setting | Default | Change via |
|---------|---------|-----------|
| Workspace CPU | 1000m (1 core) | Qovery Console or API |
| Workspace memory | 2048MB (2GB) | Qovery Console or API |
| Database | Not included (add on demand or via blueprint) | See [customization.md](reference/customization.md) |
| TTL (auto-stop) | 24 hours | Edit cron job schedule |
| Isolation | Project-per-builder | See [customization.md](reference/customization.md) |
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

## Quick reference

### CLI commands

```bash
# Blueprint
qovery environment deploy --environment "builder-blueprint"
qovery environment stop --environment "builder-blueprint"

# Provisioning
./provision-builder.sh alice alice@company.com

# Management
qovery environment list
qovery environment stop --environment "workspace"
qovery environment delete --environment "workspace"
qovery log --service "workspace" --follow
qovery status --watch
```

### API endpoints

```
POST   /organization/{orgId}/project                  Create project
POST   /project/{projectId}/environment               Create environment
POST   /environment/{envId}/clone                     Clone (provision builder)
POST   /environment/{envId}/deploy                    Deploy
POST   /environment/{envId}/stop                      Stop
DELETE /environment/{envId}                           Delete
GET    /environment/{envId}/statuses                  Service statuses
POST   /environment/{envId}/application               Create workspace service
POST   /environment/{envId}/job                       Create TTL job
POST   /organization/{orgId}/customRole               Create RBAC role
POST   /organization/{orgId}/inviteMember             Invite builder
GET    /application/{appId}/link                      Get workspace URL
```

## Next steps

- **Add more builders**: run `./provision-builder.sh <name> <email>`
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
