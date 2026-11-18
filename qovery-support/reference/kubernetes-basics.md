# Kubernetes on Qovery

Covers the Kubernetes behavior Qovery users run into: where pods run, why they are Pending or evicted, autoscaling with HPA and KEDA, kubectl access, namespaces and network policies, and logs, metrics and alerts. Qovery deploys services into the cluster without modifying Kubernetes itself.

## Contents

- How Qovery maps to Kubernetes
- Pods stuck in Pending
- Pods evicted or restarted without a deployment
- Autoscaling with HPA
- Autoscaling with KEDA (event-driven, scale to zero)
- kubectl, shell and debug pods
- Namespaces and network policies
- Logs: live, history and retention
- Metrics, alerts and third-party observability
- Known limits

## How Qovery maps to Kubernetes

| Qovery | Kubernetes |
|---|---|
| Cluster | An EKS, GKE, AKS or Kapsule cluster (or your own with BYOK) |
| Environment | A namespace |
| Application or container service | A workload (pods) with a Kubernetes Service, and gateway or ingress routes for public ports |
| Container database | A single pod with a persistent volume |
| Lifecycle job / cron job | A Job / CronJob |
| Helm service | A Helm release |
| Instances | Replicas; min and max with autoscaling |
| CPU / memory | Container requests and limits |

Changes made with kubectl to objects Qovery manages are overwritten at the next deployment. Make changes through Qovery (Console, CLI, API, Terraform).

## Pods stuck in Pending

**Symptom.** The deployment waits; pods are `Pending` with events like `0/N nodes are available: Insufficient cpu` or `Insufficient memory`.

**Causes and fixes.**
- **Requests larger than any node.** A service asking for more CPU or memory than the biggest allowed instance type can never be scheduled. Lower the request or allow a larger instance type.
- **Node pool limit reached.** The pool's CPU or memory limit stops Karpenter from adding nodes. Raise the limit in the cluster's node pool settings, then redeploy the cluster.
- **Cloud quota or capacity.** On AWS the cluster shows a quota warning; spot capacity may be exhausted for the allowed instance types. See `reference/aws-eks.md`.
- **Affinity too strict.** A `deployment.affinity.node.required` value that matches no allowed instance type or capacity type.
- **Volume zone.** A pod with a persistent volume can only run in the volume's zone.

Read the events: `qovery cluster` status in the Console, or with a read-only kubeconfig, `kubectl describe pod <pod> -n <namespace>`.

Docs: <https://www.qovery.com/docs/getting-started/troubleshoot/overview>.

## Pods evicted or restarted without a deployment

Usual reasons, most frequent first:
1. **Node consolidation or replacement** by Karpenter (default pool at any time, stable pool in its window, any pool on drift after an upgrade or AMI change). See `reference/aws-eks.md`.
2. **OOM kill** (container restart with exit code 137). See `reference/app-runtime.md`.
3. **Failed liveness probe** (container restart). See `reference/app-runtime.md`.
4. **Spot reclaim** by the cloud provider.
5. **Node pressure eviction** when pods use far more than they request.

The cure for all of them is the same pattern: 2 or more instances for anything that must stay up, requests close to real usage, graceful SIGTERM handling, and readiness that reflects real readiness.

## Autoscaling with HPA

- Classic HPA scales on CPU, or CPU and memory together (memory-only is not supported). Defaults: CPU target 60%, scale up after about 15 seconds above target, scale down after 5 minutes below.
- Set minimum and maximum instances in the service **Resources** settings. Minimum equal to maximum means no autoscaling.
- Thresholds can be tuned with the `hpa.cpu.average_utilization_percent` and `hpa.memory.average_utilization_percent` advanced settings.
- HPA scales on average usage relative to the **request**. A request far below real usage makes the HPA scale out constantly; far above, it never scales.
- An HPA that keeps scaling up and down can make Karpenter churn nodes and pull images repeatedly, which shows up as NAT and data transfer cost. Stabilize the thresholds and right-size the requests.

Docs: <https://www.qovery.com/docs/configuration/application#instances-%26-autoscaling>, guide: <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/hpa-vs-keda-autoscaling>.

## Autoscaling with KEDA (event-driven, scale to zero)

- KEDA scales on external signals (queue depth, stream lag, Prometheus queries, cron) and supports a minimum of 0 instances.
- Available on AWS and GCP clusters. Enable **KEDA** in the cluster settings first, then choose KEDA autoscaling on the service.
- The KEDA policy accepts an `advanced` block (the ScaledObject `advanced` field, top-level keys `horizontalPodAutoscalerConfig`, `restoreToOriginalReplicaCount`, `scalingModifiers`), for example `horizontalPodAutoscalerConfig.behavior.scaleDown.stabilizationWindowSeconds` to slow down scale-in.
- Scale to zero means the first request or message after idle waits for a pod to start.

## kubectl, shell and debug pods

- Read-only kubectl access: `qovery cluster kubeconfig --cluster-id "<id>" --read-only`. See `reference/aws-eks.md`.
- A shell in a running container: `qovery shell` (needs the **Shell** permission), or the **Cloud Shell** tab of the service in the Console.
- A container that crashes too fast, or an image without a shell: `qovery shell --ephemeral --mode clone` or `--mode debug`. See `reference/app-runtime.md`.
- List pods of a service: `qovery list-pods` (or pass the service's Console URL).
- A node-level debug pod: `qovery cluster debug-pod`.

## Namespaces and network policies

- Each environment is a namespace. The namespace name is exposed to services through a built-in variable.
- By default, services in different environments of the same cluster can reach each other over internal DNS. To isolate environments, apply standard Kubernetes `NetworkPolicy` objects; Qovery documents a pattern: <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/isolate-environments-network-policies>. Test it on a non-production environment first.

## Logs: live, history and retention

| | With the observability package (Qovery Observe) | Without |
|---|---|---|
| History | 12 weeks | 24 hours maximum |
| Volume | Unlimited lines | Latest 1,000 lines per service |

- Live logs: Console **Logs** tab, or `qovery log --service "<name>"` (`--application`, `--container`, `--database`, `--job` also exist).
- Deployment logs (build and deploy steps) are separate from service logs: see `reference/deployments-builds.md`.
- "I cannot see logs from yesterday": without the observability package, history is short. Options: Qovery Observe (not self-service; ask Qovery), or ship logs to your own tool (Datadog, CloudWatch, Grafana).

Docs: <https://www.qovery.com/docs/configuration/deployment/logs>, <https://www.qovery.com/docs/configuration/integrations/observability/qovery-observe>.

## Metrics, alerts and third-party observability

- Qovery Observe adds service health, CPU and memory, network and request metrics, events and alerts in the Console.
- Alert names: **Instance restart** means a container restarted inside a running pod (crash, failed liveness probe, OOM kill); **Missing instance** means a pod disappeared (evicted, deleted, or its node was removed).
- **Datadog** is installed as a Helm service: <https://www.qovery.com/docs/configuration/integrations/observability/datadog>. The Datadog agent reports Kubernetes metrics under its own names (`kubernetes.*`, `kubernetes_state.*`), not Prometheus names, so dashboards and monitors copied from elsewhere may need renaming. Enable log collection for all containers if logs are missing.
- Other integrations: CloudWatch (<https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/cloudwatch-integration>), Grafana, New Relic and SigNoz blueprints, and Kubecost for cost visibility.

## Known limits

- Without the observability package, log history is short (see table).
- Memory-only HPA is not supported.
- KEDA is limited to AWS and GCP clusters.
