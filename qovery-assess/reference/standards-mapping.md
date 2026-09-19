## Standards Mapping — anchoring checks to published controls

Load this alongside Phase 1b when the customer's audience is a security reviewer, an
auditor, or a prospect's due-diligence questionnaire. It maps this skill's checks to
published control frameworks, so a finding reads as *"this is the control the industry
names"* rather than *"this is Qovery's opinion"*.

---

### The honest framing: two different worlds

Say this in the report, because it is true and it protects the document's credibility:

**Security and workload hardening have official, numbered, auditable standards.** CIS
Kubernetes Benchmark, Pod Security Standards, NSA/CISA Kubernetes Hardening Guide, NIST
SP 800-190. A finding in that space can and should cite one.

**Production readiness does not.** There is no standards body that says a production
service needs two replicas, that liveness probes must not check dependencies, or that
staging should mirror production. Those checks come from operational experience and from
what actually causes incidents — which is a perfectly good basis, but it is not a standard,
and claiming otherwise invites a reviewer to go looking for a citation that does not exist.

So: cite standards where they exist, and where they do not, say plainly that the
recommendation is practice-based. `SOC 2` / `ISO 27001` / `PCI DSS` sit in a third
category — they are *outcome*-oriented, so they ask for evidence of RBAC, logging,
encryption, backup and incident response rather than specific settings. Phase 1b already
handles those as the compliance overlay.

---

### What this assessment can and cannot see

**This is the paragraph that keeps the mapping honest.** The CIS Kubernetes Benchmark runs
to roughly 120 numbered controls covering control-plane flags, etcd, kubelet configuration,
worker-node files and cluster policies. Most of those are only observable from *inside* the
cluster, with a kubeconfig, using a tool like `kube-bench`.

**This skill deliberately never fetches a kubeconfig** — it is on the forbidden-endpoint
list, because a kubeconfig is a standing credential granting full cluster access. So the
REST API alone observes only the subset of controls Qovery surfaces, listed below.

### Closing the gap: the Qovery MCP Server's cluster-state tools

**There is a second path, and it should be used when available — but it sees considerably
less than its breadth suggests.** The Qovery MCP Server exposes read-only tools returning the
live state of Kubernetes objects. Its risk profile is fundamentally different from a
kubeconfig:

| | Kubeconfig | MCP cluster state |
|---|---|---|
| Credential | Standing, full-cluster, reusable | Brokered per call, no credential handled |
| Scope | Everything the cert allows | Organization RBAC, read-only by default |
| Audit | Nothing in Qovery | Every query appears in the Qovery audit log |

So the rule is **not** "never look inside the cluster" — it is **never hold a cluster
credential**. Using the MCP's read-only cluster-state tools is consistent with this skill's
contract; fetching a kubeconfig is not.

**How to use it — discover, do not assume.** Tool names and argument shapes change. At
assessment time:

1. Enumerate the MCP server's available tools rather than hardcoding a name.
2. **Never call a tool that writes.** At least one tool on this server is an agent-style
   endpoint whose own description lists deploy, redeploy, stop, restart, delete, scale and
   environment-variable updates among its actions. Read each description before calling it:
   a tool advertising write actions is out of contract for this skill however the request is
   phrased. Prefer the narrow query tools.
3. Record in the report that in-cluster state was read via the MCP, so the customer can
   reconcile it against their own audit log.

#### What the cluster-state tool actually returns

Each object comes back in this shape, and nothing more:

```
{"kind":…, "name":…, "namespace":…, "conditions":[…], "phase":…?, "fallback":…?}
```

**It returns `.status` only — never `.spec`.** That one fact decides what is observable, and
it rules out most of what a pod-security review wants.

