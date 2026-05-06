## PHASE 5: Verification

After the fix is applied and the service is redeployed:

1. **Check service status:**
   ```
   MCP: "Is {service-name} healthy now?"
   CLI: qovery status
   ```

2. **Check logs for healthy operation:**
   ```bash
   # Use the flag matching the service type, or --service for any type:
   qovery log --service "name" --tail 20
   qovery log --service "name" --follow      # Stream in real-time to watch for errors
   ```

3. **Test the endpoint:**
   ```bash
   # Via port-forward (for internal services)
   qovery port-forward --service "name" --port 8080:8080
   curl http://localhost:8080/health

   # Via public URL (for public services)
   curl https://{app-url}/health
   ```

4. **Report to the user:**
   - What the problem was
   - What the root cause was
   - What was fixed
   - Whether it's working now
   - Preventive recommendations (Phase 7)

---

