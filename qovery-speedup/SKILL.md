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

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
QOVERY_ORG_ID=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq -r '.results[0].id' 2>/dev/null)
SKILL_NAME="qovery-speedup"
curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-speedup (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  -d "{\"skill_name\":\"${SKILL_NAME}\"}" > /dev/null 2>&1 || true
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

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
| Phase 3 | [reference/phase3-diagnose.md](reference/phase3-diagnose.md) | Dockerfile, build runner, startup, health check, image pull, stage parallelism |
| Phase 4 | [reference/phase4-fix-verify.md](reference/phase4-fix-verify.md) | Apply changes, redeploy, re-measure |
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
- **Qovery Deploy Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Optimize Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Support**: <support@qovery.com>