| Wanted | Available? | Why |
|---|---|---|
| NetworkPolicy present or absent | **Yes** | Objects are enumerated by kind/name/namespace even when they carry no status at all |
| Admission webhooks are registered | **Yes** | Enumerate `ValidatingWebhookConfiguration` |
| *Which* policy engine is installed, or that none is | **No, not from webhooks alone** | A `ValidatingWebhookConfiguration` is registered by cert-manager and by several controllers that are not policy engines, and an empty list misses Kubernetes-native `ValidatingAdmissionPolicy`, which registers no webhook. Confirm by querying the engine's own CRDs (`ClusterPolicy` for Kyverno, `ConstraintTemplate` for Gatekeeper) and `ValidatingAdmissionPolicy`/`-Binding`, and report `UNKNOWN` rather than "none installed" when nothing is found |
| A PodDisruptionBudget exists, and whether it currently reports `DisruptionAllowed=False` | **Yes** | Exposed as a status condition |
| Which workloads a PDB actually *covers* | **No** | The selector and `minAvailable`/`maxUnavailable` live in `.spec`. A cluster can hold three PDBs that between them protect nothing. Report the objects found, never a coverage percentage |
| Certificate health — issued, Ready, not expired — and `ClusterIssuer` present | **Yes** | Ready condition on `Certificate` and `ClusterIssuer` |
| Node readiness, memory/disk/PID pressure, Karpenter node drift | **Yes** | `Node`, `NodeClaim` and `NodePool` conditions |
| Pod phase (`Running`, `Pending`, …) | **Yes** | `phase` fallback field |
| `privileged`, `hostPath`, `hostNetwork`, `hostPID`, `allowPrivilegeEscalation`, `runAsNonRoot`, dropped capabilities, seccomp | **No** | All live in `.spec`. **A real Pod Security Standards position is not obtainable this way** — say so rather than implying it was checked |
| Real certificate expiry dates | **No** | `notAfter` is not surfaced, only "up to date and has not expired". `SC-20` still cannot give a date |
| Node zone distribution | **No** | Labels are not returned, so `topology.kubernetes.io/zone` is unreadable. `RL-11` and `DR-05` remain declared-configuration findings |
| Replica counts, container restart counts | **No** | Surfaced on neither Deployment nor Pod |

To reach a kind the curated categories do not cover, pass an explicit group/version/kind —
that is how NetworkPolicy, ValidatingWebhookConfiguration and PodDisruptionBudget above were
queried.

**Two traps that manufacture false findings:**

- **The `namespace` object filter returned nothing in testing.** Narrowing a category to a
  namespace that demonstrably held matching objects came back empty — indistinguishable from
  "this cluster has none". The tool documents `object_filter` as supported, so treat this as
  a behaviour to verify at assessment time rather than a rule: run one query with the filter
  and one without, and if they disagree, trust the unfiltered one. Filtering by `name`, or
  selecting on the `namespace` field of the unfiltered results, avoids the question.
- **Absence is only evidence once the call shape is proven.** An empty result means "none"
  *only* after the same query has returned objects somewhere. Enumerate unfiltered first,
  then narrow.

Treat any findings from this path as a **distinct evidence class** in the report: mark them
as in-cluster observations, because they are point-in-time runtime state rather than
declared configuration, and the two can legitimately disagree.

### Either way, never overclaim

**Never write or imply "CIS compliant", "CIS assessed", or a coverage percentage.** Even
with MCP cluster state, control-plane flags, etcd configuration and kubelet arguments remain
outside reach — those are what `kube-bench` is for. The correct sentence is:

> "Of the CIS Kubernetes Benchmark controls observable through the Qovery API {{and the MCP
> cluster-state tool}}, N were checked; the remainder — control-plane flags, etcd and kubelet
> configuration — require running kube-bench in-cluster, which is a separate exercise."

Offering that follow-up is a legitimate next step. Pretending this assessment already covers
it is not.

**Do not pin version numbers into the report from this file.** Benchmarks are revised, and a
stale version number ages the document badly. Check which revision is current at assessment
time, cite it with its release date and a source link, and note which Kubernetes versions it
covers relative to the clusters in scope (`CL-02` already reports those).

---

### CIS Kubernetes Benchmark

Published by the Center for Internet Security, with distribution-specific variants for
managed services (EKS, GKE, AKS). The managed variants are the relevant ones here, since
Qovery clusters are managed control planes — their structure is roughly: control-plane
logging, worker nodes, policies (RBAC, pod security, network, secrets), and managed-service
configuration (registry, IAM, encryption, endpoint access).

