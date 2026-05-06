## PHASE 6: Seasonal & Special Considerations

### E-Commerce / Seasonal Businesses

- **NEVER right-size below 30-day peaks** during or approaching peak season
- **Pre-scale 1-2 days before known peaks**: increase `min_running_instances` temporarily
- **Keep autoscaling max high**: 3-5x normal capacity during peak season
- **Post-peak review**: 1 week after the peak ends, re-analyze and right-size back down
- **Annual calendar**: create a schedule of known peaks and optimization windows

Example pre-scale command:
```bash
# Before Black Friday: increase min instances
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 5, "max_running_instances": 20}'

# After Black Friday: revert to normal
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"min_running_instances": 2, "max_running_instances": 6}'
```

### SaaS / Steady Traffic

- **Focus on right-sizing** — steady traffic means 7-day peaks are reliable predictors
- **Focus on environment scheduling** — biggest savings for non-production
- **Autoscaling with conservative max** — spikes are rare, max=2x normal is usually sufficient
- **Reserved Instances / Savings Plans** — stable workloads benefit most from committed pricing (30-40% savings)

### Startup / Growth Stage

- **Conservative right-sizing** — don't cut too aggressively, traffic is growing
- **Use autoscaling as primary strategy** — set generous max, low min
- **Review monthly** — traffic patterns are still emerging
- **Avoid long-term commitments** (RIs, Savings Plans) — traffic is unpredictable
- **Focus on environment scheduling** — immediate savings with zero risk

### B2B / Business-Hours

- **Aggressive environment scheduling** — most traffic is 9am-6pm weekdays
- **Consider reducing production instances outside business hours** (if your SLA allows brief scale-down at 3am)
- **Weekend shutdown for staging/dev** — significant savings

### ML/AI Workloads

- **GPU instances are expensive** ($1-10/hour per GPU) — optimize aggressively
- **Training workloads**: use spot instances (60-70% savings), tolerate interruptions with checkpointing
- **Inference serving**: autoscale to zero when idle (KEDA), use GPU sharing if supported
- **Data pipelines**: schedule during off-peak hours for potential spot availability
- **Karpenter GPU provisioning**: ensure GPU node groups are configured with appropriate instance types (p3, g4dn, g5)

### Batch Processing / Data Pipelines

- **Event-driven autoscaling (KEDA)**: scale based on queue depth, not CPU
- **Scale to zero**: when no work is queued, scale pods to 0
- **Spot instances**: ideal for fault-tolerant batch workloads
- **Schedule during off-peak**: cloud prices can be lower when demand is low

---

