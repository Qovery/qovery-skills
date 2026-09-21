# Example — Executive Summary

Fictional organization ("Acme Payments"), included as a density and tone reference for
the executive summary and the first findings. Numbers are illustrative; never reuse
them in a real report.

---

## 1. Executive summary

Acme Payments runs a single AWS cluster in `eu-west-3` hosting 4 environments and 23
services, with a managed PostgreSQL behind the payments API. The delivery setup is in
good shape — staged pipelines, consistent auto-deploy, a healthy deployment success
rate. The gap is concentrated in availability: **more than half the production services
cannot survive the loss of a single node**, and production shares a cluster with
development.

### Scorecard

| Pillar | Score | Level | Headline |
|---|---:|---|---|
| Reliability & Resilience | 54/100 | 1 | 9 of 16 production services run one replica |
| Security & Data Protection | 78/100 | 3 | Strong secret hygiene; K8s API open to 0.0.0.0/0 |
| Performance & Scalability | 61/100 | 2 | Autoscaling configured but capped at the minimum |
| Delivery & Operations | 82/100 | 3 | Staged pipelines and reliable deploys; no alerting |
| Cost Efficiency | 47/100 | 1 | Three dev environments running 24/7 |
| **Overall** | **66/100** | **Level 2 — Managed** | It works; resilience depends on nothing going wrong |

**Coverage:** 147 checks defined, 118 evaluated (71 pass, 22 partial, 25 fail), 9
observations, 11 not applicable, 9 could not be determined.

**The level is capped, not computed.** Three unresolved Critical findings hold the maturity
level at 2 regardless of the arithmetic; the pillar scores above are what will move once
they are closed. A publicly reachable Kubernetes API server is not a rounding error.

### Top risks

| # | ID | Severity | Risk | Impact if unaddressed | Effort |
|---|---|---|---|---|---|
| 1 | RL-01 | Critical | 9 of 16 production services run `min_running_instances: 1` | Every cluster upgrade, node drain, spot reclaim, or OOM kill takes each service fully offline for 10–60s. There is no zero-downtime deploy path today. | S |
| 2 | DL-05 | Critical | No alert receivers and no alert rules are configured | Nobody is notified when production degrades. Detection currently depends on a customer reporting it. | M |
| 3 | SC-03 | Critical | The EKS API server accepts connections from `0.0.0.0/0` | Any leaked kubeconfig or CI credential grants cluster access from anywhere on the internet. | S |
| 4 | CL-05 | High | Production and development share cluster `acme-prod-1` | A runaway dev build evicts production pods; the blast radius of any cluster-wide incident includes revenue. | L |
| 5 | RL-13 | High | 11 services have no pre-stop hook and a 30s grace period | In-flight requests are cut on every deploy, producing the 502s the team currently attributes to "deploy noise". | S |

### What is already strong

- **Deployment pipeline is properly staged.** All four environments order datastores →
  migrations → backends → frontends. Migration-ordering failures, a common source of
  false rollbacks, are structurally prevented here.
- **Production data is on managed PostgreSQL** with daily backups, the most recent
  from 6 hours before this assessment.
- **Secret hygiene is genuinely good.** Every credential-shaped key is stored as a
  Qovery secret, scoped at environment level, with no duplication across services.
  This is the exception rather than the norm.
- **Change failure rate is 4%** across the last 50 production deployments — well inside
  a healthy band, and evidence the team's review process works.
- **Health checks exist on every service**, with readiness and liveness configured
  separately and sensible initial delays.

---

## 4.1 Reliability & Resilience — 54/100

### RL-01 — Production services run a single replica

- **Severity:** Critical
- **Scope:** 9 of 16 production applications — `payments-api`, `ledger-worker`,
  `webhook-dispatcher`, `settlement-job-runner`, `kyc-service`, `notification-api`,
  `admin-console`, `reporting-api`, `fx-rate-poller`
- **Finding:** `min_running_instances: 1` with `max_running_instances: 1`.
- **Evidence:** `GET /environment/{prodEnvId}/services` — nine services report
  `min_running_instances=1, max_running_instances=1`.
- **Impact:** These services have no high availability and no zero-downtime deploy.
  Kubernetes reschedules the pod after a node event, but the service returns nothing for
  the 10–60 seconds that takes. `payments-api` and `ledger-worker` are on the
  transaction path, so this is customer-visible revenue impact, not just latency. It
  also blocks the cluster upgrade in CL-02: draining nodes will take each of these
  services down in turn.
- **Recommendation:** `min_running_instances: 2` as the floor, `3` for `payments-api`
  and `ledger-worker`. Pair with pod anti-affinity (RL-10) so the replicas do not land
  on the same node — without it, the second replica adds cost without adding
  availability. Node headroom is sufficient: the cluster runs 4 nodes at 41% allocation.
- **Effort:** S — a configuration change and a redeploy per service.
