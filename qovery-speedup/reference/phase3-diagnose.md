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

