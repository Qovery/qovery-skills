# Phase 1: Context & Access

## 1.1 Triage the goal

Ask (or infer from the request) which path applies:

| User says | Path |
|---|---|
| "Nodes keep getting replaced", "pods restart with no crash", "Karpenter kills my pods" | Churn diagnosis → Phases 2, 3, then 4/5 for the fix |
| "Pods stuck in Pending", "deployment waits forever for a node" | Scheduling diagnosis → Phases 2, 3 |
| "Configure node pools", "restrict instance types", "enable spot", "consolidation schedule" | Configuration → Phases 2, 4 |
| "Cluster never scales down", "too many nodes for the load" | Consolidation diagnosis → Phases 2, 3, 4 |
| "Kubernetes upgrade", "version EOL", "when do I get 1.xx?" | Upgrades → Phase 6 |
| "Is my cluster resilient?", "what happens when a node dies?" | Resilience review → Phases 2, 5 |

If the actual problem is a failing deployment or a crashing app, hand off to `qovery-troubleshoot`. If the goal is lowering the bill through app resources, hand off to `qovery-optimize`.

## 1.2 Identify organization and cluster

If the user pasted a Console URL, extract the IDs (see the console-url-detection reference). Otherwise:

```bash
qovery cluster list
```

Or via API:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{organizationId}/cluster" | \
  jq '.results[] | {id, name, cloud_provider, region, status, kubernetes_version: .version}'
```

Record: `organizationId`, `clusterId`, cloud provider, region, current status.

## 1.3 Check the provider and the Karpenter feature

Karpenter node pool tuning (Phase 4) only exists on **AWS EKS clusters with the KARPENTER feature enabled**. Check:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{organizationId}/cluster/{clusterId}" | \
  jq '.features[] | select(.id == "KARPENTER")'
```

- Feature present → full workflow available.
- AWS without Karpenter (legacy node groups) → Phases 2, 3, 5, 6 apply; node sizing is controlled by `min_running_nodes` / `max_running_nodes` / `instance_type` on the cluster object instead.
- GCP / Azure / Scaleway → node autoscaling is provider-managed. Phases 2, 3 (scheduling parts), 5, and 6 apply.

## 1.4 Get kubectl access

Live node inspection needs a kubeconfig:

```bash
qovery cluster kubeconfig --cluster-id {clusterId}
```

IMPORTANT: this writes the kubeconfig file into the **current working directory**. Run it from a scratch directory, then:

```bash
export KUBECONFIG="$PWD/kubeconfig-{clusterId}.yaml"   # use the actual filename printed by the CLI
kubectl get nodes
```

If the user cannot access the cluster directly (restricted network, no kubectl), fall back to:
- `GET /cluster/{clusterId}/metrics` for utilization
- `GET /organization/{organizationId}/cluster/{clusterId}/logs` for infrastructure logs
- `qovery cluster debug-pod` for an in-cluster shell

## 1.5 Capture the baseline

Before changing anything, note in the working report (Phase 7 template):
- Cluster status and Kubernetes version
- Node count right now
- The user's symptom in one sentence and when it started
