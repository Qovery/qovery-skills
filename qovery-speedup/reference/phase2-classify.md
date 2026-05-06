## PHASE 2: Classify — User vs Qovery

Based on the timeline analysis, classify each bottleneck into who can fix it:

### Classification Table

| Step | Typical Time | Slow If > | Owner | User Can Fix? |
|---|---|---|---|---|
| **Queue time** | 5-30s | 2 min | Qovery | No — contact support |
| **Git clone** | 5-15s | 30s | Mixed | Yes if repo is huge (large files, no `.gitignore`) |
| **Docker build** | 1-10 min | 5 min | User (usually) | Yes — optimize Dockerfile (see Phase 3.1) |
| **Build runner resources** | N/A | CPU at 100% | Qovery | No — contact support for larger build runner |
| **Image push** | 15-60s | 2 min | Mixed | Smaller images help; registry infra is Qovery |
| **Image pull** (containers) | 10-60s | 2 min | Mixed | Smaller images help; registry proximity is Qovery |
| **Pod scheduling** | 10-30s | 2 min | Mixed | Reduce resource requests if too high; Karpenter is Qovery |
| **App startup** | 2-30s | 2 min | User | Yes — optimize startup code, use lifecycle jobs for migrations |
| **Health check** | 5-30s | 1 min | User | Yes — tune probe config (see Phase 3.4) |
| **Deployment stage ordering** | N/A | N/A | User | Yes — parallelize independent services |

### Decision Tree

```
For each bottleneck identified in Phase 1:

Is it user-controllable?
├── YES (Docker build, app startup, health check, stage ordering, image size)
│   └── Go to Phase 3 → diagnose deeper → Phase 4 → fix
│
├── MIXED (git clone, image push/pull, pod scheduling)
│   ├── User part: optimize what you can (image size, resource requests, .gitignore)
│   └── Qovery part: if still slow after user optimizations → Phase 5 → support
│
└── NO (queue time, build runner capacity, registry infra, Karpenter node provisioning)
    └── Go to Phase 5 → generate diagnostic report → contact Qovery support
```

---

