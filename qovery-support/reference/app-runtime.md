# App runtime: crashes, memory and health probes

Covers containers that crash, restart or never become ready. For a live diagnosis of one failing service (logs, events, applying a fix), hand off to `qovery-troubleshoot`.

## Contents

- Health checks fail during deployment
- Connection refused on the health check
- OOMKilled, exit code 137
- CrashLoopBackOff
- Container exits with code 0
- 503 or dropped requests during a rollout
- Debug a container that crashes too fast to inspect
- Alert names

## Health checks fail during deployment

**Symptom.** The deployment fails at the health check step; logs show `Readiness probe failed` or `Liveness probe failed`; pods restart during startup; the deployment is rolled back.

**Likely causes.**
- The app takes longer to start than the probe allows: framework warm-up, large caches, CPU-heavy initialization, or database migrations run at boot. This is the most common cause.
- The probe targets the wrong port or path, or the health endpoint does real work (database calls) and times out under load.
- The CPU request is so low that startup is throttled.

**How to check.** In the service **Health checks** settings, compare type, port, path and initial delay with what the app actually does. Time a cold start locally or in the logs (`qovery log --service "<name>"`): if the app logs "listening" after 90 seconds and the probe starts failing at 30, that is the answer. Docs: <https://www.qovery.com/docs/configuration/service-health-checks>.

**Fix, in this order.**
1. Add a **startup probe**: the **Startup** column of the service's health check settings in the Console, or `healthchecks.startup_probe` in the API, for applications, containers and jobs. Kubernetes runs readiness and liveness only once the startup probe succeeds, so a slow start no longer trips the liveness probe. With the Console defaults (period 10 s, failure threshold 30), the service gets about 5 minutes to start. Raising the **initial delay** of the readiness and liveness probes also works, but it delays every restart too.
2. Move database migrations and other one-off work to a lifecycle job (see `reference/deployments-builds.md`).
3. Make the health endpoint cheap: return 200 when the process can serve, without calling downstream dependencies.
4. If startup is CPU-bound, raise the CPU allocation.

**Confirm.** Redeploy and watch the health check step pass; pods stay Running without restarts.

## Connection refused on the health check

**Symptom.** `dial tcp ...: connect: connection refused` in probe events.

**Likely causes.** The port declared in Qovery differs from the port the app listens on, or the app binds to `localhost` / `127.0.0.1` instead of `0.0.0.0`.

**Fix.** Make the service port match the listening port, and bind to `0.0.0.0`. Many frameworks default to `localhost` in development mode. Docs: <https://www.qovery.com/docs/getting-started/troubleshoot/overview>.

## OOMKilled, exit code 137

**Symptom.** `OOMKilled`, `exit code 137`, `SIGKILL`, restarts under load, sometimes nothing in the app logs because the kernel kills the process.

**Likely cause.** The container's memory use exceeded its memory limit. Kubernetes kills the container. Peaks (batch jobs, large requests, a cache that grows) matter more than the average.

**How to check.** Look at the memory graph of the service around the restart time, in the Console monitoring view when your plan includes it or in your own observability tool, and compare peak usage with the configured memory.

**Fix.**
- Raise the memory of the service to cover the peak plus headroom, then redeploy.
- If usage grows steadily until the kill, it is a leak: increasing memory only delays it.
- For runtimes with their own heap settings (JVM, Node.js), make sure the heap limit stays below the container memory.
- With several instances, check that the load is actually spread; one hot instance can be killed while others are idle.

To size memory from real usage across services, hand off to `qovery-optimize`.

## CrashLoopBackOff

**Symptom.** The pod status is `CrashLoopBackOff`; the service keeps restarting.

**Likely causes.** The process exits on startup: a missing environment variable, a wrong command or entrypoint, a dependency it cannot reach (database, cache), an OOM kill, or a failing liveness probe.

**How to check.** Read the logs of the previous container run, which hold the error that caused the exit: `qovery log --service "<name>"`. Look at the exit code in the pod events: 137 is memory, 1 or another non-zero code is the app, 0 is the next section.

**Fix.** Fix what the log says. For missing variables see `reference/secrets-env.md`; for unreachable databases see `reference/databases.md`.

## Container exits with code 0

**Symptom.** "My backend crashes but there is no error", the container stops with exit code 0 and restarts.

**Likely cause.** The container's main process finishes. A service in Qovery must run a long-lived process (a web server, a worker loop). A script that runs and returns, or a command that starts a server in the background and exits, makes Kubernetes restart the container.

**Fix.** Run the server in the foreground as the container's main process. If the work is meant to run once, deploy it as a lifecycle job or a cron job instead.

## 503 or dropped requests during a rollout

**Symptom.** Short bursts of 503 errors or dropped connections during each deployment, or when nodes are replaced.

**Likely causes.** A single instance (no redundancy during the rollout), readiness that reports ready before the app can serve, or the app exiting immediately on SIGTERM while requests are in flight.

**Fix.**
- Run at least 2 instances for anything user-facing.
- Make readiness reflect real readiness.
- Handle SIGTERM gracefully and give the pod time with the `deployment.termination_grace_period_seconds` advanced setting. A `deployment.lifecycle.pre_stop_exec_command` (for example a short sleep) lets the load balancer stop routing before the process exits.
- The default rolling update keeps old pods until new ones are ready. Use the `Recreate` strategy only when two versions must never run together. Docs: <https://www.qovery.com/docs/configuration/deployment/strategies>.

## Debug a container that crashes too fast to inspect

`qovery shell --ephemeral --mode clone --service "<name>"` (with `--organization`, `--project` and `--environment`, or a Console URL) starts a separate pod from the same image, variables, secrets and service account, running `sleep infinity` instead of the entrypoint, and receiving no traffic. Start the app by hand inside it and read the error. `--mode debug` attaches a debug container to a running pod instead. Both need the **Shell** permission. Docs: <https://www.qovery.com/docs/cli/commands/shell>.

## Alert names

- In Qovery alerting, an alert named **Instance restart** means a container restarted inside a running pod (crash, failed liveness probe, OOM kill), while **Missing instance** means a pod disappeared (evicted, deleted, or its node was removed).
