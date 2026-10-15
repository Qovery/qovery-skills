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

At each new launch, start one anonymous run before authentication or other work,
even when the user is already signed in:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-speedup
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
