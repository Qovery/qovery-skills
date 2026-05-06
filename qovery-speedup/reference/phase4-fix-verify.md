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

