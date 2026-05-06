## PHASE 10: Troubleshooting & Auto-Fix

When a deployment fails, follow this phase to diagnose the issue, classify it, and either fix it automatically or ask the user for permission.

### CRITICAL RULE: What You Can and Cannot Fix Automatically

You MUST follow this rule strictly:

**AUTO-FIX ALLOWED (no permission needed):**
- Qovery service configuration: port numbers, health check paths, memory/CPU limits, deployment stage ordering, environment variables (non-secret), Dockerfile path, git branch, root_path, build_mode, instance counts
- Dockerfiles that YOU created during this session (Phase 3) — you are responsible for them
- .dockerignore files that YOU created
- next.config.js `output: 'standalone'` addition (required for Next.js Dockerfile you created)
- Adding gunicorn/uvicorn to requirements.txt if YOU created the Dockerfile that references them

**MUST ASK USER BEFORE FIXING:**
- Any changes to the user's application source code (fixing a bug, adding an import, changing a config)
- Any changes to a Dockerfile that already existed before you started (you did NOT create it)
- Adding, changing, or removing environment variables that contain secrets or sensitive values
- Changes to the user's database schema or migration files
- Changes to the user's package.json, go.mod, pom.xml, or other dependency files (unless you created the Dockerfile that requires a specific dependency like gunicorn)
- Any change where you are not 100% certain it will fix the issue

**WHEN ASKING, always:**
1. Explain the error clearly (quote the relevant log lines)
2. Explain what you think the root cause is
3. Show the exact change you propose
4. Wait for explicit approval before making the change

### 10.1 Error Classification & Diagnosis

Analyze the logs fetched in Phase 9.3 and classify the error:

#### BUILD_ERROR — Docker Build Failed

**Symptoms:** Service status is `BUILD_ERROR`. Build logs show Docker build output with an error.

**Common causes and fixes:**

| Log Pattern | Cause | Fix | Auto-Fix? |
|---|---|---|---|
| `Dockerfile not found` or `Cannot locate specified Dockerfile` | Wrong `dockerfile_path` in Qovery config | Update `dockerfile_path` via API: `PATCH /application/{appId}` with `{"dockerfile_path": "Dockerfile"}` | YES |
| `COPY failed: file not found` | File referenced in Dockerfile doesn't exist, or wrong `root_path` | Check if `root_path` is correct. If Dockerfile was created by you, fix the COPY path. | YES if your Dockerfile, ASK if user's |
| `npm ERR! Could not resolve dependency` or `pip install ... ERROR` | Dependency install failure | This is a code/dependency issue | ASK USER — explain which dependency failed |
| `RUN npm run build` fails with compilation errors | TypeScript/build errors in user code | This is a code issue | ASK USER — show the build errors |
| Base image not found (e.g., `manifest unknown`) | Wrong base image tag in Dockerfile | Fix the base image tag if you created the Dockerfile | YES if your Dockerfile |
| `no space left on device` | Disk too small for build | Increase disk size on cluster or optimize Dockerfile | YES — optimize Dockerfile layers |

**How to fix `dockerfile_path` via API:**
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"dockerfile_path": "Dockerfile"}'
```

#### DEPLOYMENT_ERROR — Container Fails to Start or Health Check Fails

**Symptoms:** Service status is `DEPLOYMENT_ERROR`. The Docker image built successfully, but the container crashes or never becomes healthy.

**Common causes and fixes:**

| Log Pattern | Cause | Fix | Auto-Fix? |
|---|---|---|---|
| `CrashLoopBackOff` + app error in logs | Application crashes on startup | Read the crash logs to identify the issue | DEPENDS — see below |
| No logs at all + `DEPLOYMENT_ERROR` | Health check fails before app starts | Increase `initial_delay_seconds` in health check, or fix the health check path | YES — Qovery config |
| `listening on port 3000` but health check is on port 8080 | Port mismatch between app and Qovery config | Update `ports[].internal_port` and health check port in Qovery config | YES — Qovery config |
| `ECONNREFUSED 127.0.0.1:5432` or `connection refused` to DB | Database not ready or wrong connection string | Check deployment stages (DB must deploy before app). Check `DATABASE_URL` env var | YES — fix deployment stage or env var |
| `Error: connect ECONNREFUSED` to external service | Missing env var for external service URL | Ask user for the correct URL/credentials | ASK USER |
| `OOMKilled` or `memory limit exceeded` | Application needs more memory than allocated | Increase `memory` in Qovery config (e.g., 512 -> 1024) | YES — Qovery config |
| `exec format error` | Architecture mismatch (ARM image on AMD64 node or vice versa) | Fix the build architecture in Dockerfile or cluster config | YES if your Dockerfile |
| `SIGKILL` after timeout | App takes too long to start | Increase `initial_delay_seconds` (e.g., 30 -> 60 or 120) | YES — Qovery config |
| Health check 404 on `/health` | App doesn't have a `/health` endpoint | Switch to TCP health check instead of HTTP, or add the endpoint | YES for TCP switch, ASK for code change |

**How to fix port mismatch via API:**
```bash
# Update application port
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ports": [{"internal_port": 3000, "external_port": 443, "protocol": "HTTP", "publicly_accessible": true, "name": "http"}]
  }'
