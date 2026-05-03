---
name: qovery-speedup
description: Optimize deployment speed on Qovery. Analyzes deployment timelines using the V2 deployment history API, identifies bottlenecks (build, startup, health check, scheduling, image pull), classifies them as user-controllable or Qovery infrastructure, and proposes fixes. Includes Dockerfile optimization, build cache strategies, health check tuning, deployment stage parallelism, and container image pull optimization. Generates diagnostic reports for Qovery support when the bottleneck is infrastructure-side.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: optimization
---

# Qovery Speedup Skill

You are an expert at optimizing deployment speed on Qovery. When a user reports slow deployments, follow this skill to measure exactly where time is being spent, identify the bottleneck, classify it as user-controllable or Qovery infrastructure, and either fix it or generate a diagnostic report for Qovery support.

## When to Use This Skill

Use this skill when the user says anything like:
- "My deployments are slow"
- "Speed up my Qovery deployment"
- "Why does my deployment take so long?"
- "Optimize my build time"
- "My app takes too long to start"
- "My Docker build is slow"
- "The health check keeps timing out"
- "My deployment is taking 20 minutes"
- "How can I deploy faster?"
- "My image pull is slow"
- "Can you analyze my deployment pipeline?"
- `/qovery-speedup` (slash command)

---

## Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or `new-console.qovery.com`), extract the resource IDs directly from the URL path. This immediately identifies which organization, project, environment, and service the user wants to speed up — no need to ask.

**URL format:**
```
https://{console.qovery.com|new-console.qovery.com}/organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}[/{page}]
```

**Extraction rules:**
- `orgId` — UUID after `/organization/`
- `projectId` — UUID after `/project/`
- `envId` — UUID after `/environment/`
- `serviceId` — UUID after `/service/`
- `page` — optional suffix (`deployment-logs` is especially relevant — the user is likely looking at a slow deployment)

Not every URL contains all segments. Use whatever IDs are present:
- URL with `envId` -> use it directly in the V2 deployment history API call
- URL with `serviceId` -> focus the speed analysis on that specific service
- URL with `deployment-logs` page -> the user is likely watching a slow deployment right now

**After extracting IDs, use them directly in the deployment history API:**
```bash
# Get deployment history for the environment (V2 — includes per-stage, per-service durations)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/deploymentHistory?version=v2" | jq '.results[0:5]'

# Get environment name + all services
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, name: .name, state}],
    containers: [.containers[] | {id, name: .name, state}],
    jobs: [.jobs[] | {id, name: .name, state}],
    helms: [.helms[] | {id, name: .name, state}]
  }'
```

**Use the extracted IDs directly** in all subsequent API calls — skip asking the user to identify which environment or service is slow.

---

## PHASE 1: Measure — Deployment Timeline Analysis

Before optimizing anything, MEASURE where time is actually being spent. Do NOT guess — use data.

**Shortcut:** If the user provided a Qovery Console URL, extract the environment ID and/or service ID from it using the URL Detection rules above. Use the environment ID directly in the V2 deployment history API call below, and use the service ID to focus the timeline analysis on that specific service. Skip asking "which environment/service is slow?"

### 1.1 Gather Structured Deployment History (V2 API)

The V2 deployment history API provides a complete 3-level breakdown: environment total, per-stage, and per-service — all with durations.

**Via MCP (preferred):**
```
"Show me the deployment history for {environment}"
"How long did the last deployment take?"
"What services took the longest to deploy?"
```

**Via API — V2 endpoint (primary data source):**
```bash
# Get last 5 deployments with full stage/service breakdown and durations
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/deploymentHistoryV2?pageSize=5" | jq '.results[] | {
    execution_id: .identifier.execution_id,
    status: .status,
    total_duration: .total_duration,
    trigger: .trigger_action,
    triggered_by: .auditing_data.triggered_by,
    origin: .auditing_data.origin,
    stages: [.stages[] | {
      name: .name,
      status: .status,
      duration: .duration,
      services: [.services[] | {
        name: .identifier.name,
        type: .identifier.service_type,
        status: .status,
        total_duration: .total_duration,
        build_pod_name: .details.build_pod_name
      }]
    }]
  }'
```

