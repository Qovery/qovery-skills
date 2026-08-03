---
name: qovery-cluster-ops
description: Diagnoses and tunes Qovery cluster infrastructure. Covers node churn diagnosis, pods stuck in Pending, Karpenter node pool tuning (consolidation windows, consolidate_after, instance type requirements, limits, spot, node disks), disruption resilience (PDBs, do-not-disrupt, multi-AZ spread), and Kubernetes version upgrades. Works through the Qovery API, CLI, and kubectl. Use when the user reports node churn or node-level instability, pods stuck in Pending, asks to tune Karpenter or cluster resources, or prepares a Kubernetes upgrade on Qovery. (For application right-sizing use qovery-optimize; for failing deployments use qovery-troubleshoot; for slow deployments use qovery-speedup.)
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: cluster-operations
---

# Qovery Cluster Ops Skill

This skill operates the infrastructure layer of a Qovery cluster: nodes, Karpenter node pools, disruption behavior, and Kubernetes versions. It diagnoses node-level problems (churn, pending pods, node pressure), tunes the Karpenter configuration through the Qovery API, and verifies the result on the live cluster.

Scope boundaries:
- Application-level right-sizing and cost reports: `qovery-optimize`
- A deployment that fails or an app that crashes: `qovery-troubleshoot`
- Slow builds and deployments: `qovery-speedup`

Karpenter tuning applies to AWS EKS clusters with the Karpenter feature enabled. On GCP, Azure, and Scaleway, node autoscaling is managed by the provider; only Phases 1, 2, 5, and 6 apply there.

## When to Use This Skill

Trigger phrases:
- "My nodes keep getting recreated / replaced"
- "Karpenter is killing my pods"
- "My pods restart for no reason" (when app logs show no crash)
- "Pods are stuck in Pending"
- "Consolidation is too aggressive" / "my cluster never scales down"
- "Configure the Karpenter node pools"
- "Limit the instance types on my cluster"
- "When is my Kubernetes version upgraded?"
- `/qovery-cluster-ops` (slash command)

## Workflow checklist

```
Cluster Ops Progress:
- [ ] Phase 1 - Context & access (goal, cluster ID, provider, kubeconfig)
- [ ] Phase 2 - Inspect (nodes, utilization, Karpenter node pools, events)
- [ ] Phase 3 - Diagnose (churn, blocked consolidation, pending pods, node pressure)
- [ ] Phase 4 - Tune Karpenter node pools & apply (API/Console + cluster update)
- [ ] Phase 5 - Resilience review (PDBs, do-not-disrupt, stable pool, multi-AZ)
- [ ] Phase 6 - Kubernetes upgrades (managed vs self-managed, preparation)
- [ ] Phase 7 - Report findings and verify after change
```

Not every phase runs every time. Phase 1 decides the path:
- Node churn / instability complaint → Phases 2, 3, 4, 5
- Configuration request ("set up node pools") → Phases 2, 4
- Pending pods → Phases 2, 3
- Upgrade question → Phase 6

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-context-access.md](reference/phase1-context-access.md) | Goal triage, cluster identification, kubeconfig, provider check |
| Phase 2 | [reference/phase2-inspect.md](reference/phase2-inspect.md) | Node inventory, utilization, Karpenter state, churn measurement |
| Phase 3 | [reference/phase3-diagnose.md](reference/phase3-diagnose.md) | Playbooks: churn, blocked consolidation, pending pods, node pressure, spot |
| Phase 4 | [reference/phase4-karpenter-tuning.md](reference/phase4-karpenter-tuning.md) | Karpenter feature fields, node pool model, safe changes, apply & verify |
| Phase 5 | [reference/phase5-resilience.md](reference/phase5-resilience.md) | PDBs, do-not-disrupt, stable pool placement, multi-AZ spread |
| Phase 6 | [reference/phase6-upgrades.md](reference/phase6-upgrades.md) | Kubernetes version upgrades: managed vs self-managed, prep checklist |
| Phase 7 | [reference/report-template.md](reference/report-template.md) | Cluster ops report template (findings, changes, verification) |

## Quick reference

### API endpoints

```
# Cluster configuration (features incl. Karpenter node pools)
GET  /organization/{organizationId}/cluster                       # list clusters
GET  /organization/{organizationId}/cluster/{clusterId}
PUT  /organization/{organizationId}/cluster/{clusterId}           # edit features

# Apply a configuration change (cluster update)
POST /organization/{organizationId}/cluster/{clusterId}/deploy

# Observability
GET  /organization/{organizationId}/cluster/{clusterId}/status
GET  /organization/{organizationId}/cluster/{clusterId}/logs
GET  /cluster/{clusterId}/metrics

# Access & settings
GET  /organization/{organizationId}/cluster/{clusterId}/kubeconfig
GET  /organization/{organizationId}/cluster/{clusterId}/advancedSettings
PUT  /organization/{organizationId}/cluster/{clusterId}/advancedSettings
```

### CLI commands

```bash
qovery cluster list                          # clusters + status
qovery cluster list-nodes --cluster-id <id>  # node names
qovery cluster kubeconfig --cluster-id <id>  # writes kubeconfig file into the CURRENT directory
qovery cluster deploy --cluster-id <id>      # apply pending configuration changes
qovery cluster debug-pod                     # spawn a debug pod on the cluster
```

### kubectl (after fetching the kubeconfig)

```bash
kubectl get nodes --sort-by=.metadata.creationTimestamp   # node age = churn signal
kubectl top nodes                                          # live utilization
kubectl get nodepools,nodeclaims                           # Karpenter objects (AWS)
kubectl get pods -A --field-selector status.phase=Pending  # unschedulable pods
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'karpenter|nodeclaim|evict|drain'
```

## Reference links

- **Clusters Docs**: <https://www.qovery.com/docs/getting-started/installation/kubernetes>
- **Cluster Metrics API**: <https://www.qovery.com/docs/api-reference/clusters/fetch-cluster-metrics>
- **CLI Commands**: <https://www.qovery.com/docs/cli/commands/overview>
- **Karpenter Docs (upstream)**: <https://karpenter.sh/docs/>
- **Qovery Optimize Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Troubleshoot Skill**: <https://github.com/Qovery/qovery-skills>
- **Qovery Support**: <support@qovery.com>