```

**How to fix health check via API:**
```bash
# Switch to TCP health check (when app has no /health endpoint)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "healthchecks": {
      "liveness_probe": {
        "type": {"tcp": {"port": 3000}},
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "success_threshold": 1,
        "failure_threshold": 3
      }
    }
  }'
```

**How to increase memory via API:**
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"memory": 1024}'
```

**Debugging tip — use port-forward and shell to investigate live:**
```bash
# Open a shell into the running (or crashing) container
qovery shell --service "my-app"

# Port-forward to access the app locally and test it directly
qovery port-forward --service "my-app" --port 8080:8080
# Then: curl http://localhost:8080/health

# Port-forward to the database to verify it's accessible
qovery port-forward --service "postgres" --port 5432:5432
# Then: psql -h localhost -p 5432 -U myuser -d mydatabase
```

These commands create a secure tunnel — the services do NOT need to be publicly exposed.

#### GIT_CLONE Error — Cannot Access Repository

**Symptoms:** Step `GIT_CLONE` failed.

**Common causes:**
- Git provider (GitHub/GitLab/Bitbucket) not connected to the Qovery organization
- Repository is private and Qovery doesn't have access
- Wrong repository URL or branch name

**Fix:** Direct the user to Qovery Console > Organization Settings > Git Repository Access to connect their git provider. If the branch is wrong, update it via API:
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"git_repository": {"branch": "main"}}'
```

#### Database Connection Issues

**Symptoms:** Application logs show connection refused/timeout to database.

**Diagnosis steps:**
1. Check if the database service is actually running: `qovery service list`
2. Check deployment stages — the database MUST deploy in an earlier stage than the application
3. Check if `DATABASE_URL` or equivalent env var is set correctly — it should be an **alias** pointing to the built-in `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL` variable (not a hardcoded value, not interpolation for simple connections)
4. Check if the application is using `_INTERNAL` (cluster network) vs external URL — always prefer `_INTERNAL`

**Fixes (all auto-fixable — Qovery config):**
```bash
# Fix deployment stage ordering via API
curl -s -X PUT "https://api.qovery.com/deploymentStage/{stageId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"is_after": "{dbStageId}"}'

# Fix DATABASE_URL — create an alias to the built-in connection URI (preferred)
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable/alias" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "DATABASE_URL", "alias_parent_id": "{sourceVariableId}"}'
# Note: get the sourceVariableId by listing the environment's built-in variables:
# GET /environment/{envId}/environmentVariable — find the QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL variable ID
```

#### Missing Environment Variable

**Symptoms:** Application logs show `Error: XYZ is not defined`, `KeyError: 'XYZ'`, `env var XYZ required`, `undefined`, etc.

**Diagnosis:**
1. Identify the missing variable name from the logs
2. Check if it's a standard variable (PORT, NODE_ENV, DATABASE_URL) or a custom one
3. Check if it's a secret (API keys, passwords, tokens) or non-secret

**Fix:**
- For standard non-secret variables (PORT, NODE_ENV, etc.): Auto-fix by adding the variable via API. **YES — auto-fix.**
- For database connection variables: Auto-fix using Qovery interpolation syntax. **YES — auto-fix.**
- For secrets (API keys, JWT secrets, third-party tokens): **ASK USER** for the value. Never guess or generate secrets without permission.

```bash
# Auto-fix example: add missing PORT variable
curl -s -X POST "https://api.qovery.com/application/{appId}/environmentVariable" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "PORT", "value": "8080"}'