This returns structured data like:
```json
{
  "execution_id": "abc123-42",
  "status": "DEPLOYED",
  "total_duration": "PT12M34S",
  "stages": [
    {
      "name": "Infrastructure",
      "status": "DONE",
      "duration": "PT3M10S",
      "services": [
        {"name": "postgres", "type": "DATABASE", "total_duration": "PT3M10S"},
        {"name": "redis", "type": "HELM", "total_duration": "PT2M45S"}
      ]
    },
    {
      "name": "Backend",
      "status": "DONE",
      "duration": "PT8M42S",
      "services": [
        {"name": "backend", "type": "APPLICATION", "total_duration": "PT8M42S", "build_pod_name": "build-abc123-42-0"},
        {"name": "worker", "type": "APPLICATION", "total_duration": "PT4M20S"}
      ]
    }
  ]
}
```

IMPORTANT: Durations are in ISO 8601 format (e.g., `PT8M42S` = 8 minutes 42 seconds). Parse accordingly.

### 1.2 Generate Build Runner Usage Report

For services with a build step (applications and jobs from Git source), generate a Grafana snapshot showing CPU, memory, and network I/O during the build:

```bash
# Get the execution_id from the V2 deployment history response
# Then generate the build runner report
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploymentBuildUsageReport" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "execution_id": "{execution_id_from_v2}",
    "report_expiration_in_seconds": 86400
  }' | jq '{report_url, delete_report_url}'
```

The `execution_id` comes directly from the V2 deployment history response (`identifier.execution_id`). It is an incremental number assigned by Qovery to each deployment execution.

The returned `report_url` is a publicly accessible Grafana snapshot (expires after 24 hours) showing:
- Build pod CPU usage over time
- Build pod memory usage over time
- Build pod network I/O
- Timeline from build start to ~40 minutes after

Share this URL with the user — it's the most powerful diagnostic for build performance.

### 1.3 Parse Deployment Logs for Sub-Step Timing

The V2 API gives per-service total duration, but NOT the sub-step breakdown within a service (git clone vs build vs push vs scheduling vs startup vs health check). For that, parse the deployment logs:

**Via CLI:**
```bash
qovery log --application "name" --since 30m
```

**Via API:**
```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}/log" | jq '.results[] | .message'
```

Look for timestamped step markers in the logs:
```
[HH:MM:SS] Cloning repository...
[HH:MM:SS] Clone completed
[HH:MM:SS] Building Docker image...
[HH:MM:SS] Step 1/12: FROM node:22-alpine
...
[HH:MM:SS] Build completed
[HH:MM:SS] Pushing image...
[HH:MM:SS] Push completed
[HH:MM:SS] Deploying to Kubernetes...
[HH:MM:SS] Pod scheduled
[HH:MM:SS] Container started
[HH:MM:SS] Readiness probe passed
[HH:MM:SS] Service is running
```

Calculate the time between each step to build the sub-step timeline.

### 1.4 Compare Across Deployments

Analyze the last 5-10 deployments to establish a baseline and detect trends:

```
Deployment History Comparison:
| # | Date       | Total   | Slowest Stage    | Slowest Service | Status    |
|---|------------|---------|------------------|-----------------|-----------|
| 5 | 2025-04-20 | 12m 34s | Backend (8m 42s) | backend (8m 42s)| DEPLOYED  |
| 4 | 2025-04-19 | 11m 22s | Backend (7m 50s) | backend (7m 50s)| DEPLOYED  |
| 3 | 2025-04-18 | 14m 10s | Backend (10m 5s) | backend (10m 5s)| DEPLOYED  |
| 2 | 2025-04-17 | 6m 45s  | Backend (4m 12s) | backend (4m 12s)| DEPLOYED  |
| 1 | 2025-04-15 | 6m 30s  | Backend (4m 05s) | backend (4m 05s)| DEPLOYED  |
```

Questions to answer:
- **Is deployment time getting worse over time?** (growing codebase, more dependencies)
- **Was there a specific deployment where it jumped?** (what commit/change caused it?)
- **Are some services consistently slower than others?** (focus optimization there)
- **Is the total time dominated by one stage or spread across many?** (serial vs parallel issue)

### 1.5 Present the Timeline

Generate a clear timeline visualization for the user:

```
Deployment Pipeline for environment "production" (last deployment: 12m 34s)

Stage: Infrastructure (3m 10s)
  ├── postgres (DATABASE)     3m 10s  [Qovery managed]
  └── redis (HELM)            2m 45s  [Qovery managed]

Stage: Backend (8m 42s)                              ← SLOWEST STAGE
  ├── backend (APPLICATION)   8m 42s  [has build]    ← SLOWEST SERVICE
  │   ├── Git clone:          0m 08s  (1%)
  │   ├── Docker build:       6m 15s  (72%)          ← BOTTLENECK
  │   ├── Image push:         0m 35s  (7%)
  │   ├── Pod scheduling:     0m 18s  (3%)
  │   ├── App startup:        1m 06s  (13%)
  │   └── Health check:       0m 20s  (4%)
  └── worker (APPLICATION)    4m 20s  [has build]

Stage: Frontend (5m 15s)
  └── frontend (APPLICATION)  5m 15s  [has build]

Stage: Jobs (1m 30s)
  └── db-migrate (JOB)        1m 30s  [lifecycle]

Total: 12m 34s (stages run sequentially as configured)
```

