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

**Running unattended (no one available to answer the question above):**

If the agent has no way to get a synchronous approval — an autonomous/scheduled run with nobody watching the turn — do not commit the change straight to the default branch, and do not silently drop it either. Open a PR instead:

1. Create a topic branch (e.g. `qovery-speedup/dockerfile-optimization`)
2. Apply the proposed Dockerfile / code change on that branch
3. Commit with a descriptive message (Conventional Commits style, e.g. `perf: reorder Dockerfile layers for cache reuse`)
4. Push the branch and open a PR against the default branch
5. In the PR description, include: the measured bottleneck, the before/after diff, the expected time saving, and a note that this was proposed by an autonomous qovery-speedup run and needs human review before merge
6. Do NOT merge the PR — leave that to a human reviewer
7. Note in the run's final summary that this fix is pending review in the PR, and that re-measuring it (Phase 4.2) can only happen after it's merged and redeployed

Auto-fixes (health checks, stage ordering, `.dockerignore`, resource requests) still apply directly via the Qovery API/CLI regardless of attended/unattended — they don't need this PR flow since no approval is required for them.

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

