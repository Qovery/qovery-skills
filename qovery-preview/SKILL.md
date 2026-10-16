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

At each new launch, start one anonymous run before authentication or other work,
even when the user is already signed in:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-preview
```

Retain the returned absolute **state-file path** in the journey context across
shell calls, steps and resumptions. The file holds the run/anonymous UUIDs,
original timestamp and private correlation proof; never read it into the prompt,
print its contents, or retain tokens, AI responses or CLI cache contents.
The helper requires macOS, Linux or WSL with Bash and curl. The installer supplies a verified native Rust binary;
neither Rust nor Python needs to be installed. Native Windows is unsupported.
No path is returned for opt-out, development installs, an unavailable tracking binary or an
unsupported skill: continue normally. The root router `qovery` is excluded by the
backend name contract; downstream `qovery-*` skills track their own executions.

For a retry or resumed journey, use `resume STATE_PATH` to retry the anonymous
start only, never `start` again. To retry association, call `associate` again with
the retained state path and the explicitly selected organization UUID.
After login and **explicit organization selection/creation**, run:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' associate 'STATE_PATH' --organization 'ORGANIZATION_UUID'
```

Replace those placeholders with the retained path and selected UUID. Already
signed-in users follow the same start → associate order. Do not guess the first
organization returned by an API. The helper obtains a Bearer session internally;
API/policy/machine tokens cannot associate a run with a person. Association means
identity and organization are known, not that deployment succeeded.
One run has one immutable account/organization association. On an account or
organization change, end the old journey and start a **new execution**; never
reattach the old run or change IDs to bypass a conflict.

Requests run in the background with bounded deadlines. Network failures remain
queued with backoff; `resume` retries anonymous starts, while `associate` also
rechecks the current account and selected organization before retrying association.
Keep the path on interruption. At journey completion, use `cleanup STATE_PATH`
only after queued requests are no longer needed; explicit cleanup discards pending
requests too. State is private, limited to 100 runs and pruned after 30 days on
subsequent launches. Set `QOVERY_SKILLS_NO_TRACKING=1` before any command to prevent
helper state creation and sends, including pending retries. It does not remove
User-Agent headers from other API calls or disable server audit logs.
`cleanup` still removes state.
`QOVERY_SKILLS_TRACKING_DEBUG=1` prints safe statuses without request data or secrets.
Never call the legacy tracking endpoint as a fallback.

> **API rule:** send this exact `User-Agent` header on **every** `curl` call to `api.qovery.com`, spelled out in full each time — a shell variable set in one command is gone by the next one:
>
> ```
> -H "User-Agent: QoverySkill/qovery-preview (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
> ```

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
