# AWS EKS clusters on Qovery

Covers cluster creation errors, AWS quotas, credentials and IAM, Karpenter node pools and spot instances, Kubernetes version upgrades, custom AMIs, and cluster deletion. Most Qovery support tickets come from AWS clusters.

## Contents

- Ground rules for Qovery-managed clusters
- Cluster creation fails
- Cluster status is Warning (quota) or Error
- Credentials, IAM roles and security reviews
- Node pools: stable, default, GPU, cronjob
- Spot instances
- Pods restarted by Karpenter consolidation or drift
- Kubernetes version upgrades
- Custom AMIs and node patching
- Accessing the cluster with kubectl
- Deleting a cluster
- Known limits

## Ground rules for Qovery-managed clusters

- **Change cluster settings through Qovery**, not in the AWS console. Manual changes (node groups, route tables on the Qovery VPC, security groups, Kubernetes version) drift from Qovery's configuration and are either reverted on the next cluster deployment or break Qovery components.
- **Never upgrade Kubernetes yourself** in the AWS console. Qovery manages upgrades.
- After changing a cluster setting (instance types, node pool limits, advanced settings), **redeploy the cluster** for it to apply.
- Read the cluster logs in the Console (cluster **Logs**) for the exact error of a failed cluster deployment.

## Cluster creation fails

**Preflight checks.** Before creating or deploying an EKS cluster, Qovery checks quotas, availability zones and (for an existing VPC) subnets and tags, and blocks the deployment with a report if something is missing. Read that report first. Docs: <https://www.qovery.com/docs/configuration/integrations/kubernetes/eks/preflight-checks>.

**Common causes and fixes.**

| Error or symptom | Cause | Fix |
|---|---|---|
| `AddressLimitExceeded`, Elastic IP quota | The default AWS limit is 5 Elastic IPs per region; a cluster with Static IP needs several | Request an Elastic IP quota increase in AWS Service Quotas, or free unused EIPs, then redeploy |
| vCPU or instance limits, nodes never start | EC2 On-Demand or Spot vCPU quota too low for the instance types | Request a vCPU quota increase for the instance families used |
| VPC limit | Default 5 VPCs per region | Request an increase or use another region |
| Region rejected | Fewer than 3 availability zones | Choose a region with at least 3 zones |
| Permissions error mentioning SQS (Karpenter) | The credentials lack SQS permissions, often because an AWS Organizations SCP denies them | Check the role's policy and the SCPs with the AWS Policy Simulator on `arn:aws:sqs:::qovery*`; allow the SQS actions |
| "This account is currently blocked" | AWS has suspended the account (billing, verification) | Resolve it with AWS, then retry |
| Existing VPC mode fails validation | Missing subnets or tags | Follow the preflight report: subnet types per zone and the required tags |

A cluster shown as deploying for well over 45 minutes with no new log lines: read the cluster logs, check quotas, and escalate with the cluster ID if it persists past an hour.

Docs: <https://www.qovery.com/docs/getting-started/troubleshoot/overview> (section "Cluster Issues").

## Cluster status is Warning (quota) or Error

- **Warning with a quota callout.** Karpenter could not create nodes because an AWS service quota was reached. The callout names the quota, the impacted resource and a suggested action, usually a quota increase. Services on that cluster show **Quota issue**. It clears once nodes can be created again. Docs: <https://www.qovery.com/docs/configuration/clusters#aws-quota-warnings>.
- **Status unavailable.** The cluster is unreachable: stopped in the cloud console, a provider outage, expired credentials, or deleted resources. Check the provider status page and the credentials.
- **Error.** Read the cluster logs. If the failure is in a Qovery-managed component during a cluster deployment (for example a Helm release of the load balancer controller or cert-manager), retry the cluster deployment once; if it fails again, escalate with the logs.

## Credentials, IAM roles and security reviews

- The recommended method is an **STS assume role** created by a CloudFormation stack, rather than static access keys. Docs: <https://www.qovery.com/docs/getting-started/installation/aws>.
- Rotating credentials for the **same** AWS account: create the new credentials, select them in the cluster **Credentials** tab, then update the cluster.
- **Never switch a cluster's credentials to a different AWS account.** Qovery would lose track of the resources in the original account, which keep running and billing. To move accounts, create a new cluster in the new account, move the environments, then delete the old cluster.
- Security and compliance questions (what the role can do, how Qovery assumes it, ExternalId): IAM permissions are listed at <https://www.qovery.com/docs/getting-started/security-and-compliance/aws-iam-permissions>, and the assume-role hardening is described at <https://www.qovery.com/blog/strengthening-security-qovery-access-aws-account>.
- To give your **applications** AWS access (S3, SQS, Bedrock), use an IAM role for the service account rather than keys in variables: <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/aws-iam-roles>.

## Node pools: stable, default, GPU, cronjob

