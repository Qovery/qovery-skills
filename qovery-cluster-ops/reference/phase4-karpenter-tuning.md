# Phase 4: Karpenter Node Pool Tuning

Applies to AWS EKS clusters with the KARPENTER feature. All changes go through the Qovery cluster configuration (Console or API), never by editing Karpenter CRDs directly on the cluster: direct edits are overwritten on the next cluster update.

## 4.1 The Qovery node pool model

Qovery provisions Karpenter with managed node pools:

| Pool | Purpose | Consolidation behavior |
|---|---|---|
| `default` | Regular workloads | Continuous, after `consolidate_after` |
| `stable` | Workloads that must not be disrupted (single replica, stateful, databases in container mode) | Only inside an explicit scheduled window |
| `gpu` (optional) | GPU workloads | Own requirements/limits |
| cronjob override (optional) | Batch/cron workloads | Own limits/consolidate_after |

The configuration lives in the cluster's KARPENTER feature (`ClusterFeatureKarpenterParameters`):

```json
{
  "spot_enabled": true,
  "disk_size_in_gib": 50,
  "disk_iops": 3000,
  "disk_throughput": 125,
  "default_service_architecture": "AMD64",
  "qovery_node_pools": {
    "requirements": [
      { "key": "InstanceFamily", "operator": "In", "values": ["t3", "m5", "m6i", "c5", "r5"] },
      { "key": "InstanceSize",   "operator": "In", "values": ["large", "xlarge", "2xlarge"] },
      { "key": "Arch",           "operator": "In", "values": ["AMD64"] }
    ],
    "default_override": {
      "consolidate_after": "10m",
      "limits": { "enabled": true, "max_cpu_in_vcpu": 200, "max_memory_in_gibibytes": 400, "max_gpu": 0 }
    },
    "stable_override": {
      "consolidation": {
        "enabled": true,
        "days": ["SATURDAY", "SUNDAY"],
        "start_time": "PT22:00",
        "duration": "PT4H0M"
      },
      "limits": { "enabled": true, "max_cpu_in_vcpu": 100, "max_memory_in_gibibytes": 200, "max_gpu": 0 }
    }
  }
}
```

Requirement keys: `InstanceFamily`, `InstanceSize`, `Arch` (plus `SkuFamily`/`SkuVersion` on Azure). Operator: `In`. In the Console this is **Cluster Settings > Resources**.

## 4.2 Read the current configuration

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{organizationId}/cluster/{clusterId}" | \
  jq '.features[] | select(.id == "KARPENTER") | .value'
```

## 4.3 Tune consolidation

**`default` pool, `consolidate_after`** (string like `30s`, `10m`, `1h`; max `24h`): how long a node stays underutilized before Karpenter consolidates it.
- Churn complaints → raise it (e.g. `30s` → `10m` or `30m`). Cost rises slightly; stability improves.
- Cost complaints with slow scale-down → lower it, but not below the workload's natural oscillation period.

**`stable` pool, consolidation window** (`consolidation` object): `enabled`, `days` (uppercase weekday names), `start_time` (ISO-8601 `PT22:00`), `duration` (`PT4H0M`).
- Keep the window in the lowest-traffic period.
- Window too short or disabled → the stable pool accumulates underutilized nodes forever; schedule at least a weekly window.

## 4.4 Tune instance requirements

Rules of thumb:
- **Diversity beats precision.** 10-20 instance types across several families (`t3`, `m5`, `m6i`, `c5`, `r5`) gives Karpenter room to bin-pack and, with spot, lowers interruption rates.
- **Never lock a single `InstanceSize`.** One size makes consolidation nearly impossible (it cannot swap two half-empty nodes for one larger one) and is a common root cause of both churn and cost creep.
- Include at least one memory-optimized family (`r5`/`r6i`) if any workload is memory-heavy.
- `Arch` must match what services build for; mixed-arch needs both values and multi-arch images.

## 4.5 Tune limits

`limits` caps the total vCPU/memory a pool can provision. A pool at its cap silently stops creating nodes (pods stay Pending, see Phase 3.3). Size caps to roughly 2x normal peak so autoscaling headroom survives incidents, and keep them enabled as a cost backstop.

## 4.6 Spot and node disks

- `spot_enabled`: cluster-level opt-in for spot capacity. Karpenter falls back to on-demand automatically when spot is unavailable. Disable only if the whole cluster is interruption-sensitive; otherwise handle sensitive services via the stable pool (Phase 5).
- `disk_size_in_gib`, `disk_iops` (3000-16000), `disk_throughput` (125-1000 MB/s): raise when image pulls or ephemeral storage are the bottleneck (visible as `DiskPressure` or slow pulls in `qovery-speedup`).

## 4.7 Apply and verify

1. `PUT /organization/{organizationId}/cluster/{clusterId}` with the full cluster payload including the modified KARPENTER feature. Fetch the current object first and modify only the intended fields.
2. Trigger the cluster update: `POST .../cluster/{clusterId}/deploy` or `qovery cluster deploy --cluster-id {clusterId}`. Warn the user: the update is rolling and safe, but node pool requirement changes cause node replacement as Karpenter converges.
3. Watch: `qovery cluster list` until status is back to a deployed state; `kubectl describe nodepool default` to confirm the new values reached the cluster.
4. Re-measure churn with the Phase 2.5 method over the next 24-48h and compare against the baseline recorded in Phase 1.5.

Terraform-managed clusters: apply the same values in the `qovery_cluster` resource features instead of the API, otherwise the next `terraform apply` reverts the change.
