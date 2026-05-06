## PHASE 5: Qovery Support Escalation

If the bottleneck is on Qovery's infrastructure side, generate a diagnostic report and offer to share with support.

### 5.1 When to Escalate

Escalate to Qovery support when:
- **Queue time >2 min** consistently
- **Build runner CPU at 100%** — needs larger build runner allocation
- **Build runner memory near limit** — risk of OOM during build
- **Image push takes >2 min** with a reasonably-sized image (<500MB)
- **Pod scheduling >2 min** consistently even with right-sized resource requests
- **Karpenter not provisioning nodes** in a timely manner

### 5.2 Generate Diagnostic Report

Save to `.qovery/reports/YYYY-MM-DD-deployment-speed.md`:

```markdown
# Deployment Speed Diagnostic Report

**Date:** YYYY-MM-DD
**Service:** {name}
**Environment:** {name}
**Cluster:** {name} ({cloud_provider}, {region})