This timeline is the foundation for everything that follows. Present it to the user before proposing any changes.

---

## PHASE 2: Classify — User vs Qovery

Based on the timeline analysis, classify each bottleneck into who can fix it:

### Classification Table

| Step | Typical Time | Slow If > | Owner | User Can Fix? |
|---|---|---|---|---|
| **Queue time** | 5-30s | 2 min | Qovery | No — contact support |
| **Git clone** | 5-15s | 30s | Mixed | Yes if repo is huge (large files, no `.gitignore`) |
| **Docker build** | 1-10 min | 5 min | User (usually) | Yes — optimize Dockerfile (see Phase 3.1) |
| **Build runner resources** | N/A | CPU at 100% | Qovery | No — contact support for larger build runner |
| **Image push** | 15-60s | 2 min | Mixed | Smaller images help; registry infra is Qovery |
| **Image pull** (containers) | 10-60s | 2 min | Mixed | Smaller images help; registry proximity is Qovery |
| **Pod scheduling** | 10-30s | 2 min | Mixed | Reduce resource requests if too high; Karpenter is Qovery |
| **App startup** | 2-30s | 2 min | User | Yes — optimize startup code, use lifecycle jobs for migrations |
| **Health check** | 5-30s | 1 min | User | Yes — tune probe config (see Phase 3.4) |
| **Deployment stage ordering** | N/A | N/A | User | Yes — parallelize independent services |

### Decision Tree

```
For each bottleneck identified in Phase 1:

Is it user-controllable?
├── YES (Docker build, app startup, health check, stage ordering, image size)
│   └── Go to Phase 3 → diagnose deeper → Phase 4 → fix
│
├── MIXED (git clone, image push/pull, pod scheduling)
│   ├── User part: optimize what you can (image size, resource requests, .gitignore)
│   └── Qovery part: if still slow after user optimizations → Phase 5 → support
│
└── NO (queue time, build runner capacity, registry infra, Karpenter node provisioning)
    └── Go to Phase 5 → generate diagnostic report → contact Qovery support
```

---

## PHASE 3: Diagnose — Deep Analysis of Bottlenecks

### 3.1 Docker Build Optimization (Most Common Bottleneck)

Analyze the user's Dockerfile and build logs to identify waste. This is where the biggest gains are.

**Step 1: Read the Dockerfile**

Examine the Dockerfile and identify anti-patterns:

| Anti-Pattern | Detection | Fix | Impact |
|---|---|---|---|
| **No layer caching — `COPY . .` before dependency install** | `COPY . .` appears before `npm install` / `pip install` / `go mod download` | Reorder: copy lockfiles first, install deps, then copy code. Deps layer is cached when only code changes. | **HIGH — saves 50-80% of build time** |
| **No `.dockerignore`** | `.dockerignore` file missing or incomplete | Create one: exclude `.git`, `node_modules`, `__pycache__`, `dist`, `build`, `.env`, `*.md` | **HIGH — reduces build context from GBs to MBs** |
| **No multi-stage build** | Single `FROM` statement, build tools in final image | Convert to multi-stage: build in one stage, copy artifacts to minimal runtime stage | **MEDIUM — smaller image = faster push/pull** |
| **Dev dependencies included** | `npm install` instead of `npm ci --omit=dev` | Use `npm ci --omit=dev` (Node), `pip install --no-dev` (Python), `-DskipTests` (Maven) | **MEDIUM — faster install, smaller image** |
| **Large base image** | `FROM node:22` (~1GB) or `FROM python:3.13` (~900MB) | Switch to alpine/slim: `node:22-alpine` (~180MB), `python:3.13-slim` (~150MB) | **MEDIUM — faster pull, less to build on** |
| **Redundant RUN layers** | Multiple `RUN apt-get update && apt-get install` | Combine into single `RUN` with `&&` | **LOW-MEDIUM — fewer layers** |
| **No build cache mounts** | Dependencies re-downloaded on every build even when unchanged | Use `--mount=type=cache` for package manager caches | **HIGH — near-instant dependency installs on cache hit** |
| **Large files in build context** | `.git` directory (can be hundreds of MB), data files, media | Add to `.dockerignore` | **HIGH — context upload is a hidden time sink** |
| **Tests running in build** | `RUN npm test` or `RUN pytest` in Dockerfile | Move tests to CI pipeline (GitHub Actions, GitLab CI), not Docker build | **MEDIUM — testing should be separate** |
| **Downloading during build** | `RUN curl ... | RUN wget ...` downloading large files | Pre-bake into base image or use multi-stage with a download stage | **MEDIUM — network I/O during build is slow** |

