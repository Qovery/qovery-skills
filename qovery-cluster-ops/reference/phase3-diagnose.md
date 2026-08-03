# Phase 3: Diagnosis Playbooks

Pick the playbook matching the Phase 2 findings. Each ends with a pointer to the fix.

## 3.1 Playbook: Node churn too high

**Symptoms:** nodes replaced many times a day, pods restarted without app crashes, monitoring/telemetry gaps, users report random disconnections.

**Checks:**
1. Which pool churns? Compare nodeclaim ages per `karpenter.sh/nodepool` label (Phase 2.1).
2. Why are nodes removed? Look for consolidation events on the terminated nodeclaims:
   ```bash
   kubectl get events -A --sort-by=.lastTimestamp | grep -iE 'consolidat|disrupt' | tail -30
   ```
3. Is the workload itself flapping? HPA scaling up/down repeatedly forces node add/remove cycles:
   ```bash
   kubectl get hpa -A
   kubectl get events -A | grep -i 'ScalingReplicaSet' | tail -20
   ```

**Root causes and fixes:**

| Cause | Evidence | Fix |
|---|---|---|
| Consolidation too aggressive on the `default` pool | Nodes killed minutes after becoming underutilized | Raise `consolidate_after` (Phase 4.3) |
| Sensitive workloads on the consolidating pool | Single-replica or stateful pods on `default` pool nodes | Move them to the `stable` pool / add do-not-disrupt (Phase 5) |
| Workload flapping (HPA min too low, spiky traffic) | Scaling events correlate with node churn | Raise HPA min replicas; smooth the workload first, then retune |
| Requirements too narrow for bin-packing | One instance size allowed, Karpenter replaces nodes to fit pods | Widen instance requirements (Phase 4.4) |
| Spot interruptions | Interruption/rebalance events, churn only on `capacity-type=spot` nodes | See 3.5 |

## 3.2 Playbook: Consolidation not happening (cluster never scales down)

**Symptoms:** node count stays high after load drops; utilization per node is low; cost creep.

**Checks:**
1. `kubectl describe nodepool default` → is consolidation configured as expected?
2. Look for `Unconsolidatable` / blocked-disruption events and read the reason:
   ```bash
   kubectl get events -A | grep -iE 'unconsolidatable|cannot disrupt|blocked' | tail -20
   ```

**Root causes:**

| Blocker | Evidence | Fix |
|---|---|---|
| PDB allows zero disruption | Event names the PDB | Fix `maxUnavailable`/`minAvailable` (Phase 5.1) |
| `karpenter.sh/do-not-disrupt` pods spread across nodes | Annotation present on pods | Confine them to the `stable` pool (Phase 5.2) |
| Pods without a controller (bare pods) | Bare pods on the node | Recreate them as Deployments/Jobs |
| Stable pool outside its consolidation window | Churn-free by design | Expected; tune the window if needed (Phase 4.3) |
| Instance requirements lock the size | Only one size allowed, so replacing 2 half-empty nodes with 1 bigger one is impossible | Widen `InstanceSize`/`InstanceFamily` requirements (Phase 4.4) |
| Over-requested apps | Requests >> usage, nodes look "full" to the scheduler | Right-size requests via `qovery-optimize`, then consolidation resumes |

## 3.3 Playbook: Pods stuck in Pending

**Symptoms:** deployments hang at scheduling, `FailedScheduling` events.

**Checks:**
```bash
kubectl get pods -A --field-selector status.phase=Pending
kubectl describe pod {pod} -n {ns}    # read the FailedScheduling message verbatim
```

**Root causes by message:**

| Message contains | Cause | Fix |
|---|---|---|
| `Insufficient cpu` / `Insufficient memory` + no new node appears | Node pool at its `limits`, or requirements match no instance type large enough | Raise pool limits or widen requirements (Phase 4.4/4.5) |
| `didn't match Pod's node affinity/selector` | Pod requires arch/labels no pool provides (e.g. ARM64 image on AMD64-only pool) | Align `default_service_architecture` / requirements with the workload |
| `untolerated taint` | GPU/dedicated pool taints | Add the toleration or target the right pool |
| Nothing happens at all, no nodeclaim created | Karpenter itself unhealthy, or subnet/IP exhaustion | Check karpenter controller logs; escalate to Qovery support with cluster logs |
| New node appears but takes 2-5 min | Normal provisioning latency | Expected on scale-up; see `qovery-speedup` if it hurts deployments |

## 3.4 Playbook: Node memory pressure

**Symptoms:** OOM kills without app memory growth, node `MemoryPressure=True`, system pods evicted.

**Checks:**
```bash
kubectl describe nodes | grep -B2 -A5 'MemoryPressure'
kubectl top nodes
```

**Root causes:** apps with memory limits far above requests (overcommit), or instance types too small for the pod mix. Fixes: align requests with real usage (`qovery-optimize`), or require larger instance sizes on the pool (Phase 4.4). Memory-saturated nodes also break consolidation: Karpenter cannot drain a node whose pods do not fit elsewhere.

## 3.5 Playbook: Spot interruptions

**Symptoms:** churn confined to `karpenter.sh/capacity-type=spot` nodes; AWS interruption notices in events.

**Assess before "fixing":** spot churn is the accepted price of the discount. Act only if the workload cannot tolerate it:
- Production, interruption-sensitive → keep those services on on-demand: the `stable` pool is on-demand; or disable `spot_enabled` on the cluster (Phase 4.6).
- Tolerant workloads → diversify instance requirements instead: more families/sizes = lower interruption probability.

## 3.6 When to escalate to Qovery support

Escalate with the Phase 7 report when the evidence points to infrastructure Qovery manages: Karpenter controller crash-looping, cluster stuck in a deployment state, subnet/IP exhaustion, control-plane errors in cluster logs. Contact: support@qovery.com or the in-Console chat.
