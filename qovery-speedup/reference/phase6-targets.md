## PHASE 6: Deployment Speed Targets & Ongoing Monitoring

### 6.1 What's a Reasonable Deployment Time?

| Application Type | Good | Acceptable | Needs Optimization |
|---|---|---|---|
| Simple Node.js/Go app (small codebase) | 1-3 min | 3-5 min | >5 min |
| React/Vite SPA (frontend) | 2-4 min | 4-7 min | >7 min |
| Next.js (SSR + build) | 3-6 min | 6-10 min | >10 min |
| Python (Flask/FastAPI/Django) | 1-4 min | 4-7 min | >7 min |
| Java (Spring Boot, Maven) | 3-8 min | 8-12 min | >12 min |
| Java (Spring Boot, Gradle) | 2-6 min | 6-10 min | >10 min |
| Go (compiled binary) | 1-3 min | 3-5 min | >5 min |
| .NET (ASP.NET Core) | 2-5 min | 5-8 min | >8 min |
| Container from registry (no build) | 30s-2 min | 2-4 min | >4 min |
| Helm chart | 1-5 min | 5-10 min | >10 min |
| Terraform service | 2-10 min | 10-20 min | Depends on resources |

### 6.2 Save Benchmark Report

Save the analysis to `.qovery/reports/YYYY-MM-DD-deployment-speed.md` for future comparison:

```bash
# Ask user if they want to commit
git add .qovery/reports/
git commit -m "docs: add deployment speed analysis YYYY-MM-DD"
```

### 6.3 When to Re-Analyze

Suggest re-running this analysis when:
- Adding significant new dependencies (larger `node_modules`, new Maven deps)
- Upgrading frameworks (new Next.js version, Spring Boot upgrade)
- Changing Dockerfiles
- Adding new services to the environment
- After Qovery cluster upgrades
- When deployment time noticeably regresses

### 6.4 Continuous Improvement Checklist

After optimization, provide the user with a checklist for maintaining fast deployments:

```markdown
## Deployment Speed Maintenance Checklist

- [ ] Dockerfile has proper layer ordering (lockfiles first, then code)
- [ ] .dockerignore excludes .git, node_modules, build artifacts
- [ ] Multi-stage build separates build and runtime
- [ ] Alpine/slim base images used where possible
- [ ] Dependencies installed with --production/--omit=dev flags
- [ ] Build cache mounts used for package manager caches
- [ ] Health check initial_delay_seconds matches actual startup time + buffer
- [ ] Both readiness and liveness probes configured
- [ ] Independent services are in the same deployment stage
- [ ] Database is in an earlier stage than the apps that need it
- [ ] No tests running inside Docker build (moved to CI)
- [ ] No large file downloads during app startup
- [ ] Database migrations run as lifecycle job, not during app startup
```

---