**Step 2: Propose optimized Dockerfile**

For each anti-pattern found, show the user the exact before/after change. Here are the key patterns:

**Optimal layer ordering (the single biggest win):**

```dockerfile
# BAD — every code change invalidates the dependency cache
FROM node:22-alpine
WORKDIR /app
COPY . .                    # ← This invalidates everything below on ANY code change
RUN npm install             # ← Re-installs ALL dependencies every time
RUN npm run build

# GOOD — dependencies are cached, only code changes trigger rebuild
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./    # ← Only changes when deps change
RUN npm ci --omit=dev                      # ← Cached layer when deps haven't changed
COPY . .                                   # ← Only code changes trigger from here
RUN npm run build
```

**Build cache mounts (advanced — near-instant dependency installs):**

```dockerfile
# Node.js — cache npm modules across builds
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# Python — cache pip packages
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# Go — cache Go modules
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Maven — cache .m2 repository
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw package -DskipTests -B

# Gradle — cache Gradle home
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew bootJar --no-daemon -x test
```

**Multi-stage builds (smaller final image = faster push + pull):**

```dockerfile
# Build stage — has all build tools, dev deps, compilers
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage — minimal, only production artifacts
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist
CMD ["node", "dist/index.js"]
```

**Optimal `.dockerignore`:**

```dockerignore
.git
.gitignore
.env
.env.*
*.md
LICENSE
docker-compose*.yml
Dockerfile
.dockerignore
node_modules
.next
dist
build
coverage
.nyc_output
__pycache__
*.pyc
.venv
venv
.pytest_cache
target
.gradle
.idea
.vscode
*.swp
```

### 3.2 Build Runner Resource Analysis

Use the Grafana snapshot from Phase 1.2 to check if the build runner is resource-constrained:

| Observation | Meaning | Action |
|---|---|---|
| CPU at 100% throughout build | Build runner CPU-bound | Contact Qovery support — needs larger build runner |
| Memory near limit / OOM | Build runner memory-bound | Contact Qovery support — needs more memory |
| CPU/memory well within limits | Build runner is fine — Dockerfile is the bottleneck | Focus on Dockerfile optimization (Phase 3.1) |
| Network I/O spikes | Downloading large dependencies | Use build cache mounts, pre-bake dependencies |

Share the Grafana snapshot URL with the user:
> "Here's the build runner resource usage for your last deployment: {report_url}
> It shows CPU, memory, and network I/O during the build. The snapshot expires in 24 hours."

### 3.3 Application Startup Optimization

If the app startup is the bottleneck (time between container starting and health check passing):

| Pattern | Detection (from logs) | Fix | Auto-Fix? |
|---|---|---|---|
| **JVM cold start** | `Started ... in X seconds` with X > 30 | Use CDS (Class Data Sharing), Spring AOT, or GraalVM native image; or accept it and increase `initial_delay_seconds` | ASK (code change) / YES (probe config) |
| **Database migrations on start** | Migration logs during startup | Move migrations to a lifecycle job (runs once per deploy, not per pod) | ASK |
| **Downloading assets on start** | HTTP download logs during startup | Pre-bake assets into the Docker image at build time | ASK |
| **Loading large ML models** | Model loading logs, several minutes | Pre-bake model into image, or use init container, or increase startup probe timeout | ASK |
| **Waiting for dependencies** | Retry/connection logs to DB/Redis | Ensure deployment stages order dependencies first; add retry logic with exponential backoff | YES (stages) / ASK (code) |
| **Expensive initialization** | Custom init code (warming caches, pre-computing) | Defer non-critical initialization to after health check passes; use readiness probe to signal when ready | ASK |
| **Slow DNS resolution** | DNS timeout logs | Check if `ndots` configuration is causing excessive DNS lookups (common in K8s) | Contact Qovery support |

**Measure actual startup time:**

