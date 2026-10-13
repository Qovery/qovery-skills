---
name: qovery-speedup
description: Speeds up Qovery deployments. Analyzes deployment timelines via the V2 deployment history API, identifies bottlenecks (build, startup, health check, scheduling, image pull), classifies them as user-controllable or Qovery infrastructure, and proposes fixes — Dockerfile optimization, build cache strategies, health check tuning, deployment stage parallelism, image pull optimization. Generates a diagnostic report for Qovery support when the bottleneck is infrastructure-side. Use when the user complains about slow deployments or long build times on Qovery.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: optimization
---

# Qovery Speedup Skill

This skill speeds up Qovery deployments. It measures exactly where time is being spent, identifies the bottleneck, classifies it as user-controllable or Qovery-infrastructure, and either applies the fix or generates a diagnostic report for Qovery support.

For deployment failures use `qovery-troubleshoot`. For cost optimization use `qovery-optimize`.

## Usage Tracking

Run the lifecycle helper once at launch, before authentication:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-speedup
```

The new transport is disabled until the q-core contract is validated. It currently
returns no tracking context in normal installations; continue the skill normally.
Do not send the legacy usage event as a fallback: compatibility is pending.
For offline tests only, `--simulate /absolute/path/events.jsonl` returns a private
state-file path. Keep that path in the journey context across shell calls and
resumed steps; never retain credentials, prompts, AI responses or CLI cache data.
A new invocation uses `start`; a retry/resume uses `resume STATE_PATH` and keeps
identifiers and event timestamps. After login and explicit organization selection,
use `associate STATE_PATH`; its production authentication mapping is pending.
Already signed-in users follow the same start → associate order. Association is
not deployment success. Offline association tests use `--account-fixture` and
`--organization-fixture`; never supply real tokens or account data to those flags.
Change the association context when switching accounts or organizations; do not
reuse a previously associated identity. Clean up with `cleanup STATE_PATH` when
the journey ends or is abandoned. State expires after 24 hours on resume; remove
abandoned state paths explicitly, including after a crash. Opt-out creates no state.

> **API rule:** send this exact `User-Agent` header on **every** `curl` call to `api.qovery.com`, spelled out in full each time — a shell variable set in one command is gone by the next one:
>
> ```
> -H "User-Agent: QoverySkill/qovery-speedup (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
> ```

## When to Use This Skill

Trigger phrases:
- "My deployments are slow"
- "Speed up my Qovery deployment"
- "Why does my deployment take so long?"
- "Optimize my build time"
- "My app takes too long to start"
- "My Docker build is slow"
- "The health check keeps timing out"
- "My deployment is taking 20 minutes"
- `/qovery-speedup` (slash command)

## Workflow checklist

```
Deployment Speedup Progress:
- [ ] Phase 1 — Measure (V2 deployment history, build runner report, sub-step parsing)
- [ ] Phase 2 — Classify the bottleneck (user-controllable vs Qovery infrastructure)
- [ ] Phase 3 — Diagnose (Dockerfile, build runner, startup, health check, image pull, stages)
- [ ] Phase 4 — Apply fixes & verify
- [ ] Phase 5 — If infra-side: generate diagnostic report and escalate to Qovery support
- [ ] Phase 6 — Set ongoing speed targets and a maintenance checklist
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-measure-timeline.md](reference/phase1-measure-timeline.md) | V2 deployment history, build runner usage report, log parsing, comparison |
| Phase 2 | [reference/phase2-classify.md](reference/phase2-classify.md) | Classification table + decision tree (user vs Qovery) |
| Phase 3 | [reference/phase3-diagnose.md](reference/phase3-diagnose.md) | Image-mirroring reuse check, Dockerfile, build runner, startup, health check, image pull, stage parallelism |
| Phase 4 | [reference/phase4-fix-verify.md](reference/phase4-fix-verify.md) | Apply changes, redeploy, re-measure — opens a PR for Dockerfile/code fixes when running unattended |
| Phase 5 | [reference/phase5-support-escalation.md](reference/phase5-support-escalation.md) | When and how to escalate to Qovery support |
| Phase 6 | [reference/phase6-targets.md](reference/phase6-targets.md) | Ongoing speed targets + monitoring checklist |
| Support escalation | [reference/diagnostic-report-template.md](reference/diagnostic-report-template.md) | Drop-in report template for Qovery support tickets |

## Quick reference

### MCP queries

```
"Show me deployment history for {environment}"
"How long did the last deployment take?"
"What services took the longest to deploy?"
"Show build logs for {service}"
"Why is my deployment slow?"
```

### API endpoints

```
# V2 Deployment History (primary — structured timing data)
GET  /environment/{envId}/deploymentHistoryV2?pageSize=5

# Build Runner Usage Report (Grafana snapshot)
POST /environment/{envId}/deploymentBuildUsageReport
     Body: {"execution_id": "...", "report_expiration_in_seconds": 86400}

# Per-service deployment history
GET  /application/{appId}/deploymentHistory
GET  /container/{containerId}/deploymentHistory
GET  /job/{jobId}/deploymentHistory
GET  /helm/{helmId}/deploymentHistory

# Service configuration (health checks, resources)
GET  /application/{appId}
PUT  /application/{appId}

# Application logs (for sub-step timing)
GET  /application/{appId}/log

# Deployment stages
GET  /environment/{envId}/deploymentStage
PUT  /application/{appId}                      # change deployment_stage_id
```

### CLI commands

```bash
qovery status                                       # current deployment status
qovery log --application "name" --since 30m        # deployment logs
qovery port-forward --service "name" --port X:X    # test startup locally
qovery service list                                # all services overview
```

## Reference links

- **Deployment History Docs**: <https://www.qovery.com/docs/configuration/deployment/history>
- **Deployment Logs Docs**: <https://www.qovery.com/docs/configuration/deployment/logs>
- **Deployment Pipeline Docs**: <https://www.qovery.com/docs/configuration/deployment/pipeline>
- **Build Optimization**: <https://www.qovery.com/docs/getting-started/guides/qovery-101/optimize>
- **Image Mirroring (rebuild vs. reuse rules)**: <https://www.qovery.com/docs/configuration/deployment/image-mirroring>
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Optimize Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Support**: <support@qovery.com>
