---
name: qovery-onboard
description: Guided onboarding for new Qovery users. Acts as a personal cloud architect — collects the user's role, experience level, industry, compliance needs, and constraints, then recommends and sets up the optimal Qovery configuration. Handles cloud provider selection, cluster creation (managed or BYOK), project/environment structure, security defaults, cost defaults, team invitations, and migration from other platforms (Heroku, Vercel, Render). Use when a user is new to Qovery or wants to set up the platform from scratch.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: onboarding
---

# Qovery Onboard Skill

This skill guides new Qovery users through a complete, best-practice setup — without requiring any Kubernetes knowledge.

The skill is opinionated: it does NOT dump configuration options on the user. It UNDERSTANDS the user's context and MAKES DECISIONS for them, with smart defaults that encode security, cost, and operational best practices. The user can override anything, but the defaults are excellent by design.

## Usage Tracking

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
QOVERY_SKILLS_UA="QoverySkill/qovery-onboard (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)"
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  QOVERY_ORG_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" -H "User-Agent: $QOVERY_SKILLS_UA" \
    "https://api.qovery.com/organization" | jq -r '.results[0].id // empty' 2>/dev/null)
  [ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
    -H "Authorization: Token $QOVERY_API_TOKEN" -H "Content-Type: application/json" -H "User-Agent: $QOVERY_SKILLS_UA" \
    -d '{"skill_name":"qovery-onboard"}' > /dev/null 2>&1 || true
elif command -v qovery >/dev/null 2>&1 && qovery auth token --print >/dev/null 2>&1; then
  QOVERY_ORG_ID=$(curl -s -H "Authorization: Bearer $(qovery auth token --print)" -H "User-Agent: $QOVERY_SKILLS_UA" \
    "https://api.qovery.com/organization" | jq -r '.results[0].id // empty' 2>/dev/null)
  [ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
    -H "Authorization: Bearer $(qovery auth token --print)" -H "Content-Type: application/json" -H "User-Agent: $QOVERY_SKILLS_UA" \
    -d '{"skill_name":"qovery-onboard"}' > /dev/null 2>&1 || true
fi
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

## When to Use This Skill

Trigger phrases:
- "I'm new to Qovery, help me get started"
- "Set up Qovery for my organization"
- "I want to use Qovery but I don't know where to start"
- "Help me onboard onto Qovery"
- "Configure Qovery for my company"
- "I have an existing Kubernetes cluster, can I use Qovery?" (BYOK)
- "Migrate me from Heroku / Vercel / Render"
- `/qovery-onboard` (slash command)

## Workflow checklist

```
Onboarding Progress:
- [ ] Phase 1 — Understand the user (role, experience, industry, constraints)
- [ ] Phase 2 — Recommend the right setup (cloud, cluster, env structure, security, cost, RBAC)
- [ ] Phase 3 — Execute the setup (account, credentials, cluster, projects, deployment rules)
- [ ] Phase 4 — BYOK path (only if the user is bringing an existing cluster)
- [ ] Phase 5 — Migration guide (only if migrating from Heroku/Vercel/Render/manual K8s)
- [ ] Phase 6 — Verification & next steps
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-understand-user.md](reference/phase1-understand-user.md) | Role, experience, industry, compliance, constraints questions |
| Phase 2 | [reference/phase2-recommend-setup.md](reference/phase2-recommend-setup.md) | Cloud / cluster / env / security / cost / RBAC recommendations |
| Phase 3 | [reference/phase3-execute-setup.md](reference/phase3-execute-setup.md) | Account, credentials, cluster, projects, deployment rules, git provider |
| Phase 4 | [reference/phase4-byok.md](reference/phase4-byok.md) | `qovery cluster install` for existing K8s clusters |
| Phase 5 | [reference/phase5-migration-guides.md](reference/phase5-migration-guides.md) | Heroku, Vercel, Render, manual K8s migrations + concept mapping |
| Phase 6 | [reference/phase6-verification.md](reference/phase6-verification.md) | Sanity checks, first deployment hand-off, support paths |

After onboarding, hand off to `qovery-deploy` for the first application deployment.

## Quick reference

### MCP queries

```
"Show me all environments"
"Show me all clusters"
"What projects do I have?"
"Is everything healthy?"
"Show me all services"
```

### CLI commands

```bash
qovery auth                       # Authenticate
qovery cluster list               # List clusters
qovery cluster install            # BYOK installation
qovery context set                # Set org/project/environment
qovery project list               # List projects
qovery environment list           # List environments
qovery service list               # List services
qovery env import                 # Import .env file
qovery env parse --heroku-json    # Parse Heroku config vars
```

### API endpoints

```
# Base URL: https://api.qovery.com   Auth: Authorization: Token $QOVERY_API_TOKEN

GET  /organization                                    List organizations

POST /organization/{orgId}/aws/credentials            Add AWS credentials
POST /organization/{orgId}/gcp/credentials            Add GCP credentials
POST /organization/{orgId}/azure/credentials          Add Azure credentials
POST /organization/{orgId}/scaleway/credentials       Add Scaleway credentials

POST /organization/{orgId}/cluster                    Create cluster
POST /cluster/{clusterId}/deploy                      Deploy (install) cluster
GET  /organization/{orgId}/cluster                    List clusters

POST /organization/{orgId}/project                    Create project
POST /project/{projId}/environment                    Create environment

POST /organization/{orgId}/member/invite              Invite member
GET  /organization/{orgId}/member                     List members

GET  /organization/{orgId}/gitProvider                List connected git providers
```

## Reference links

- **Qovery Getting Started**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **BYOK Installation**: <https://www.qovery.com/docs/getting-started/installation/kubernetes>
- **Members & RBAC**: <https://www.qovery.com/docs/configuration/organization/members-rbac>
- **Deployment Rules**: <https://www.qovery.com/docs/configuration/deployment-rule>
- **Heroku Migration Guide**: <https://www.qovery.com/docs/getting-started/guides/use-cases/cloud-migration-and-scaling>
- **CLI Reference**: <https://www.qovery.com/docs/cli/commands/overview>
- **API Reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Optimize Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Speedup Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Support**: <support@qovery.com>
- **Community Forum**: <https://discuss.qovery.com>