```bash
# Port-forward and time the first successful response
qovery port-forward --service "name" --port 8080:8080
time curl http://localhost:8080/health
# The time from container start to first successful health response = actual startup time
```

### 3.4 Health Check Tuning

Health check misconfiguration is one of the easiest wins — pure Qovery config changes, no code needed.

**Get current health check config:**

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/application/{appId}" | jq '.healthchecks'
```

**Common misconfigurations and fixes:**

| Problem | Detection | Optimal Config | Auto-Fix? |
|---|---|---|---|
| `initial_delay_seconds` too high | App starts in 5s but delay is 120s — wasting 115s | Set to `actual_startup_time + 10s` | YES |
| `initial_delay_seconds` too low | App starts in 60s but delay is 10s — probe fails, pod restarts | Set to `actual_startup_time + 30s` | YES |
| `period_seconds` too high | Probes every 30s — slow readiness detection | Set to 5-10s | YES |
| `failure_threshold` too low | Set to 1 — single slow response kills the pod | Set to 3-5 | YES |
| `timeout_seconds` too low | Set to 1s but health endpoint needs 3s | Set to 5s, or optimize the health endpoint | YES |
| HTTP probe on slow endpoint | `/health` queries database, takes 3s | Create lightweight `/healthz` that returns 200 immediately | ASK (code change) |
| No readiness probe | Only liveness — Kubernetes sends traffic before app is ready | Add readiness probe (same endpoint, lower `initial_delay_seconds`) | YES |

**Optimal health check config by framework:**

| Framework | Typical Startup | Recommended `initial_delay_seconds` | Health Endpoint |
|---|---|---|---|
| Node.js (Express/Fastify) | 1-5s | 10s | `/health` |
| Next.js | 3-10s | 15s | `/` or `/api/health` |
| Python (Flask/FastAPI) | 2-5s | 10s | `/health` |
| Python (Django) | 5-15s | 20s | `/health` |
| Go | 1-3s | 5s | `/health` |
| Java (Spring Boot) | 15-60s | 60-120s | `/actuator/health` |
| Ruby (Rails) | 10-30s | 30s | `/health` |
| .NET | 5-15s | 20s | `/health` |

**Fix health check via API (auto-fix):**

```bash
# Tune health check timing based on actual startup time
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "healthchecks": {
      "readiness_probe": {
        "type": {"http": {"port": 8080, "scheme": "HTTP", "path": "/health"}},
        "initial_delay_seconds": 10,
        "period_seconds": 5,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      },
      "liveness_probe": {
        "type": {"http": {"port": 8080, "scheme": "HTTP", "path": "/health"}},
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    }
  }'
```

### 3.5 Pod Scheduling Optimization

If Kubernetes takes >2 min to schedule the pod:

| Cause | Detection | Fix | Owner |
|---|---|---|---|
| **No available nodes** | Karpenter provisioning new node (~2 min) | Expected on first deploy or scale-up. Diversify instance types in Karpenter for faster matching. | Qovery (cluster config) |
| **Resource requests too high** | Pod requests 4 CPU + 8GB but workload uses 500m + 512MB | Right-size resource requests (see qovery-optimize skill) | User — auto-fix |
| **Node startup time** | New EC2/GCE instance takes 2-3 min to join cluster | Expected. Keep at least 1-2 warm nodes by setting `min_running_instances >= 1` | Mixed |
| **Image pull slow** | Large image (>1GB) pulling from remote registry | See Phase 3.6 (Container Image Optimization) | User (image size) |
| **Anti-affinity/topology rules** | Pod can't be scheduled due to spread constraints | Review pod anti-affinity rules | Qovery/User |

### 3.6 Container Image Pull Optimization

For services using pre-built images from a container registry (not Git-based builds), the image pull is often the bottleneck.

**Image size benchmarks:**

| Size | Pull Time (typical) | Rating |
|---|---|---|
| < 100MB | 5-15s | Excellent |
| 100-500MB | 15-45s | Good |
| 500MB-1GB | 45-90s | Needs optimization |
| > 1GB | 90-180s+ | Bad — optimize immediately |

**Optimization strategies:**

| Strategy | Impact | How |
|---|---|---|
| **Use alpine/slim base images** | -50-80% image size | `FROM node:22-alpine` instead of `FROM node:22` |
| **Multi-stage builds** | -50-80% | Build in one stage, copy only artifacts to runtime stage |
| **Remove unnecessary files** | -10-30% | Delete temp files, caches, docs in final stage |
| **Use `.dockerignore`** | -10-50% context size | Exclude `.git`, `node_modules`, test files |
| **Minimize layers** | -5-10% | Combine RUN commands, clean up in same layer |
| **Share base layers** | -20-50% pull time | Use the same base image for multiple services (layers are cached on nodes) |
| **Use Qovery's built-in registry** | Faster pulls | Images built by Qovery are already in a registry close to the cluster |

**Check current image size:**

```bash
# For container services, check the tag and image size in the registry
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/container/{containerId}" | jq '{image_name, tag}'