Qovery EKS clusters with Karpenter have two node pools by default:
- **Stable**: services with a single instance (minimum instances = 1), container databases, and Qovery's own components. Consolidation is off by default and can be scheduled in a window.
- **Default**: everything else. Karpenter can consolidate it at any time.

Optional: a **GPU** node pool and a **cronjob** node pool (cron jobs must be redeployed whenever it is enabled or disabled).

Settings per pool: instance types, spot on/off, disk size, consolidation schedule (stable and cronjob), a daily window that blocks drift replacements (stable), and CPU and memory limits. A pool that reaches its limits cannot add nodes, and pods stay Pending.

To pin a service: set the `deployment.affinity.node.required` advanced setting, for example `{ "karpenter.sh/capacity-type": "on-demand" }` or `{ "node.kubernetes.io/instance-type": "t3a.xlarge" }` (the type must be in the pool's list).

Docs: <https://www.qovery.com/docs/configuration/integrations/kubernetes/eks/managed#resources>.

## Spot instances

- Spot is enabled per node pool. It is discouraged on the stable pool, which hosts single-instance workloads.
- Spot nodes can be reclaimed by AWS at short notice, and spot capacity can run out for the instance types you allowed. Keep critical single-instance services on on-demand capacity (affinity above), run at least 2 instances of anything user-facing, and allow several instance families so Karpenter has alternatives.
- A fixed spot/on-demand ratio is not configurable.

## Pods restarted by Karpenter consolidation or drift

**Symptom.** "My pod restarted although nothing was deployed", "pods are moved to other nodes", a short outage on a single-instance service.

**Causes.** Karpenter consolidates under-used nodes on the default pool, and replaces drifted nodes after an instance type change, an upgrade or an AMI update.

**Fix.**
- Run 2 or more instances for services that must not blip; a service with minimum instances = 1 stays on the stable pool, but one replica always restarts when its node is replaced.
- Handle SIGTERM and set `deployment.termination_grace_period_seconds` so in-flight work finishes. This gives time but does not prevent the move.
- Use the stable pool's consolidation schedule and drift block window to keep replacements out of business hours.
- Spread replicas across zones with `deployment.topology_spread.zone` and across nodes with `deployment.antiaffinity.pod`.

## Kubernetes version upgrades

- Qovery tests each Kubernetes version before rolling it out to clusters progressively, and notifies you when an upgrade is available. You can also trigger it yourself: `qovery cluster upgrade --cluster "<name>" --watch` (it upgrades to the next available version).
- Before upgrading, check workloads for Kubernetes APIs removed in the target version: `qovery cluster analysis deprecated-api --cluster-id "<id>"`. Helm charts you deploy are the usual source of deprecated APIs.
- Qovery supports versions one or two minors behind the latest offered by AWS, so the newest EKS version is not available immediately.
- During an upgrade, nodes are replaced. Single-instance services restart; that is expected.
- If an upgrade fails on a Qovery-managed component, retry the cluster deployment once, then escalate.

Docs: <https://www.qovery.com/docs/configuration/clusters#faq>.

## Custom AMIs and node patching

The node image is set with the cluster advanced setting `aws.eks.ec2.ami` (Karpenter nodes only). Values: `AmazonLinux2023` (default), `Bottlerocket`, or a custom AMI such as `al2023:ami-...` or `bottlerocket:ami-...`. Prefix custom AMIs with their family so the right bootstrap is generated, match the CPU architecture of your instance types (arm64 for Graviton), and share the AMI with the account and region. Changing it makes nodes drift and Karpenter replaces them progressively. Test on a staging cluster first. Docs: <https://www.qovery.com/docs/configuration/cluster-advanced-settings#aws-eks-ec2-ami>.

## Accessing the cluster with kubectl

```bash
qovery cluster kubeconfig --cluster-id "<id>" --read-only   # writes kubeconfig-readonly-<id>.yaml (view ClusterRole)
export KUBECONFIG=./kubeconfig-readonly-<id>.yaml
```

Never print the kubeconfig file's contents. Use a read-only kubeconfig for inspection. Do not change Qovery-managed objects with kubectl; changes are overwritten on the next deployment. Docs: <https://www.qovery.com/docs/configuration/connect-to-cluster>.

## Deleting a cluster

- Delete the environments on the cluster first, including blueprint databases and Terraform services, so their cloud resources are removed too.
- `DependencyViolation` on a subnet or VPC during deletion: something created outside Qovery (a load balancer, an ENI, a peering, a database) still uses the network. Find it in the VPC console, delete it, then retry the deletion.
- Resources left behind after a cluster deletion can be found with the cluster's tag in the cloud console and removed by hand. Docs: <https://www.qovery.com/docs/configuration/clusters#aws-account-cleanup>.

## Known limits

- Static IP, custom VPC subnets and existing-VPC mode are chosen at creation and cannot be changed later.
- No custom Karpenter node pools beyond the ones Qovery offers; no spot/on-demand ratio.
- The newest Kubernetes version reaches Qovery clusters after a testing period.
- Credentials cannot be moved to another AWS account on an existing cluster.
