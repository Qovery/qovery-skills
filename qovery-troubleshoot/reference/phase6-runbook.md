## PHASE 6: Runbook Generation

After resolving an issue, offer to create a runbook for future reference:

> "I've fixed the issue. Would you like me to create a runbook documenting what happened and how it was resolved? This helps if the same issue occurs again."

If the user agrees:

### Create the Runbook

1. **Create the directory** (if it doesn't exist):
   ```bash
   mkdir -p .qovery/runbooks
   ```

2. **Generate a markdown file** with the following structure:

   ```markdown
   # Runbook: {Issue Title}

   **Date:** {YYYY-MM-DD}
   **Service:** {service-name}
   **Environment:** {environment-name}
   **Severity:** {Critical / High / Medium / Low}
   **Time to Resolve:** {Xm}

   ## Symptoms

   {What the user reported and what the agent observed}

   ## Diagnosis

   **Layer:** {Which diagnostic layer identified the issue}
   **Commands used:**
   - {MCP query or CLI command 1}
   - {MCP query or CLI command 2}

   ## Root Cause

   {Clear explanation of why the issue occurred}

   ## Resolution

   {Exact steps taken to fix the issue, including commands}

   ## Prevention

   {How to prevent this from happening again}

   ## Related Runbooks

   {Links to any related runbooks if applicable}
   ```

3. **File naming**: `YYYY-MM-DD-{issue-slug}.md`
   - Example: `2025-04-20-oom-kill-backend.md`
   - Example: `2025-04-20-db-connection-refused.md`
   - Example: `2025-04-20-health-check-timeout.md`

4. **Ask the user** if they want to commit the runbook to git:
   ```bash
   git add .qovery/runbooks/
   git commit -m "docs: add runbook for {issue-slug}"
   ```

### Reference Past Runbooks

When a new issue occurs, check if there are existing runbooks in `.qovery/runbooks/` that match the symptoms. If a relevant runbook exists, reference it — the fix might be the same or similar.

---