# Check image size locally (if you have Docker)
docker pull {image}:{tag}
docker images {image}:{tag} --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```

**Layer sharing optimization:**

If you have multiple services using different base images, standardize on one:
```
BEFORE:
  backend:  FROM node:22 (1GB)
  frontend: FROM node:22-slim (200MB)
  worker:   FROM node:20 (1GB)

AFTER (shared base = node:22-alpine pulled once, cached on every node):
  backend:  FROM node:22-alpine (180MB)
  frontend: FROM node:22-alpine (180MB)
  worker:   FROM node:22-alpine (180MB)
```

### 3.7 Deployment Stage Parallelism

If the environment has multiple deployment stages running serially, check if independent services can be parallelized:

**Get current stage configuration:**

The V2 deployment history already shows stages and their durations. Check if services in different stages are actually independent.

```
CURRENT (serial — everything sequential):
  Stage 1: Database (3m)
  Stage 2: Backend (8m)
  Stage 3: Frontend (5m)
  Stage 4: Jobs (1m 30s)
  Total: 17m 30s

OPTIMIZED (parallel where possible):
  Stage 1: Database (3m)              — must be first (backend depends on it)
  Stage 2: Backend + Frontend (8m)    — frontend doesn't depend on backend at DEPLOY time
  Stage 3: Jobs (1m 30s)             — migration depends on backend
  Total: 12m 30s (saved 5m — 29% improvement!)
```

**Rules for parallelization:**
- Services that DON'T depend on each other can be in the SAME stage
- Databases MUST be in an earlier stage than apps that connect to them
- Lifecycle jobs that run migrations MUST be after the backend (same or later stage)
- Frontends often DON'T depend on backends at deploy time (they connect at runtime via env vars)

**Fix via API (auto-fix — move services to same stage):**

```bash
# Move frontend to the same stage as backend (they're independent at deploy time)
curl -s -X PUT "https://api.qovery.com/application/{frontendId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"deployment_stage_id": "{backendStageId}"}'
```

---

## PHASE 4: Fix & Verify

### 4.1 Auto-Fix Rules

Same rules as other Qovery skills:

**AUTO-FIX ALLOWED (no permission needed):**
- Health check timing (`initial_delay_seconds`, `period_seconds`, `failure_threshold`, `timeout_seconds`)
- Health check type switching (HTTP to TCP)
- Deployment stage reordering / merging (parallelizing independent services)
- `.dockerignore` creation
- Resource request adjustments (if over-requested)

**MUST ASK USER BEFORE FIXING:**
- Any Dockerfile modifications (even optimizations — it's user code)
- Application startup code changes (moving migrations, deferring init)
- Adding build cache mounts to Dockerfile
- Creating a new lightweight health endpoint
- Changing base images
- Any change to user code

**WHEN ASKING, always:**
1. Show the current Dockerfile / code section
2. Show the proposed change with before/after diff
3. Explain the expected time saving
4. Wait for explicit approval

### 4.2 Apply Fixes and Re-Measure

After applying fixes:

1. **Trigger a new deployment:**
   ```bash
   curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
     -H "Authorization: Token $QOVERY_API_TOKEN"
   # Or via MCP: "Redeploy the production environment"
   # Or via CLI: qovery environment deploy
   ```

2. **Wait for it to complete and gather the new timeline:**
   ```bash
   # Wait, then fetch the latest deployment from V2 history
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/environment/{envId}/deploymentHistoryV2?pageSize=1" | jq
   ```

3. **Compare before vs after:**
   ```
   Deployment Speed Improvement:

   | Step          | Before  | After   | Saved   | Improvement |
   |---------------|---------|---------|---------|-------------|
   | Docker Build  | 8m 42s  | 2m 15s  | 6m 27s  | 74%         |
   | App Startup   | 1m 50s  | 1m 50s  | —       | —           |
   | Health Check  | 1m 30s  | 0m 20s  | 1m 10s  | 78%         |
   | Stage Parallel| —       | —       | 5m 00s  | 29%         |
   | TOTAL         | 17m 30s | 5m 15s  | 12m 15s | 70%         |
   ```

4. **Present results to the user** with clear before/after comparison.

---

## PHASE 5: Qovery Support Escalation

If the bottleneck is on Qovery's infrastructure side, generate a diagnostic report and offer to share with support.

### 5.1 When to Escalate

Escalate to Qovery support when:
- **Queue time >2 min** consistently
- **Build runner CPU at 100%** — needs larger build runner allocation
- **Build runner memory near limit** — risk of OOM during build
- **Image push takes >2 min** with a reasonably-sized image (<500MB)
- **Pod scheduling >2 min** consistently even with right-sized resource requests
- **Karpenter not provisioning nodes** in a timely manner

### 5.2 Generate Diagnostic Report

Save to `.qovery/reports/YYYY-MM-DD-deployment-speed.md`:

```markdown
# Deployment Speed Diagnostic Report

