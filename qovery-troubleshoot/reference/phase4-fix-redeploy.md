## PHASE 4: Fix & Redeploy

### CRITICAL RULE: What You Can and Cannot Fix Automatically

**AUTO-FIX ALLOWED (no permission needed):**
- Qovery service configuration: port numbers, health check paths/ports/delays, memory/CPU limits, deployment stage ordering, environment variables (non-secret), Dockerfile path, git branch, root_path, instance counts, autoscaling settings
- Resource right-sizing (increase memory/CPU)
- Deployment stage reordering
- Health check type switching (HTTP to TCP)
- Stopping/starting services for cost optimization
- Canceling stuck deployments

**MUST ASK USER BEFORE FIXING:**
- Any changes to application source code
- Any changes to Dockerfiles
- Adding, changing, or removing secrets
- Database schema changes
- Terraform module code changes
- Helm values changes that affect application behavior
- Any change where you are not 100% certain it will fix the issue

**WHEN ASKING, always:**
1. Explain the error clearly (quote the relevant log lines)
2. Explain what you think the root cause is
3. Show the exact change you propose
4. Wait for explicit approval before making the change

### Redeploy After Fix

```bash
# Redeploy a single service
curl -s -X POST "https://api.qovery.com/application/{appId}/restart" \
  -H "Authorization: Token $QOVERY_API_TOKEN"

# Or redeploy the whole environment
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"

# Or via CLI
qovery application redeploy --application "name"

# Or via MCP
# "Redeploy the backend application"
# "Restart the API service"
```

### Watch and Verify

After redeploying, watch the deployment (same as Phase 1.2). If it fails again, loop back to Phase 2 with the new error. Maximum 3 auto-fix attempts per service before escalating to the user with a full summary of what was tried.

---