# For secrets — ask the user, then:
curl -s -X POST "https://api.qovery.com/application/{appId}/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "user-provided-value"}'
```

#### Terraform Service Errors

**Symptoms:** Terraform service shows `DEPLOYMENT_ERROR`. Execution step failed.

**Diagnosis:** Fetch terraform service logs to see the `terraform plan` or `terraform apply` output.

**Common causes:** Wrong variables, missing AWS permissions, resource conflicts, state lock.

**Fix:** These are complex and highly variable. Show the Terraform error output to the user and explain the likely cause. **ASK USER** before making changes to Terraform code.

#### Helm Chart Errors

**Symptoms:** Helm service shows `DEPLOYMENT_ERROR`.

**Diagnosis:** Fetch helm logs to see the `helm install/upgrade` output.

**Common causes:** Invalid values, missing dependencies, timeout, resource conflicts.

**Fix:** Show the Helm error to the user. If it's a values override issue (e.g., wrong port, missing config), you can auto-fix the `values_override` in Qovery config. For chart-level issues, **ASK USER**.

### 10.2 Fix and Redeploy Loop

After applying a fix (whether auto-fix or user-approved):

1. **Apply the fix** — API call to update Qovery config, or edit and commit a file (Dockerfile, next.config.js, etc.)

2. **Trigger a redeploy:**
   ```bash
   # Redeploy a single service
   curl -s -X POST "https://api.qovery.com/application/{appId}/restart" \
     -H "Authorization: Token $QOVERY_API_TOKEN"

   # Or redeploy the whole environment
   curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
     -H "Authorization: Token $QOVERY_API_TOKEN"

   # Or via CLI
   qovery application redeploy --application "my-app"
   ```

3. **Watch the new deployment** — Go back to Phase 9.2 and monitor again.

4. **Repeat** until success or until the issue clearly requires user intervention that you cannot resolve.

5. **Maximum retries**: Do not attempt more than 3 auto-fix cycles for the same service. If after 3 attempts the service still fails, present a full summary of what you tried, what the current error is, and ask the user how they want to proceed.

### 10.3 Common Fix Recipes

#### Recipe: Next.js standalone output not enabled

**Error:** Build succeeds but deployment fails — `.next/standalone` directory is missing.

**Fix (auto-fix — you created the Dockerfile that expects standalone):**
1. Check `next.config.js` or `next.config.mjs`
2. Add `output: 'standalone'` if missing
3. Commit and push
4. Redeploy

#### Recipe: Python missing gunicorn/uvicorn

**Error:** Build succeeds but container crashes with `gunicorn: command not found` or `uvicorn: command not found`.

**Fix (auto-fix — you created the Dockerfile that references it):**
1. Add `gunicorn` or `uvicorn` to `requirements.txt`
2. Commit and push
3. Redeploy

#### Recipe: App listens on 0.0.0.0 but health check uses wrong port

**Error:** Logs show `Server listening on port 3000` but Qovery health check is configured for port 8080.

**Fix (auto-fix — Qovery config):**
1. Update port config and health check port to 3000 via API
2. Redeploy

#### Recipe: Database not ready when app starts

**Error:** App crashes with `ECONNREFUSED` to database host on first deploy. Database is still provisioning.

**Fix (auto-fix — Qovery config):**
1. Ensure database is in an earlier deployment stage than the application
2. If deployment stages are correct, increase `initial_delay_seconds` on the app's health check to give the DB more time
3. Redeploy

#### Recipe: SPA returns 404 on page refresh

**Error:** React/Vite SPA works on the root URL but returns 404 when refreshing on a sub-route (e.g., `/dashboard`).

**Fix (auto-fix — you created the nginx Dockerfile):**
1. Verify the nginx config in the Dockerfile includes `try_files $uri $uri/ /index.html`
2. If missing, fix the nginx configuration in the Dockerfile
3. Commit and push
4. Redeploy

---

