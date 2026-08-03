# Phase 2: Inspect the Cluster

Collect facts before diagnosing. All kubectl commands assume the kubeconfig from Phase 1.

## 2.1 Node inventory and age distribution

```bash
kubectl get nodes --sort-by=.metadata.creationTimestamp \
  -o custom-columns='NAME:.metadata.name,AGE:.metadata.creationTimestamp,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,CAPACITY-TYPE:.metadata.labels.karpenter\.sh/capacity-type,NODEPOOL:.metadata.labels.karpenter\.sh/nodepool'
```

Read the age column as a churn signal:
- Most nodes younger than a few hours on a steady workload → churn is likely abnormal, go to Phase 3.1.
- A healthy steady-state cluster shows a mix of old and young nodes.

Also note: instance type diversity, zone spread (needed in Phase 5), spot vs on-demand mix (`CAPACITY-TYPE`), and which Karpenter node pool each node belongs to (typically `default` and `stable` on Qovery clusters).

## 2.2 Utilization

```bash
kubectl top nodes          # live CPU/memory usage (needs metrics-server, present on Qovery clusters)
kubectl describe nodes | grep -A6 'Allocated resources'   # requested vs allocatable
```

Distinguish the two numbers per node:
- **Requests vs allocatable**: what the scheduler and Karpenter consolidation reason about.
- **Usage (top)**: what the workloads actually consume.

High requests + low usage → over-requested apps (that fix belongs to `qovery-optimize`, note it in the report). High memory usage (>85%) across nodes → node pressure, go to Phase 3.4.

No kubectl access? Use `GET /cluster/{clusterId}/metrics` instead.

## 2.3 Karpenter state (AWS with Karpenter)

```bash
kubectl get nodepools
kubectl get nodeclaims -o wide          # one per provisioned node; STATUS + AGE
kubectl describe nodepool default       # current requirements, disruption settings, limits
kubectl describe nodepool stable
```

Check on each node pool:
- `spec.disruption.consolidateAfter` and consolidation policy
- `spec.template.spec.requirements` (instance families, sizes, arch, capacity type)
- `spec.limits` (cpu/memory caps) and current usage vs limit in `status.resources`

A node pool at its `limits` cannot provision new nodes: pods stay Pending even though Karpenter is healthy.

## 2.4 Recent disruption and scheduling events

```bash
kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'karpenter|nodeclaim|drain|evict|FailedScheduling' | tail -50
```

Classify what you see:
- `DisruptionTerminating`, `Unconsolidatable`, consolidation messages → feed Phase 3.1/3.2
- `FailedScheduling` with reasons (insufficient cpu/memory, node affinity, taints) → feed Phase 3.3
- Spot interruption / rebalance messages → feed Phase 3.5

## 2.5 Churn measurement (make it a number)

Count node creations over a window so before/after comparison is possible:

```bash
kubectl get nodeclaims -o json | jq -r '.items[].metadata.creationTimestamp' | sort | uniq -c
```

Report churn as "N node replacements in the last 24h for a steady workload of M pods". More than a handful of replacements per day without deploys or traffic changes is worth diagnosing.

## 2.6 Infrastructure logs (API view)

For events kubectl cannot show (cluster provisioning, upgrade activity):

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{organizationId}/cluster/{clusterId}/logs" | jq '.results[-20:]'
```
