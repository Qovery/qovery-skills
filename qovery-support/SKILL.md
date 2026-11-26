---
name: qovery-support
description: Answers the questions Qovery users ask support most often and walks through the fixes that resolved them, covering deployments and builds, app crashes and health probes, custom domains and TLS, ingress timeouts, static IPs and VPC peering, databases, environment variables and secrets, AWS EKS clusters (Karpenter, node pools, upgrades, IAM, quotas), autoscaling, logs, the CLI, API and Terraform provider, billing and team access. Built from anonymized Qovery support history and checked against the Qovery docs. Hands off to qovery-troubleshoot when a specific service needs live diagnosis. Use when a user asks a how-to, why or "is this expected" question about Qovery, Kubernetes or AWS on Qovery, or wants to know the known fix for a common error before opening a support ticket.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: support
---

# Qovery Support Skill

This skill is a knowledge base of the questions Qovery users bring to support and the answers that worked. It covers Qovery itself, the Kubernetes concepts Qovery exposes, and the AWS side of a Qovery-managed cluster. Each topic lists the symptom as users describe it, the usual causes, how to check, the fix, and when to escalate.

It is not a live debugger. When the user has a specific failing service and wants it diagnosed with logs and events, hand off to `qovery-troubleshoot`. When the user's question turns out to be "make it faster" or "make it cheaper", hand off to `qovery-speedup` or `qovery-optimize`.

## Usage Tracking

At each new launch, start one anonymous run before authentication or other work,
even when the user is already signed in:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-support
```

Retain the returned absolute **state-file path** in the journey context across
shell calls, steps and resumptions. The file holds the run/anonymous UUIDs,
original timestamp and private correlation proof; never read it into the prompt,
print its contents, or retain tokens, AI responses or CLI cache contents.
The helper requires macOS, Linux or WSL with Bash and curl. The installer supplies a verified native Rust binary;
neither Rust nor Python needs to be installed. Native Windows is unsupported.
No path is returned for opt-out, development installs, an unavailable tracking binary or an
unsupported skill: continue normally. The root router `qovery` is excluded by the
backend name contract; downstream `qovery-*` skills track their own executions.

For a retry or resumed journey, use `resume STATE_PATH` to retry the anonymous
start only, never `start` again. Many support questions never need a sign-in: in
that case, keep the anonymous run and skip association. If the user signs in and
**explicitly selects an organization** (for example to check their own setup), run:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' associate 'STATE_PATH' --organization 'ORGANIZATION_UUID'
```

Replace those placeholders with the retained path and selected UUID. Do not guess
the first organization returned by an API. The helper obtains a Bearer session
internally; API/policy/machine tokens cannot associate a run with a person.
One run has one immutable account/organization association. On an account or
organization change, end the old journey and start a **new execution**.

Requests run in the background with bounded deadlines. At journey completion, use
`cleanup STATE_PATH` only after queued requests are no longer needed. Set
`QOVERY_SKILLS_NO_TRACKING=1` before any command to prevent helper state creation
and sends. `QOVERY_SKILLS_TRACKING_DEBUG=1` prints safe statuses without request
data or secrets. Never call the legacy tracking endpoint as a fallback.

> **API rule:** send this exact `User-Agent` header on **every** `curl` call to `api.qovery.com`, spelled out in full each time. A shell variable set in one command is gone by the next one:
>
> ```
> -H "User-Agent: QoverySkill/qovery-support (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
> ```

## Organization preset

After authentication, once the member has chosen or confirmed the organization, apply your
organization's skill preset before doing the task: read `reference/org-preset.md` and follow it. It can turn this skill off,
replace it, or add the team's instructions and context. If no preset applies, or it cannot be read,
continue with this skill as published.

## When to Use This Skill

Trigger phrases:
- "How do I get a static IP to whitelist?"
- "My custom domain has no certificate"
- "I get a 504 after 15 seconds"
- "How do I connect to my database from my laptop?"
- "Why are my pods restarting / being moved to another node?"
- "Why did my environment variable get the wrong value?"
- "Can I upgrade my EKS cluster myself?"
- "Why is my deployment refused?"
- "How do I invite a teammate / switch login provider?"
- "Is this a known issue?"
- `/qovery-support` (slash command)

## Workflow

```
Support Progress:
- [ ] 1. Classify the question into one topic from the table below
- [ ] 2. Load that one reference file (not all of them)
- [ ] 3. Ask only for the context the matching entry needs (cloud provider, service type, exact error)
- [ ] 4. Answer: likely cause, how to confirm, the fix, how to verify it worked
- [ ] 5. Hand off or escalate when the entry says so
```

Rules that apply to every answer:

1. **Start from the user's exact error text.** Match it against the symptoms in the reference file before guessing.
2. **Read before you change.** Checks use read-only commands (`qovery status`, `qovery log`, `qovery api <path>` GETs, `kubectl get/describe` with a read-only kubeconfig). Any write (advanced settings, variables, cluster settings, redeploys) needs the user's explicit go-ahead.
3. **Say when something is not supported.** Several common requests are known product limits (listed in each file). State the limit and the documented workaround instead of inventing a setting.
4. **Never print secrets.** Do not echo tokens, passwords, connection strings or kubeconfig contents. Token handling rules are in [reference/auth.md](reference/auth.md).
5. **Do not invent flags or settings.** If a setting is not in the reference file or in the docs page it links, check `qovery <command> --help` or the docs before recommending it.

## Topics (load on demand)

