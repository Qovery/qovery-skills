## PHASE 7: Prevention & Recommendations

After fixing an issue, suggest preventive measures tailored to what went wrong:

### After Build Errors
- Pin dependency versions in lockfiles (package-lock.json, go.sum, requirements.txt)
- Use multi-stage Docker builds to reduce build context size
- Enable auto-deploy on Git push so build issues are caught early

### After Health Check Failures
- Add a dedicated `/health` endpoint to your application
- Set `initial_delay_seconds` based on actual startup time (measure it)
- Use readiness probes in addition to liveness probes
- For JVM apps: use Spring Boot Actuator's `/actuator/health`

### After OOM Kills
- Right-size memory based on observed peak usage + 20% buffer
- Enable autoscaling (`min_running_instances < max_running_instances`)
- For Node.js: set `--max-old-space-size` to 75% of container memory
- For JVM: set `-Xmx` to 75% of container memory
- Consider profiling for memory leaks

### After Connectivity Issues
- Always use `_INTERNAL` hostnames for in-cluster communication
- Use environment variable aliases for database connections (not hardcoded)
- Configure deployment stages so dependencies start first
- Use `qovery port-forward` for local debugging

### After Cost Issues
- Stop non-production environments during off-hours (MCP can automate this)
- Use container-mode databases for dev/test (not managed)
- Right-size resources based on actual usage
- Enable spot instances for non-critical workloads
- Clean up unused environments regularly

### After Cluster Issues
- Keep Kubernetes version up to date
- Monitor cluster capacity and node pressure
- Ensure cloud credentials are valid and have sufficient permissions
- Set up alerts for cluster-level issues (via Qovery Console)

### General Best Practices
- Use the [Qovery Deploy Skill](https://github.com/Qovery/qovery-skills) for new deployments — it sets up health checks, deployment stages, and env var aliases correctly from the start
- Use the [Qovery MCP Server](https://mcp.qovery.com/mcp) for day-to-day monitoring and management
- Use Terraform for production infrastructure (reproducible, version-controlled)
- Commit your `qovery.tf` and `.qovery/runbooks/` to git

---