**Date:** YYYY-MM-DD
**Service:** {name}
**Environment:** {name}
**Cluster:** {name} ({cloud_provider}, {region})

## Timeline Analysis (Last 5 Deployments)

| # | Date | Total | Queue | Build | Push | Schedule | Startup | Health | Status |
|---|------|-------|-------|-------|------|----------|---------|--------|--------|
| 5 | 4/20 | 12:34 | 0:15  | 8:42  | 0:45 | 0:22     | 1:50    | 0:32   | OK     |
| 4 | 4/19 | 11:22 | 0:10  | 7:50  | 0:40 | 0:20     | 1:45    | 0:30   | OK     |
| 3 | 4/18 | 14:10 | 0:18  | 10:05 | 0:50 | 0:25     | 1:50    | 0:32   | OK     |
| 2 | 4/17 | 6:45  | 0:12  | 4:12  | 0:35 | 0:18     | 1:20    | 0:28   | OK     |
| 1 | 4/15 | 6:30  | 0:10  | 4:05  | 0:30 | 0:15     | 1:20    | 0:30   | OK     |

## Identified Bottleneck

**Step:** {step name}
**Owner:** Qovery infrastructure
**Details:** {specific diagnosis — e.g., "Build runner CPU consistently at 100% throughout the 8-minute build. The Grafana snapshot confirms CPU saturation. Dockerfile has already been optimized (proper layer ordering, .dockerignore, multi-stage build, cache mounts)."}

## Build Runner Usage Report

**Grafana Snapshot URL:** {report_url from API}
*(Expires in 24 hours — please review before expiration)*

## User-Side Optimizations Already Applied

- [x] Dockerfile layer ordering optimized
- [x] .dockerignore configured
- [x] Multi-stage build in place
- [x] Build cache mounts added
- [x] Health check timing tuned
- [x] Deployment stages parallelized

## Recommendation

Please review the build runner CPU/memory allocation for cluster "{cluster_name}" in region {region}. The current build runner resources appear insufficient for this application's build requirements.

## Service Configuration

- Build mode: DOCKER
- Dockerfile: {path}
- CPU: {cpu}m
- Memory: {memory}MB
- Instances: {min}-{max}
- Health check: {type} on port {port}, path {path}, initial_delay {delay}s
```

### 5.3 Offer to Contact Qovery Support

> "The bottleneck is on Qovery's infrastructure side ({specific step}). I've generated a diagnostic report at `.qovery/reports/YYYY-MM-DD-deployment-speed.md` with timeline data, the build runner Grafana snapshot, and details about what's been optimized on your side.
>
> Would you like to share this report with Qovery support? They can:
> - Increase build runner CPU/memory allocation
> - Optimize registry push performance
> - Review Karpenter configuration for faster node provisioning
> - Investigate queue delays
>
> Contact them at:
> - **Email:** support@qovery.com (attach the report)
> - **Qovery Console:** In-app chat support
> - **Community Forum:** https://discuss.qovery.com"

---

## PHASE 6: Deployment Speed Targets & Ongoing Monitoring

### 6.1 What's a Reasonable Deployment Time?

| Application Type | Good | Acceptable | Needs Optimization |
|---|---|---|---|
| Simple Node.js/Go app (small codebase) | 1-3 min | 3-5 min | >5 min |
| React/Vite SPA (frontend) | 2-4 min | 4-7 min | >7 min |
| Next.js (SSR + build) | 3-6 min | 6-10 min | >10 min |
| Python (Flask/FastAPI/Django) | 1-4 min | 4-7 min | >7 min |
| Java (Spring Boot, Maven) | 3-8 min | 8-12 min | >12 min |
| Java (Spring Boot, Gradle) | 2-6 min | 6-10 min | >10 min |
| Go (compiled binary) | 1-3 min | 3-5 min | >5 min |
| .NET (ASP.NET Core) | 2-5 min | 5-8 min | >8 min |
| Container from registry (no build) | 30s-2 min | 2-4 min | >4 min |
| Helm chart | 1-5 min | 5-10 min | >10 min |
| Terraform service | 2-10 min | 10-20 min | Depends on resources |

### 6.2 Save Benchmark Report

Save the analysis to `.qovery/reports/YYYY-MM-DD-deployment-speed.md` for future comparison:

```bash
# Ask user if they want to commit
git add .qovery/reports/
git commit -m "docs: add deployment speed analysis YYYY-MM-DD"
```

### 6.3 When to Re-Analyze

Suggest re-running this analysis when:
- Adding significant new dependencies (larger `node_modules`, new Maven deps)
- Upgrading frameworks (new Next.js version, Spring Boot upgrade)
- Changing Dockerfiles
- Adding new services to the environment
- After Qovery cluster upgrades
- When deployment time noticeably regresses

### 6.4 Continuous Improvement Checklist

After optimization, provide the user with a checklist for maintaining fast deployments:

```markdown
## Deployment Speed Maintenance Checklist

