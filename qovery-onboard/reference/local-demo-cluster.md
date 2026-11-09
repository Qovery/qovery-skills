# Local demo cluster (no cloud account, no card)

Use this when the organization has **no cluster** and the user has not asked for a cloud cluster, or when they say they want to try Qovery, have no cloud account, or have no credit card on the organization. It gets them deploying in minutes on their own machine.

`qovery demo up` creates a local k3s cluster with k3d (Kubernetes in Docker), installs the Qovery Operator on it and connects it to the organization. Apps, databases and Blueprints deploy to it like any other cluster. It is free, needs no card, and runs only on this machine: it is for trying Qovery and testing, not for production.

## 1. Offer it

When `GET /organization/{orgId}/cluster` returns no cluster, offer the two paths and recommend the local one unless the user already has a cloud account ready:

> Your organization has no cluster yet. Two ways to continue:
> 1. **Try it now on this machine** (recommended to start): a local cluster in Docker, free, no cloud account. About 5 to 10 minutes.
> 2. **Use your cloud or your own Kubernetes cluster**: AWS, GCP, Azure or Scaleway, or a cluster you already run. Takes longer, and a cluster Qovery creates needs a card on the organization.

If they pick 2, continue with the cloud cluster steps of the current skill.

## 2. Check the machine

Run these and report what is missing in one message:

```bash
uname -s                                                  # Darwin, Linux, or Linux under WSL
docker info --format '{{.ServerVersion}} {{.NCPU}} cpus {{.MemTotal}} bytes'
k3d version && helm version --short && kubectl version --client
qovery version                                            # needs 1.180.1 or later
```

| Check | Needed | If not |
|---|---|---|
| OS | macOS, Linux, or Windows with WSL | Native Windows is not supported: use WSL or a cloud cluster |
| Docker | Running, with at least 4 CPUs and 8 GB of memory | Ask the user to start Docker Desktop, or raise its CPU and memory in Docker Desktop settings |
| k3d, helm, kubectl | Installed | macOS: `brew install k3d helm kubectl`. Linux: install each from its official docs |
| Qovery CLI | 1.180.1 or later (earlier versions fail with Helm 4) | `qovery upgrade` |

## 3. Things only the user can do

Ask for both in one message, and wait.

- **Organization in the CLI context.** `qovery demo up` uses the organization from the CLI context, and `qovery context set` is an interactive picker an agent cannot drive. Check with `qovery context`. If no organization is set, ask the user to run `! qovery context set` (in Claude Code) and pick the organization.
- **macOS only: a local network address**, so traffic from the machine reaches the apps on the cluster. It needs the user's password. Check first, and only ask if it is missing:

  ```bash
  ifconfig lo0 | grep -q 172.42.0.3 && echo "already set"
  ```

  If it is not set, ask the user to run: `! sudo ifconfig lo0 alias 172.42.0.3/32 up`. With the address in place, `qovery demo up` does not ask for a password.
- **WSL:** the setup needs `sudo` and a Windows administrator prompt, so ask the user to run `qovery demo up` themselves in their terminal, then continue at step 5.

## 4. Create the cluster

```bash
qovery demo up 2>&1 | tee /tmp/qovery-demo-up.log
```

It takes about 5 to 10 minutes. Run it in the background if your tool allows, and report progress from the log. The cluster is named `local-demo-<user>`; pass `--cluster-name <name>` for another name. Running it again with the same name reuses that cluster's record in the organization.

## 5. Check it worked

```bash
qovery cluster list
```

The local cluster must be listed and running. Keep its ID: it is the cluster for the environments you create next. Then continue with the current skill.

Tell the user that apps deployed there are reachable from this machine only, and that they can move to a cloud cluster later by creating one and deploying the same project to it.

## If it fails

`qovery demo up` ends with an error code. Act on it once, then stop and tell the user; do not loop.

| Code | What to do |
|---|---|
| `DOCKER_NOT_RUNNING` | Ask the user to start Docker, then run `qovery demo up` again |
| `MISSING_DEPENDENCY` | Install the tool the message names (step 2), then run again |
| `UNSUPPORTED_OS` | Offer a cloud cluster instead |
| `AUTHENTICATION_FAILED` | `qovery auth --headless`, the user opens the link, then run again |
| `ORGANIZATION_NOT_RESOLVED` | The user runs `! qovery context set`, then run again |
| `LOOPBACK_SETUP_FAILED` | The user runs the `sudo ifconfig` line from step 3, then run again |
| `INVALID_CLUSTER_NAME`, `CLUSTER_NAME_NOT_A_DEMO` | Run again with `--cluster-name` and a new name |
| `LEGACY_RELEASE_EXISTS` | An older demo is installed: `qovery demo destroy`, then `qovery demo up` |
| `K3D_CLUSTER_FAILED` | Usually Docker resources or a port in use: check Docker's CPU and memory, then run again |
| `QOVERY_API_ERROR`, `HELM_LIST_FAILED` | Run again once |
| `OPERATOR_INSTALL_FAILED`, `OPERATOR_HEARTBEAT_TIMEOUT`, `CLUSTER_DEPLOYMENT_FAILED`, `CLUSTER_DEPLOYMENT_TIMEOUT`, `WORKLOAD_VERIFICATION_FAILED` | Run once more with `--debug`. If it fails again, give the user the code and the last lines of `/tmp/qovery-demo-up.log`, suggest the qovery-troubleshoot skill or Qovery support, and offer a cloud cluster instead |

## Remove it

```bash
qovery demo destroy                          # deletes the local cluster, keeps its record in Qovery
qovery demo destroy --delete-qovery-config   # also deletes the Qovery cluster record and its environments
```

Ask before using `--delete-qovery-config`: it deletes the environments deployed on that cluster.
