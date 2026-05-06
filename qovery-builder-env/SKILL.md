---
name: qovery-builder-env
description: Sets up self-service builder environments for non-tech teams. Creates controlled remote dev environments with AI coding tools (OpenCode, Claude Code, VS Code + Copilot, Lovable-like) pre-installed, Qovery deployment built-in, and platform-team guardrails (RBAC, cost controls, audit trails, SSO). Use when a platform engineer needs to enable sales, finance, marketing, or operations teams to build and deploy internal tools safely on Kubernetes via Qovery.
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: builder-environments
---

# Qovery Builder Environment Skill

This skill sets up self-service builder platforms on Kubernetes via Qovery for non-tech teams (sales, finance, operations, marketing). It collects platform requirements, builds environment templates with AI coding tools, configures RBAC and cost controls, provisions individual builder workspaces, and can generate Terraform manifests for the whole setup.

## When to Use This Skill

Trigger phrases:
- "Set up builder environments for non-tech teams"
- "Create remote dev environments for our sales/finance team"
- "Give non-tech employees the ability to build and deploy apps"
- "Set up a self-service platform for internal tool builders"
- "How do I enable our All Builders initiative with Qovery?"
- "Create a controlled environment where business teams can vibe-code"
- "Set up Lovable / Cursor / Claude Code environments managed by Qovery"
- `/qovery-builder-env` (slash command)

After running this skill, the platform engineer can optionally run `qovery-builder-portal` to generate a self-service web UI on top.

## Workflow checklist

```
Builder Platform Progress:
- [ ] Phase 1 — Understand the builder use case (audience, AI tools, RBAC scope)
- [ ] Phase 2 — Set up platform foundation (project, RBAC role, SSO)
- [ ] Phase 3 — Create the builder environment template (IDE container + DB + sample app)
- [ ] Phase 4 — Provision per-builder environments (clone blueprint, invite users)
- [ ] Phase 5 — Apply cost controls (TTL stop/delete jobs, resource limits, alerts)
- [ ] Phase 6 — Deployment plan summary + USER CONFIRMATION
- [ ] Phase 7 — Execute and verify
- [ ] Phase 7B — Optional: production graduation review process
- [ ] Phase 8 — Save platform config to git (shell scripts or Terraform)
- [ ] Phase 9 — Generate builder onboarding + platform team runbook
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-requirements.md](reference/phase1-requirements.md) | Audience, tools, RBAC, branding questions |
| Phase 2 | [reference/phase2-foundation.md](reference/phase2-foundation.md) | Project, custom RBAC role, SSO config |
| Phase 3 | [reference/phase3-template.md](reference/phase3-template.md) | Blueprint env, IDE container Dockerfile, AI keys, sample app |
| Phase 4 | [reference/phase4-provision.md](reference/phase4-provision.md) | Per-builder cloning, invites, provisioning script |
| Phase 5 | [reference/phase5-lifecycle.md](reference/phase5-lifecycle.md) | TTL stop/delete jobs, business hours schedule, resource limits, alerts |
| Phase 6 | [reference/phase6-deployment-plan.md](reference/phase6-deployment-plan.md) | Plan summary template + confirmation gate |
| Phase 7 | [reference/phase7-execute.md](reference/phase7-execute.md) | Final execution order |
| Phase 7B | [reference/phase7b-production.md](reference/phase7b-production.md) | Promotion review for builder apps that go to prod |
| Phase 8 | [reference/phase8-iac.md](reference/phase8-iac.md) | Config folder layout + Terraform option |
| Phase 9 | [reference/phase9-onboarding.md](reference/phase9-onboarding.md) | Builder quick-start guide + platform-team runbook |

## Code templates (copy and adapt)

```
templates/
├── dockerfiles/
│   ├── code-server.Dockerfile             # Option A: VS Code Server + Copilot
│   ├── openvscode-server.Dockerfile       # Option B: OpenVSCode Server (lighter)
│   └── terminal-only.Dockerfile           # Option C: terminal + ttyd + AI agents
├── scripts/
│   ├── provision-builder.sh               # main per-builder provisioning script
│   ├── smoke-test-workspace.sh            # validate a workspace after provisioning
│   ├── ttl-stop-job.sh                    # auto-stop expired environments
│   └── ttl-delete-job.sh                  # auto-delete long-stopped environments
└── terraform/
    ├── variables.tf
    ├── main.tf
    ├── terraform.tfvars
    └── modules/builder-env/main.tf        # per-builder module
```

The provisioning script (`templates/scripts/provision-builder.sh`) is the platform team's main tool: it clones the blueprint, sets per-builder tags, invites the user, and outputs the workspace URL. Copy it into the platform repo and adapt the env-var section at the top.

## Quick reference

### CLI commands

```bash
# Project & template
qovery project create --name "builder-workspaces"
qovery environment create --name "builder-template"
qovery environment deploy --environment "builder-template"

# Builder provisioning
qovery environment clone --environment "builder-template" --name "builder-{name}"
qovery environment deploy --environment "builder-{name}"

# Builder management
qovery environment list
qovery environment stop --environment "builder-{name}"
qovery environment delete --environment "builder-{name}"

# Monitoring
qovery status --watch
qovery log --service "workspace" --follow

# Project-level secrets (AI API keys)
qovery project env create --key ANTHROPIC_API_KEY --value "{key}" --scope PROJECT --secret
qovery project env update --key ANTHROPIC_API_KEY --value "{new-key}" --scope PROJECT --secret
```

### API endpoints

```
# Base URL: https://api.qovery.com   Auth: Authorization: Token $QOVERY_API_TOKEN

POST   /organization/{orgId}/project                  Create project
POST   /project/{projectId}/environment               Create environment
POST   /environment/{envId}/clone                     Clone environment (provision builder)
POST   /environment/{envId}/deploy                    Deploy environment
POST   /environment/{envId}/stop                      Stop environment
DELETE /environment/{envId}                           Delete environment
GET    /environment/{envId}/statuses                  All service statuses

POST   /environment/{envId}/application               Create application (IDE container)
GET    /application/{appId}/link                      Get public URLs

POST   /environment/{envId}/database                  Create database

POST   /organization/{orgId}/customRole               Create custom role
PUT    /organization/{orgId}/customRole/{roleId}      Configure role permissions

POST   /organization/{orgId}/inviteMember             Invite builder
PUT    /organization/{orgId}/member                   Change member role

POST   /project/{projectId}/environmentVariable       Set project-level secret
```

## Next step

Once builder environments are running, generate a self-service web portal on top with the **`qovery-builder-portal`** skill. The portal lets builders create their own environments through a simple UI without ever touching Qovery directly.

## Reference links

- **Qovery Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **Qovery CLI Reference**: <https://www.qovery.com/docs/cli/commands/overview>
- **Qovery API Reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **Qovery Terraform Provider**: <https://registry.terraform.io/providers/Qovery/qovery/latest/docs>
- **Qovery Custom Roles (RBAC)**: <https://www.qovery.com/docs/using-qovery/configuration/organization/members-rbac>
- **Qovery SSO / SAML**: <https://www.qovery.com/docs/using-qovery/configuration/organization/authentication>
- **code-server (VS Code in browser)**: <https://github.com/coder/code-server>
- **OpenVSCode Server**: <https://github.com/gitpod-io/openvscode-server>
- **ttyd (web terminal)**: <https://github.com/tsl0922/ttyd>
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Optimize Skill**: <https://github.com/Qovery/qovery-skills>