| Topic | File | Typical questions |
|---|---|---|
| Builds and deployments | [reference/deployments-builds.md](reference/deployments-builds.md) | Build failed, Docker Hub rate limit, stuck or cancelling deployment, auto-deploy not firing, preview environments, lifecycle and cron jobs |
| App runtime | [reference/app-runtime.md](reference/app-runtime.md) | OOMKilled, CrashLoopBackOff, probe failures, connection refused, slow start, exit code 0, restarts |
| Networking and domains | [reference/networking-domains.md](reference/networking-domains.md) | Custom domain and TLS, 504 timeouts, NGINX to Envoy Gateway, static outbound IP, inbound IPs, VPC peering, WAF, internal traffic |
| Databases | [reference/databases.md](reference/databases.md) | Container vs managed (Blueprint), connect from a laptop, connection strings, backups and snapshots, Redis/Valkey swap |
| Variables and secrets | [reference/secrets-env.md](reference/secrets-env.md) | Scopes and overrides, aliases, interpolation, build-time variables, secrets in builds, cross-environment references |
| AWS EKS clusters | [reference/aws-eks.md](reference/aws-eks.md) | Cluster creation errors, quotas, IAM and credentials, Karpenter node pools and spot, Kubernetes upgrades, custom AMIs, cluster deletion |
| Kubernetes on Qovery | [reference/kubernetes-basics.md](reference/kubernetes-basics.md) | Pending pods, evictions, HPA and KEDA, kubectl access, namespaces, network policies, logs and alerts, observability |
| CLI, API and Terraform | [reference/cli-api-terraform.md](reference/cli-api-terraform.md) | CLI commands, `qovery api`, advanced settings via the API, Terraform provider drift, Terraform services, control-plane IPs |
| Billing and access | [reference/billing-access.md](reference/billing-access.md) | Deployment refused for billing, plan-gated features, roles and custom roles, invites, login provider switch, SSO |
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract organization, project, environment and service IDs from a pasted Console URL |
| Auth | [reference/auth.md](reference/auth.md) | Sign in with `qovery auth`, token handling rules |

## Most common questions (one-line answers)

Each line points to the file with the full entry.

| Question | Short answer | File |
|---|---|---|
| Requests fail with 504 after about 15 seconds | Envoy Gateway's default request timeout; raise `network.gateway_api.http_request_timeout_seconds` on the service (or `envoy.gateway_api.http_request_timeout_seconds` on the cluster), then redeploy | networking-domains |
| Custom domain stuck without a certificate | CNAME must point to the target shown in the Console; wait for DNS, then redeploy. Wildcards on Cloudflare need CDN proxy mode | networking-domains |
| Static outbound IP for an allowlist | Cluster **Static IP** feature (NAT gateways + Elastic IPs). On AWS it is chosen at cluster creation and cannot be turned on later | networking-domains |
| Connect to the database from a laptop | `qovery port-forward` for debugging; not for production traffic or high-churn clients | databases |
| Production database | Use a managed database from a Blueprint (for example Amazon RDS for PostgreSQL); container databases are for dev and test | databases |
| Health checks fail on a slow-starting app | Add a startup probe (Startup column of the health checks) or raise the initial delay; move migrations to a lifecycle job | app-runtime |
| OOMKilled / exit code 137 | Memory limit too low for peak usage; raise memory, then look for leaks | app-runtime |
| Pods restart or move between nodes | Karpenter consolidation and node pools; run at least 2 instances for anything that must not blip | kubernetes-basics |
| Alias or variable has an unexpected value | Check redeploy, scope overrides and alias targets; re-point an alias through the API or the rename swap, never delete and recreate it | secrets-env |
| Can I upgrade Kubernetes myself in the AWS console? | No. Qovery manages upgrades; manual upgrades break Qovery components | aws-eks |
| Changed one advanced setting via the API and others reset | `PUT .../advancedSettings` replaces the whole object; always GET, edit, PUT the full object | cli-api-terraform |
| Deployment refused although the invoice is paid | Organization billing restriction; contact Qovery support with the invoice reference | billing-access |

## Hand-offs

| Situation | Skill |
|---|---|
| A specific service is failing now and needs logs, events and a fix applied | `qovery-troubleshoot` |
| Deployments work but are slow | `qovery-speedup` |
| The question is about reducing the cloud bill or right-sizing | `qovery-optimize` |
| Whole-organization best-practice review | `qovery-assess` |
| Setting up per-PR preview environments | `qovery-preview` |
| First deployment of an app | `qovery-deploy` |
| Least-privilege API token for an agent or CI | `qovery-policy-token` |

If one of these skills is not installed, give the user the steps from the reference file instead.

## Escalate to Qovery support

Escalate when the reference entry says so, when a fix needs Qovery to act (billing unlocks, platform bugs, Qovery-managed components failing during a cluster deployment), or after the documented fix did not work.

- In the Console: the **help button** at the bottom right, then **Contact Support**.
- Customers with a shared Slack or Teams channel can post there.
- Support options: <https://www.qovery.com/support> and <https://www.qovery.com/docs/getting-started/useful-resources/help-and-support>.

Help the user write a good ticket: the Console URL of the service or cluster, the deployment ID or time window, the exact error lines, what they already tried, and the cloud provider and region. Never paste secrets, tokens or full connection strings into a ticket.

Qovery runs a shared responsibility model: Qovery supports what it deploys and manages; the user's application code and anything changed directly in the cloud provider console are the user's responsibility. Say so when a fix belongs to the user or to AWS.

## Reference links

- **Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Troubleshooting guide**: <https://www.qovery.com/docs/getting-started/troubleshoot/overview>
- **FAQ**: <https://www.qovery.com/docs/getting-started/useful-resources/faq>
- **Service advanced settings**: <https://www.qovery.com/docs/configuration/service-advanced-settings>
- **Cluster advanced settings**: <https://www.qovery.com/docs/configuration/cluster-advanced-settings>
- **CLI reference**: <https://www.qovery.com/docs/cli/commands/overview>
- **API reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **Changelog**: <https://www.qovery.com/changelog>
