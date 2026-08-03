# Phase 5: Resilience Review

Node disruption (consolidation, spot, upgrades) is normal on an autoscaled cluster. Resilience means workloads tolerate it. Review these four layers.

## 5.1 PodDisruptionBudgets

```bash
kubectl get pdb -A
```

Check both failure modes:
- **Missing PDB** on multi-replica production services → a drain can evict all replicas at once. Add a PDB with `maxUnavailable: 1` (or equivalent).
- **Over-strict PDB** (`maxUnavailable: 0`, or `minAvailable` equal to replica count) → blocks consolidation and Kubernetes upgrades entirely. This shows up as `Unconsolidatable` events (Phase 3.2) and stuck node drains. Relax it or scale replicas up by one.

## 5.2 Protect disruption-sensitive workloads

Two mechanisms, in order of preference on Qovery:

1. **Stable node pool placement.** Qovery schedules single-replica services and container-mode databases on the `stable` pool, which only consolidates inside its scheduled window. Verify sensitive pods actually run there:
   ```bash
   kubectl get pods -n {ns} -o wide   # then check the node's karpenter.sh/nodepool label
   ```
2. **`karpenter.sh/do-not-disrupt: "true"` pod annotation** for exceptional cases (long-running jobs that must finish). Use sparingly: every annotated pod pins its node and degrades consolidation (Phase 3.2).

## 5.3 Multi-AZ spread

```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone'
kubectl get pods -n {ns} -o wide     # map replicas to zones for critical services
```

Flags to raise:
- All nodes in one zone on a production cluster → zone outage takes everything down. Check the cluster's region/AZ configuration with Qovery support if this looks wrong.
- All replicas of a critical service on nodes in the same zone → replicas exist but share the failure domain. Kubernetes spreads by default only loosely; verify what topology spread or anti-affinity options are available for the service (service advanced settings via `GET /application/{appId}/advancedSettings`) rather than assuming.

Zonal data transfer has a cost: forcing spread on chatty internal services trades resilience for cross-AZ traffic charges. Say so when recommending it.

## 5.4 Disruption tolerance checklist

For each critical service, confirm:

- [ ] At least 2 replicas (or deliberately accepted downtime, documented)
- [ ] PDB present and satisfiable (5.1)
- [ ] Graceful shutdown: handles SIGTERM, terminates within the grace period
- [ ] Liveness/readiness probes correct, so replacements enter rotation cleanly
- [ ] Single-replica/stateful services on the stable pool (5.2)
- [ ] Not interruption-sensitive while running on spot nodes; move to on-demand/stable if it is

Findings that are application configuration (replicas, probes) belong in the report as handoffs to `qovery-deploy`/`qovery-optimize` workflows rather than cluster changes.
