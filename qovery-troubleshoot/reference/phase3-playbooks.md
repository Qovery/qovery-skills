## PHASE 3: Common Issue Playbooks

Pre-built diagnostic sequences for the most common problems. Jump directly to the relevant playbook based on the user's description.

### Playbook: App Won't Start

**Triggers:** "my app won't start", "deployment error", "container keeps crashing"

1. Check deployment status (Layer 1) — is it `BUILD_ERROR` or `DEPLOYMENT_ERROR`?
2. If `BUILD_ERROR`: fetch build logs (Layer 2), identify the failing step
3. If `DEPLOYMENT_ERROR`: fetch runtime logs (Layer 3), check for crash reason
4. Check health checks (Layer 4) — is the probe timing out?
5. Check env vars (Layer 5) — is a required variable missing?
6. Check resources (Layer 7) — is the app OOM killed?
7. Apply fix and redeploy

### Playbook: App Is Slow

**Triggers:** "my app is slow", "high latency", "performance issue", "takes forever to respond"

1. Check resource allocation (Layer 7) — CPU/memory too low?
2. Check if autoscaling is hitting max instances
3. Check if app is using external hostnames instead of `_INTERNAL` (Layer 6)
4. Check database performance — port-forward and run `EXPLAIN ANALYZE` on slow queries
5. Check for N+1 queries or missing indexes (ASK USER to review queries)
6. Recommend right-sizing and autoscaling configuration
7. Check if the app is CPU-bound or I/O-bound from logs

### Playbook: Database Connection Fails

**Triggers:** "can't connect to database", "ECONNREFUSED", "connection timeout", "database unreachable"

1. Is the database service running? (Layer 1 — `qovery service list`)
2. Are deployment stages correct? (Layer 6 — DB must deploy before app)
3. Is `DATABASE_URL` set correctly? (Layer 5 — should be an alias, not hardcoded)
4. Is it using `_INTERNAL` hostname? (Layer 5 — `_HOST_INTERNAL`, not `_HOST`)
5. Port-forward to the DB and test locally (Layer 6):
   ```bash
   qovery port-forward --service "postgres" --port 5432:5432
   psql -h localhost -p 5432 -U myuser -d mydatabase
   ```
6. Check for connection pool exhaustion in app logs (Layer 3)
7. Check if DB requires SSL but app doesn't use it (Layer 3 — `sslmode` error)
8. Apply fix and redeploy

### Playbook: Deployment Stuck / Queued

**Triggers:** "deployment stuck", "deployment queued forever", "won't deploy", "deploying for hours"

1. Check environment status — is another deployment in progress?
2. Check deployment stage dependencies — circular wait?
3. Check cluster status (Layer 8) — is the cluster healthy?
4. Check if there are resource constraints (no node capacity)
5. Cancel the stuck deployment and retry:
   ```bash
   # Cancel via API
   curl -s -X POST "https://api.qovery.com/environment/{envId}/cancelDeployment" \
     -H "Authorization: Token $QOVERY_API_TOKEN"
   # Or via MCP: "Cancel the ongoing deployment"
   ```
6. Retry the deployment
7. If it's still stuck: check Qovery Console for more details or contact support

### Playbook: Custom Domain Not Working

**Triggers:** "domain not working", "SSL error", "certificate issue", "custom domain 404"

1. Check if the custom domain is registered in Qovery:
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/application/{appId}/customDomain" | jq
   ```
2. Check DNS CNAME record:
   ```bash
   dig app.example.com CNAME
   # Must point to the Qovery-generated domain
   ```
3. Check if the service is publicly accessible (port config has `publicly_accessible: true`)
4. Check TLS certificate — Qovery uses Let's Encrypt, may take a few minutes to provision
5. Check if the protocol is `HTTP` (not `TCP`/`UDP`) for web traffic
6. If DNS is correct but still not working: wait 5-10 minutes for DNS propagation

### Playbook: Terraform Service Failing

**Triggers:** "terraform error", "terraform plan failed", "terraform service stuck"

1. Fetch Terraform execution logs via MCP or API
2. Common causes:
   - **Variable errors**: Missing or wrong `variables` in the Terraform service config
   - **Permission errors**: Cloud credentials don't have required IAM permissions
   - **State lock**: Previous run didn't release the state lock
   - **Resource conflicts**: Resource already exists outside Terraform
3. Show the Terraform error output to the user — **ASK before making changes**
4. Terraform code changes always require user approval

### Playbook: Helm Chart Failing

**Triggers:** "helm install failed", "chart error", "helm timeout"

1. Fetch Helm install/upgrade logs via MCP or API
2. Common causes:
   - **Invalid values**: YAML syntax error in `values_override`
   - **Missing dependencies**: Chart requires a dependency that isn't deployed
   - **Timeout**: Chart takes longer than `timeout_sec` to deploy
   - **Resource conflicts**: Kubernetes resources already exist
3. If timeout: increase `timeout_sec` — **auto-fix**
4. If values error: fix `values_override` — **auto-fix for typos, ASK for logic changes**
5. Check `qovery.env.*` macro references — are the referenced variables set?

### Playbook: High Costs / Cost Optimization

**Triggers:** "too expensive", "reduce costs", "cost optimization", "save money"

**Via MCP (preferred — provides structured cost analysis):**
```
"Show me monthly spending"
"Find underutilized resources"
"Which environments are costing the most?"
"Show me idle services"
"Stop all non-production environments for the weekend"
```

**Manual diagnosis:**

1. **List all services with resource allocations:**
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/environment/{envId}/statuses" | jq
   ```

2. **Identify over-provisioned services:**
   - CPU allocation much higher than actual usage
   - Memory allocation much higher than peak usage
   - Recommend right-sizing — **auto-fix**

3. **Identify idle/unused services:**
   - Services with no traffic or no recent deployments
   - Development/staging environments running 24/7
   - Recommend stopping during off-hours — **auto-fix via MCP**

4. **Database mode optimization:**
   - Production using container-mode database? Consider managed mode for reliability
   - Dev/test using managed-mode database? Switch to container mode to save costs

5. **Spot instances:**
   - For non-critical workloads, consider enabling spot instances on the cluster

6. **Environment lifecycle:**
   - Stop all non-production environments overnight/weekends:
     ```
     MCP: "Stop all development environments overnight"
     ```

### Playbook: OOM / Resource Exhaustion

**Triggers:** "out of memory", "OOM killed", "crash loop", "exit code 137"

1. Confirm OOM from logs (Layer 3): `OOMKilled`, `exit code 137`, `SIGKILL`
2. Check current memory allocation:
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/application/{appId}" | jq '.memory'
   ```
3. Increase memory by 50-100% — **auto-fix**:
   - 512MB -> 1024MB
   - 1024MB -> 2048MB
4. If it keeps happening: the app likely has a memory leak — **ASK USER** to investigate
5. For Node.js: suggest `--max-old-space-size` flag — **ASK USER**
6. For JVM: suggest `-Xmx` and `-Xms` JVM options — **ASK USER**
7. Redeploy and monitor

### Playbook: Build Failing

**Triggers:** "build error", "docker build failed", "can't build"

1. Fetch build logs (Layer 2)
2. Check Dockerfile path — is `dockerfile_path` correct? — **auto-fix if wrong**
3. Check `root_path` for monorepos — **auto-fix if wrong**
4. Check for dependency errors — **ASK USER** for code/package changes
5. Check for disk space issues — optimize Dockerfile layers — **auto-fix**
6. Check base image availability — **auto-fix if base image tag is wrong**
7. Redeploy

---