| Check | Control area |
|---|---|
| `SC-03` open Kubernetes API | Managed services — control-plane endpoint access restriction |
| `SC-22` control-plane audit logging | Control-plane logging |
| `SC-19` network flow logs | Logging and monitoring |
| `SC-16` admin minimisation | Policies — RBAC and service accounts |
| `SC-11` service-account token automount | Policies — RBAC and service accounts |
| `SC-12` per-service cloud identity | Managed services — identity and access management |
| `SC-24` role-based cloud credentials | Managed services — identity and access management |
| `SC-25` SSH keys on cluster nodes | Worker nodes — remote access |
| `SC-10` read-only root filesystem | Policies — pod security |
| `SC-14` encryption at rest | Managed services — encryption |
| `SC-08` `VS-01` `VS-02` secret handling | Policies — secrets management |
| `DL-11` immutable image tags | Managed services — image provenance |
| `SC-02` database network policy | Policies — network segmentation |

**Observable here but not benchmark-covered:** most of `RL-`, `TP-`, `BP-`, `DR-`.
**Benchmark-covered but not observable here:** kubelet flags, etcd configuration,
control-plane component arguments, admission controllers, NetworkPolicy objects, seccomp and
AppArmor profiles, privileged/hostPath/hostNetwork pod settings. Those need `kube-bench`.

---

### Pod Security Standards

The upstream Kubernetes workload baseline — three profiles, `privileged`, `baseline` and
`restricted`, covering privilege escalation, host namespaces, capabilities, seccomp and
running as non-root.

| Check | Profile element |
|---|---|
| `SC-10` read-only root filesystem | `restricted` |
| `SC-11` service-account token automount | Hardening beyond `restricted` |

**Be explicit about the gap.** Qovery surfaces only these two of the PSS controls through
its API. Whether workloads run privileged, mount host paths, use host networking, drop
capabilities, or set `runAsNonRoot` is **not visible** to this assessment. If the customer
wants a PSS position, that is an in-cluster exercise — say so rather than implying the two
observable settings represent the profile.

---

### NSA/CISA Kubernetes Hardening Guide

Government baseline, organised by threat rather than by flag, which makes it the most useful
one to *quote* in a report because its sections read as risks.

| Check | Guide area |
|---|---|
| `SC-01` `SC-04` `SC-02` exposure | Network separation and hardening |
| `SC-03` API endpoint restriction | Network separation and hardening |
| `SC-10` `SC-11` workload hardening | Kubernetes pod security |
| `SC-15` `SC-16` `SC-17` `SC-26` identity | Authentication and authorization |
| `SC-24` credential type, `SC-25` node SSH access | Authentication and authorization |
| `SC-19` `SC-22` `DL-05` `OP-03` `OP-04` | Audit logging and threat detection |
| `CL-02` Kubernetes version currency | Upgrading and application security practices |

---

### NIST SP 800-190 — Application Container Security Guide

Maps container risks to countermeasures and up into NIST SP 800-53 controls, which matters
for anyone with a federal or NIST-aligned obligation.

| Check | Countermeasure area |
|---|---|
| `DL-11` image tags, `DL-12` pinned sources | Image countermeasures |
| `SC-18` registry credentials, registry configuration | Registry countermeasures |
| `SC-16` RBAC, `SC-03` API access, `SC-08` secrets | Orchestrator countermeasures |
| `SC-10` `SC-11` runtime hardening | Container countermeasures |
| `SC-13` instance metadata service, `SC-25` node SSH keys | Host OS countermeasures |
| `DL-14` deployed-commit provenance | Image countermeasures — provenance of what runs |
| `OP-07` Terraform service scope | Orchestrator countermeasures — least privilege for automation |

**Not observable here:** image vulnerability scanning results, base-image provenance and
age, runtime behavioural monitoring, host OS configuration.

---

### How to render this in the report

- **Add the standard as a badge next to the compliance badges** on findings that map —
  `CIS`, `PSS`, `NSA/CISA`, `NIST 800-190` — using the same visual treatment as the
  SOC 2 / ISO / GDPR badges from Phase 1b.
- **Badge only what maps.** A reliability finding with no standard gets no standards badge,
  and that absence is informative rather than a gap in the report.
- **Put the coverage caveat in the Method section**, next to the existing scope limits. It
  belongs with "not a penetration test", not buried in an appendix.
- **Reconcile with Phase 1b.** Compliance badges (SOC 2, ISO, GDPR, DORA, PCI) say *what an
  auditor will ask about*. Standards badges (CIS, PSS, NSA/CISA, NIST) say *what the control
  is called*. A finding can carry both, and the two answer different questions.
