# Builds and deployments

Covers build failures, registries, stuck or cancelled deployments, auto-deploy and Git webhooks, preview environments, and lifecycle and cron jobs. For a single service failing right now, hand off to `qovery-troubleshoot`. For slow but working deployments, hand off to `qovery-speedup`.

## Contents

- Read a failed deployment first
- Build fails
- Docker Hub rate limits and registry login errors
- New code does not show up after deploy
- Deployment stuck, queued or "cancelling"
- Auto-deploy does not trigger
- Preview environments
- Lifecycle jobs and cron jobs
- Known limits

## Read a failed deployment first

Most deployment questions are answered by the first error line of the failing step. Before anything else:

```bash
qovery environment deployment list --environment "<env>"
qovery environment deployment explain --environment "<env>" --level message   # stage, service, step and error messages
qovery environment deployment logs --environment "<env>"                         # full deployment logs
```

`explain` tells you which stage, which service and which step failed (build, push, deploy, health check). Use that to pick the right section below. Docs: <https://www.qovery.com/docs/getting-started/troubleshoot/overview>.

## Build fails

**Symptom.** "Build failed", "Dockerfile not found", dependency install errors, the build stops after 30 minutes.

**Likely causes.**
- An application-level error: a dependency install, a lockfile mismatch, a compile error. This is the most common case, and the fix is in the user's code or Dockerfile.
- Wrong **root application path** or **Dockerfile path** in the service settings, typical in monorepos.
- The build hits the build timeout (default 1,800 seconds).
- A private Git submodule the build cannot clone.
- A build secret declared with `RUN --mount=type=secret` without a literal `id=` (Qovery rejects it).

**How to check.** Find the first `ERROR` line in the build step of the deployment logs, not the last line. Compare the Dockerfile path and root path in the service **General** settings with the repository layout. Build locally with `docker build` from the same root path to reproduce.

**Fix.**
- Code or dependency errors: fix and push. Do not raise resources to work around a compile error.
- Paths: correct the root application path and Dockerfile path, then redeploy.
- Timeout: raise **Timeout (seconds)** in the service **Build settings** (for example 3600), and look at layer ordering and `.dockerignore` (hand off to `qovery-speedup` for build time work).
- Private submodules: make the submodule reachable with the credentials Qovery uses, or turn on **Skip Git submodules** in the service **Build settings** if the build does not need them. (Build settings live on their own page in the service settings, not in Advanced settings.)
- Build secrets: add `id=<VARIABLE_NAME>` to each `--mount=type=secret` line. See `reference/secrets-env.md` for how variables reach the build.

**Escalate when** the build fails before your Dockerfile runs (cloning, builder scheduling, image push) and retrying does not help.

Docs: <https://www.qovery.com/docs/getting-started/troubleshoot/overview>, <https://www.qovery.com/docs/configuration/application#build-settings>.

## Docker Hub rate limits and registry login errors

**Symptom.** `toomanyrequests`, `unauthorized` or login errors when pulling a base image from Docker Hub during the build, or when deploying a public image.

**Likely cause.** Anonymous Docker Hub pulls are rate limited and shared.

**Fix.** Add your own Docker Hub credentials as a container registry in **Organization Settings > Container Registries** (username plus a Docker Hub access token, not the account password). Authenticated pulls get a higher limit and are recommended even for public images. Docs: <https://www.qovery.com/docs/configuration/integrations/container-registries/docker-hub>.

For private base images (`FROM my-registry/...`), the registry must be declared in the organization's container registries so the build can authenticate.

## New code does not show up after deploy

**Symptom.** The deployment succeeded but the app still runs the old version.

**Likely cause.** A mutable image tag such as `latest`. Qovery mirrors images, and both the mirror and Kubernetes cache by tag, so pushing a new image under the same tag may not be pulled.

**Fix.** Use a unique tag per build (commit SHA or version), or an immutable digest. Docs: <https://www.qovery.com/docs/configuration/deployment/image-mirroring>.

## Deployment stuck, queued or "cancelling"

**Symptom.** "Deployment in progress for 30 minutes", "Queued with no status", "stuck in cancelling".

