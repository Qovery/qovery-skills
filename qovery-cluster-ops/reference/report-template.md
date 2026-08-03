# Cluster Ops Report Template

Fill during the workflow; deliver at the end. Also the right artifact to attach when escalating to Qovery support (support@qovery.com).

```markdown
# Cluster Ops Report - {cluster name}

**Cluster:** {name} ({clusterId}) - {provider} {region}, Kubernetes {version}
**Date:** {date}
**Requested by:** {user}
**Symptom / goal:** {one sentence}

## Baseline (before changes)

| Metric | Value |
|---|---|
| Node count | {n} ({types}, {zones}) |
| Node replacements last 24h | {n} |
| Pending pods | {n} |
| Avg node memory usage | {pct} |
| Karpenter pools | default (consolidate_after={v}), stable (window={days} {start} {duration}) |

## Findings

1. {finding} - evidence: {command/event output reference}
2. ...

## Changes applied

| Change | Where | Before | After |
|---|---|---|---|
| {e.g. consolidate_after} | KARPENTER feature, default_override | 30s | 10m |

Applied via {Console / PUT + cluster deploy / Terraform}, cluster update completed at {time}.

## Verification

- {metric} re-measured over {window}: {before} → {after}

## Not changed (handoffs)

- {e.g. over-requested CPU on service X → qovery-optimize}
- {e.g. missing PDB on service Y → application change}

## Open questions for Qovery support (if escalating)

- {question + the evidence that motivates it}
```

Keep raw command outputs referenced in Findings available (paste the relevant excerpts below the report or in an appendix section) so support can verify without re-running everything.
