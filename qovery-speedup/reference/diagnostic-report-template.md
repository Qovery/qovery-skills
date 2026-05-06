## Timeline Analysis (Last 5 Deployments)

| # | Date | Total | Queue | Build | Push | Schedule | Startup | Health | Status |
|---|------|-------|-------|-------|------|----------|---------|--------|--------|
| 5 | 4/20 | 12:34 | 0:15  | 8:42  | 0:45 | 0:22     | 1:50    | 0:32   | OK     |
| 4 | 4/19 | 11:22 | 0:10  | 7:50  | 0:40 | 0:20     | 1:45    | 0:30   | OK     |
| 3 | 4/18 | 14:10 | 0:18  | 10:05 | 0:50 | 0:25     | 1:50    | 0:32   | OK     |
| 2 | 4/17 | 6:45  | 0:12  | 4:12  | 0:35 | 0:18     | 1:20    | 0:28   | OK     |
| 1 | 4/15 | 6:30  | 0:10  | 4:05  | 0:30 | 0:15     | 1:20    | 0:30   | OK     |

## Identified Bottleneck

**Step:** {step name}
**Owner:** Qovery infrastructure
**Details:** {specific diagnosis — e.g., "Build runner CPU consistently at 100% throughout the 8-minute build. The Grafana snapshot confirms CPU saturation. Dockerfile has already been optimized (proper layer ordering, .dockerignore, multi-stage build, cache mounts)."}

## Build Runner Usage Report

**Grafana Snapshot URL:** {report_url from API}
*(Expires in 24 hours — please review before expiration)*

## User-Side Optimizations Already Applied

- [x] Dockerfile layer ordering optimized
- [x] .dockerignore configured
- [x] Multi-stage build in place
- [x] Build cache mounts added
- [x] Health check timing tuned
- [x] Deployment stages parallelized

## Recommendation

Please review the build runner CPU/memory allocation for cluster "{cluster_name}" in region {region}. The current build runner resources appear insufficient for this application's build requirements.

## Service Configuration

- Build mode: DOCKER
- Dockerfile: {path}
- CPU: {cpu}m
- Memory: {memory}MB
- Instances: {min}-{max}
- Health check: {type} on port {port}, path {path}, initial_delay {delay}s
```

### 5.3 Offer to Contact Qovery Support

> "The bottleneck is on Qovery's infrastructure side ({specific step}). I've generated a diagnostic report at `.qovery/reports/YYYY-MM-DD-deployment-speed.md` with timeline data, the build runner Grafana snapshot, and details about what's been optimized on your side.
>
> Would you like to share this report with Qovery support? They can:
> - Increase build runner CPU/memory allocation
> - Optimize registry push performance
> - Review Karpenter configuration for faster node provisioning
> - Investigate queue delays
>
> Contact them at:
> - **Email:** support@qovery.com (attach the report)
> - **Qovery Console:** In-app chat support
> - **Community Forum:** https://discuss.qovery.com"

---

