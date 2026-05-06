## PHASE 4: Apply Changes

### 4.1 User Approval

Present the report and ask:

> "Here are my cost optimization recommendations, sorted by impact. Which ones would you like me to apply? You can:
> - Say **'all'** to apply everything
> - Pick specific numbers (e.g., '1, 2, 4')
> - Say **'skip'** for any you want to hold off on
> - Ask me to adjust any recommendation before applying"

NEVER apply changes without explicit user approval.

### 4.2 Determine the Tool

If the user specified their tool in Phase 1, use that. If not, ask:

> "How should I apply these changes?
> A) **Qovery API** — applies immediately, changes take effect on next deployment
> B) **Generate Terraform diffs** — I'll show you the exact `.tf` changes to review and apply yourself
> C) **Both** — apply now via API and also generate Terraform for long-term IaC management"

### 4.3 Apply via API

For each approved recommendation:

```bash
# Right-size a service (CPU + memory)
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cpu": 250, "memory": 512}'

# Enable autoscaling
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 2, "max_running_instances": 5}'

# Via MCP
"Scale down the backend to 250m CPU and 512MB memory"
"Set backend autoscaling to min 2, max 5"
"Stop all development environments"
```

### 4.4 Generate Terraform Diffs

If the user manages infrastructure via Terraform, generate clear before/after diffs:

```hcl
# BEFORE (current):
resource "qovery_application" "backend" {
  cpu    = 500
  memory = 1024
  min_running_instances = 3
  max_running_instances = 3
}

# AFTER (optimized):
resource "qovery_application" "backend" {
  cpu    = 250    # Right-sized: peak 180m (30d), recommended 250m (1.5x buffer)
  memory = 512    # Right-sized: peak 400MB (30d), recommended 512MB (1.3x buffer)
  min_running_instances = 2    # Enabled autoscaling: reduced from 3 for off-peak savings
  max_running_instances = 5    # Headroom for traffic spikes
}
```

Present each change with a comment explaining the reasoning and the data behind it.

### 4.5 Set Up Environment Scheduling

For deployment rules:
- Via Console: guide through Environment Settings > Deployment Rules
- Via MCP: `"Stop all development environments for the weekend"`
- Note: provide the deployment rule configuration (pattern, start time, stop time, timezone, days)

### 4.6 Redeploy Affected Services

After applying resource changes, services need a redeploy:

```bash
# Redeploy all services in the environment
curl -s -X POST "https://api.qovery.com/environment/{envId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"

# Or via MCP
"Redeploy the production environment"

# Or via CLI
qovery environment deploy
```

---

