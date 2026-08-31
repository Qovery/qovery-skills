---
name: qovery-preview
description: Creates temporary preview environments from pull requests via Qovery. Detects or creates a blueprint environment, clones it for each PR, switches git branches, configures auto-shutdown, and handles cleanup. Supports full-stack and single-service previews. Use when the user asks for a PR preview, branch preview, ephemeral environment, or per-PR deployment on Qovery.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: preview-environments
---

# Qovery Preview Environment Skill

This skill creates preview environments on Kubernetes via Qovery. It detects PR/branch context, finds or creates a blueprint environment, clones it, switches branches, configures auto-shutdown, and deploys.

## Usage Tracking

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  QOVERY_AUTH_HEADER="Token $QOVERY_API_TOKEN"
elif command -v qovery >/dev/null 2>&1 && qovery auth token --print >/dev/null 2>&1; then
  QOVERY_AUTH_HEADER="Bearer $(qovery auth token --print)"
else
  QOVERY_AUTH_HEADER=""
fi
if [ -n "$QOVERY_AUTH_HEADER" ]; then
  QOVERY_ORG_ID=$(curl -s -H "Authorization: $QOVERY_AUTH_HEADER" \
    "https://api.qovery.com/organization" | jq -r '.results[0].id' 2>/dev/null)
  SKILL_NAME="qovery-preview"
  [ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
    -H "Authorization: $QOVERY_AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -H "User-Agent: QoverySkill/qovery-preview (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
    -d "{\"skill_name\":\"${SKILL_NAME}\"}" > /dev/null 2>&1 || true
fi
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

## When to Use This Skill

Trigger phrases:
- "Create a preview environment for the current branch"
- "Create a PR environment for PR-123"
- "Set up preview environments for my project"
- "Clone my environment for this feature branch"
- "I want to test my PR in isolation"
- "Preview this branch on Qovery"
- "Create a temporary environment for my feature"
- `/qovery-preview` (slash command)

## Workflow checklist

```
Preview Environment Progress:
- [ ] Phase 1 — Context gathering (auth, PR/branch detection, org/cluster, blueprint check)
- [ ] Phase 2 — Create or find a blueprint environment
- [ ] Phase 3 — Clone the blueprint into the preview environment
- [ ] Phase 4 — Configure auto-shutdown (stop / delete / recycle)
- [ ] Phase 5 — Deployment plan summary + USER CONFIRMATION
- [ ] Phase 6 — Deploy & verify
- [ ] Phase 7 — Cleanup & lifecycle management
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-context.md](reference/phase1-context.md) | Branch/PR detection, blueprint search |
| Phase 2 | [reference/phase2-blueprint.md](reference/phase2-blueprint.md) | Find a source env, clone, configure auto-preview, validate |
| Phase 3 | [reference/phase3-preview-from-blueprint.md](reference/phase3-preview-from-blueprint.md) | Per-PR clone scope (full-stack vs single-service) |
| Phase 4 | [reference/phase4-auto-shutdown.md](reference/phase4-auto-shutdown.md) | Stop / delete / recycle modes, cron jobs, tokens |
| Phase 5 | [reference/phase5-plan-summary.md](reference/phase5-plan-summary.md) | Plan template + confirmation gate |
| Phase 6 | [reference/phase6-deploy-verify.md](reference/phase6-deploy-verify.md) | Deploy, monitor, fetch URLs, smoke-test |
| Phase 7 | [reference/phase7-cleanup.md](reference/phase7-cleanup.md) | Manual cleanup commands + GitHub Action template |

## Quick reference

### CLI commands

```bash
# Blueprint management
qovery environment clone --environment "staging" --name "blueprint"
qovery environment deploy --environment "blueprint"
qovery environment stop --environment "blueprint"

# Preview environment lifecycle
qovery environment clone --environment "blueprint" --name "preview-pr-123"
qovery environment deploy --environment "preview-pr-123"
qovery environment stop --environment "preview-pr-123"
qovery environment delete --environment "preview-pr-123"

# Monitoring
qovery status --watch
qovery log --service "backend" --follow
qovery log --service "backend" --since 1h --filter "ERROR"
qovery service list
qovery environment list
```

### API endpoints

```
# Base URL: https://api.qovery.com   Auth: Authorization: Token $QOVERY_API_TOKEN

# Environment lifecycle
POST   /environment/{envId}/clone                    Clone (blueprint or preview)
POST   /environment/{envId}/deploy
POST   /environment/{envId}/stop
DELETE /environment/{envId}

# Service configuration
GET    /environment/{envId}/application              List applications
PUT    /application/{appId}                          Edit (switch branch)
GET    /application/{appId}/link                     Get public URLs

GET    /environment/{envId}/container                List containers
PUT    /container/{containerId}                      Edit (switch branch)

# Status
GET    /environment/{envId}/statuses                 All service statuses
GET    /environment/{envId}/logs                     Deployment logs v2

# Auto-shutdown jobs
POST   /environment/{envId}/job                      Create cron job
POST   /application/{jobId}/secret                   Set job secret (shutdown token)

# API tokens (for scoped tokens used by jobs)
POST   /organization/{orgId}/apiToken
GET    /organization/{orgId}/apiToken
DELETE /organization/{orgId}/apiToken/{tokenId}

# Service logs
GET    /application/{appId}/log                      last 1000 lines
GET    /container/{containerId}/log                  last 1000 lines
```

## Reference links

- **Preview Environments Guide**: <https://www.qovery.com/docs/getting-started/guides/use-cases/preview-environments>
- **Lifecycle Job Examples**: <https://github.com/qovery/lifecycle-job-examples>
- **Database Seeding Example**: <https://github.com/qovery/lifecycle-job-examples/tree/main/examples/seed-postgres-database-with-sql-script>
- **Qovery Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **CLI Reference**: <https://www.qovery.com/docs/cli/commands/overview>
- **API Reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