**Likely causes.**
- Another deployment is running on the same environment. Actions on an environment are queued, so a long deployment holds the others.
- The cluster cannot schedule the new pods: it is out of capacity, a spot capacity shortage, or a node pool limit is reached. The deployment waits for pods that stay Pending.
- A cluster-level problem (the cluster itself is deploying, in Warning for an AWS quota, or in Error).
- Cancellation only takes effect at safe points in the deployment pipeline, so a cancel can take a while or the step can complete before it stops.

**How to check.**
1. Cluster status first: `qovery cluster list` or the cluster overview in the Console. A **Warning** with a quota callout or an **Error** explains most stuck environments. See `reference/aws-eks.md`.
2. `qovery environment deployment list --environment "<env>"` to see what is running or queued.
3. Pod events: Pending pods with `Insufficient cpu` or `Insufficient memory` mean capacity. See `reference/kubernetes-basics.md`.

**Fix.**
- Wait for the running deployment, or cancel it: `qovery environment cancel --environment "<env>" --watch`. Cancel stops the current service and rolls it back; services already deployed in that run are not rolled back. Cancelling a lifecycle job needs the force option (`--force` in the CLI, the confirmation checkbox in the Console).
- Capacity: lower the service's CPU or memory requests, allow more instance types, or raise the node pool limits.
- A Console status that does not refresh: reload the page before assuming the deployment is stuck.

**Escalate when** a deployment stays in the same step for well over its usual duration with no pod events, or the cluster is in Error.

Docs: <https://www.qovery.com/docs/configuration/deployment/actions>, <https://www.qovery.com/docs/configuration/deployment/statuses>.

## Auto-deploy does not trigger

**Symptom.** Pushing to the branch does not start a deployment. Preview environments are not created for new pull requests.

**Likely causes.** Auto-deploy is off for the service, the push was on another branch, or the Git provider webhook was not created or failed to deliver.

**How to check.** `qovery api "application/<applicationId>"` and look for `"auto_deploy": true`. In the Console, saving the service settings shows a warning when the webhook could not be set up. On the Git provider side, open the repository webhooks and look at recent deliveries.

**Fix.** Enable auto-deploy (`qovery application update -n <app> --auto-deploy`), check that the Git token or app used by Qovery still has access to the repository, and redeliver the failed webhook from the Git provider. Docs: <https://www.qovery.com/docs/configuration/deployment/auto-deploy>.

## Preview environments

**Symptom.** "No preview for my PR", "preview created but missing a service", "previews cost too much".

**How it works.** Preview environments are enabled per environment (the blueprint) under **Environment settings > Preview Environments**, with the list of services to include. Each application in the blueprint must track the base branch the PRs target. Previews are created automatically for every PR, or on demand when someone comments `/qovery preview` on the PR. Docs: <https://www.qovery.com/docs/configuration/environment>.

**Common fixes.**
- No preview: the PR does not target the base branch configured on the blueprint's applications, the service is not selected, or the webhook did not fire (see above).
- Costs: configure auto-delete on merge or close and deployment rules that stop idle previews.
- Terraform services or jobs that create shared cloud resources: exclude them from previews, or make sure each preview creates its own isolated resources, so deleting a preview does not destroy something shared.

To set up previews end to end, hand off to `qovery-preview`.

## Lifecycle jobs and cron jobs

**Symptom.** "Where should I run my database migrations?", "my job failed without an error", "my cron job is Pending".

**Answers.**
- Run migrations and one-off tasks as a **lifecycle job** triggered on deploy, not in the application's start command. Migrations at startup delay readiness and make health checks fail. Docs: <https://www.qovery.com/docs/configuration/lifecycle-job>.
- Read job output with `qovery log --job "<name>"`. A job that exits non-zero fails the deployment step; a missing variable or a wrong command is the usual cause.
- Lifecycle jobs and cron jobs follow the same build rules as applications.
- On AWS clusters with the optional **cronjob node pool**, cron jobs must be redeployed after the node pool is enabled or disabled. Cron jobs left pointing at a disabled pool stay Pending. Docs: <https://www.qovery.com/docs/configuration/integrations/kubernetes/eks/managed#resources>.

## Known limits

- One deployment runs per environment at a time; others queue.
- There is no per-service build CPU architecture. Builds target the cluster's architecture. To ship an image for another architecture, build it in your CI and deploy it as a container image.
- Docker image tags are limited to 128 characters (Docker's limit).
