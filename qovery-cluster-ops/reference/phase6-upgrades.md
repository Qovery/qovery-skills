# Phase 6: Kubernetes Version Upgrades

## 6.1 Who upgrades what

| Cluster type | Who runs the upgrade |
|---|---|
| Qovery-managed (EKS, GKE, AKS, Kapsule) | Qovery rolls out Kubernetes upgrades progressively across clusters; the customer does not trigger them |
| Self-managed / BYOK (`qovery cluster install`) | The customer upgrades Kubernetes; Qovery components must remain compatible |

Read the current version from `GET /organization/{organizationId}/cluster/{clusterId}` (or `qovery cluster list`). For questions about upgrade timing on managed clusters, check the changelog and status page (links in SKILL.md) or ask Qovery support; do not promise dates.

## 6.2 Preparation checklist (managed clusters)

The upgrade itself is Qovery's job, but workloads decide whether it is a non-event. Before a version bump:

1. **Deprecated API usage.** Helm charts and operators the user deployed themselves (via Qovery Helm services or directly) may use APIs removed in the target version. Scan with a purpose-built tool if available in the environment (`pluto detect-helm -A`, `kubent`), otherwise review the charts' compatibility notes against the target Kubernetes version.
2. **PDB sanity.** Upgrades drain every node; an unsatisfiable PDB stalls the rollout (same check as the resilience review, Phase 5.1).
3. **Graceful shutdown.** Every node is replaced during an upgrade, so SIGTERM handling and probe correctness matter more than on a normal day.
4. **Pinned node images or versions in user tooling.** Anything that hardcodes a Kubernetes minor version (CI kubectl, client libraries with skew limits) should be checked against the target version.

## 6.3 During and after

- Watch progress: `qovery cluster list` (status) and `GET .../cluster/{clusterId}/logs`.
- Node-by-node replacement is expected; total node count temporarily rises.
- After: `kubectl get nodes` shows the new version on every node; run a smoke check on critical services; re-check for pods stuck Pending (Phase 3.3), which after upgrades usually means an unsatisfiable PDB or a taint change.

## 6.4 Self-managed clusters

For BYOK clusters, the upgrade procedure belongs to the customer's distribution. The Qovery-side steps:
1. Confirm the target version is supported by Qovery (docs/changelog, or support).
2. Upgrade the cluster with the distribution's own tooling.
3. Re-run `qovery cluster install` guidance if Qovery components need updating, and verify the cluster reports healthy in the Console afterwards.
