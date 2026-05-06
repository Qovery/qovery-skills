## PHASE 4: BYOK Path (Bring Your Own Kubernetes)

If the user has an existing Kubernetes cluster, guide them through installing Qovery on it.

### 4.1 Check Prerequisites

Verify the user's cluster meets the requirements:

- Kubernetes version >= 1.24
- Minimum 4 CPUs and 8GB RAM available in the cluster
- `kubectl` installed and configured with cluster-admin access
- `helm` package manager installed

```bash
# Check Kubernetes version
kubectl version --short

# Check available resources
kubectl top nodes

# Check kubectl access
kubectl auth can-i '*' '*' --all-namespaces
```

### 4.2 Install Qovery CLI

```bash
# macOS
brew tap Qovery/qovery-cli && brew install qovery-cli

# Linux
curl -s https://get.qovery.com | bash

# Verify
qovery version
```

### 4.3 Authenticate

```bash
qovery auth
```

This opens a browser for authentication. For headless environments:
```bash
qovery auth --headless
```

### 4.4 Install Qovery on the Cluster

Run the interactive installer:

```bash
qovery cluster install
```

This command:
1. Detects your Kubernetes cluster
2. Asks for your Qovery organization and cluster name
3. Installs the Qovery components via Helm:
   - **Qovery Agent** — communicates with the Qovery control plane
   - **Qovery Shell Agent** — enables `qovery shell` and `qovery port-forward`
   - **Ingress controller** — routes external traffic to your services
   - **Cert-manager** — automatic TLS certificate provisioning

The installation typically takes 5-10 minutes.

> "Qovery is being installed on your cluster. This installs a lightweight agent and supporting components. It won't interfere with your existing workloads."

### 4.5 Verify Installation

```bash
# Check all Qovery pods are running
kubectl get pods -n qovery

# All pods should be in Running or Completed state
```

Then verify in the Qovery Console:
> "Check the Qovery Console at https://console.qovery.com > Clusters. Your cluster should appear with a 'Connected' status."

### 4.6 Continue with Project Setup

After BYOK installation, continue with Phase 3.4 (project and environment creation) — the rest of the setup is the same as the managed cluster path.

---