- [ ] Dockerfile has proper layer ordering (lockfiles first, then code)
- [ ] .dockerignore excludes .git, node_modules, build artifacts
- [ ] Multi-stage build separates build and runtime
- [ ] Alpine/slim base images used where possible
- [ ] Dependencies installed with --production/--omit=dev flags
- [ ] Build cache mounts used for package manager caches
- [ ] Health check initial_delay_seconds matches actual startup time + buffer
- [ ] Both readiness and liveness probes configured
- [ ] Independent services are in the same deployment stage
- [ ] Database is in an earlier stage than the apps that need it
- [ ] No tests running inside Docker build (moved to CI)
- [ ] No large file downloads during app startup
- [ ] Database migrations run as lifecycle job, not during app startup
```

---

## Quick Reference

### MCP Queries for Deployment Speed

```
"Show me deployment history for {environment}"
"How long did the last deployment take?"
"What services took the longest to deploy?"
"Show build logs for {service}"
"Why is my deployment slow?"
```

### API Endpoints

```bash
# V2 Deployment History (primary — structured timing data)
GET /environment/{envId}/deploymentHistoryV2?pageSize=5

# Build Runner Usage Report (Grafana snapshot)
POST /environment/{envId}/deploymentBuildUsageReport
  Body: {"execution_id": "...", "report_expiration_in_seconds": 86400}

# Per-Service Deployment History
GET /application/{appId}/deploymentHistory
GET /container/{containerId}/deploymentHistory
GET /job/{jobId}/deploymentHistory
GET /helm/{helmId}/deploymentHistory

# Service Configuration (health checks, resources)
GET /application/{appId}
PUT /application/{appId}

# Application Logs (for sub-step timing)
GET /application/{appId}/log

# Deployment Stage Management
GET /environment/{envId}/deploymentStage
PUT /application/{appId} (change deployment_stage_id)
```

### CLI Commands

```bash
qovery status                                    # Current deployment status
qovery log --application "name" --since 30m      # Deployment logs
qovery port-forward --service "name" --port X:X  # Test startup locally
qovery service list                              # All services overview
```

---

## Reference Links

- **Deployment History Docs**: https://www.qovery.com/docs/configuration/deployment/history
- **Deployment Logs Docs**: https://www.qovery.com/docs/configuration/deployment/logs
- **Deployment Pipeline Docs**: https://www.qovery.com/docs/configuration/deployment/pipeline
- **Build Optimization**: https://www.qovery.com/docs/getting-started/guides/qovery-101/optimize
- **V2 Deployment History API**: `GET /environment/{envId}/deploymentHistoryV2`
- **Build Usage Report API**: `POST /environment/{envId}/deploymentBuildUsageReport`
- **Qovery Deploy Skill**: https://github.com/Qovery/qovery-skills (for creating optimized Dockerfiles during deployment)
- **Qovery Troubleshoot Skill**: https://github.com/Qovery/qovery-skills (for fixing deployment failures)
- **Qovery Optimize Skill**: https://github.com/Qovery/qovery-skills (for cost optimization)
- **Qovery Support**: support@qovery.com
