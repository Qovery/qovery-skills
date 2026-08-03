---
description: Diagnose and tune Qovery cluster infrastructure (nodes, Karpenter, upgrades)
---

Operate the infrastructure layer of a Qovery cluster: diagnose node churn or pending pods, tune Karpenter node pools, review disruption resilience, or prepare a Kubernetes upgrade.

If arguments are provided, use them as context:
- `$ARGUMENTS` - cluster name, Qovery Console URL, or a symptom description

Follow the qovery-cluster-ops skill: identify the cluster and goal, inspect nodes and Karpenter state, run the matching diagnosis playbook, and apply configuration changes through the Qovery API followed by a cluster update.

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Git remote: !`git remote get-url origin 2>/dev/null || echo "unknown"`
