# Phase 2b: KRR-Based Right-Sizing (when Qovery observability is enabled)

Qovery integrates [KRR (Kubernetes Resource Recommender)](https://github.com/robusta-dev/krr) as a built-in, read-only **cluster analysis**: the engine runs KRR server-side against the cluster's metrics stack and streams back per-container CPU/memory recommendations (P99 percentiles, max usage, OOMKill history). When the cluster has Qovery observability enabled, prefer this over the hand-computed formulas of Dimension 1: it is OOM-aware, battle-tested, and requires no kubeconfig, no port-forward, and no local KRR install.

This phase only replaces the **measurement** step of Dimension 1. The business-context guardrails of Phase 2 still apply on top of KRR's output.

## 2b.1 Preconditions

1. **Observability enabled on the cluster** (gives the analysis a metrics store to query):
   ```bash
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     -H "User-Agent: QoverySkill/qovery-optimize (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
     "https://api.qovery.com/organization/{organizationId}/cluster/{clusterId}" | \
     jq '.metrics_parameters.enabled'
   ```
   - `true` → run the analysis as-is.
   - `false`/`null` but the user operates their own Prometheus on the cluster → pass it with `--prometheus-url`.
   - Neither → skip this phase and use the Dimension 1 formulas with the metrics API.
2. **Recent Qovery CLI.** Verify with `qovery cluster analysis --help`; if the command is missing, upgrade the CLI first.

## 2b.2 Run the cost recommendation analysis

```bash
qovery cluster analysis cost-recommendation \
  -c {clusterId} \
  --output csv \
  --cmd-arg=--history_duration --cmd-arg=336 \
  --cmd-arg=--timeframe_duration --cmd-arg={days} \
  --cmd-arg=--cpu-request --cmd-arg=99 \
  --cmd-arg=--cpu-limit --cmd-arg=99 \
  --cmd-arg=--memory-buffer-percentage --cmd-arg=15 \
  --cmd-arg=--use-oomkill-data \
  --cmd-arg=--oom-memory-buffer-percentage --cmd-arg=25 \
  --cmd-arg=--allow-hpa
```

How it behaves:
- The analysis is **read-only** and runs on Qovery's side; nothing is changed on the cluster.
- `--watch` is on by default: the CLI polls until the analysis reaches SUCCEEDED/FAILED/TERMINATED, then prints the report. With `--watch=false`, fetch it later:
  ```bash
  qovery cluster analysis logs --cluster-id {clusterId} --analysis-id {analysisId}
  ```
- `--output`: `csv` for the report pipeline below, `table` for a quick human read, `json` for programmatic parsing.
- `--cmd-arg` values are **allowlisted KRR arguments**: the engine validates them and rejects unsupported or unsafe flags, so stick to the set above.

Flag rationale (the set proven on Qovery clusters):
- P99 for CPU requests/limits, 15% memory buffer, plus a 25% buffer on containers with OOMKill history (`--use-oomkill-data`).
- `--allow-hpa` respects HPA min replicas when computing pod-level diffs.
- `--timeframe_duration {days}`: match the Phase 1 analysis period (7 by default, 30 for seasonal businesses). If the metrics retention is shorter than the requested window, shorten it and note the limitation in the report.

## 2b.3 Map results to Qovery services

KRR rows are keyed by namespace/workload/container. Map them back to Qovery objects for the report: Qovery-managed namespaces carry the environment and workloads carry the service (`qovery.com/environment-id` and `qovery.com/service-id` labels). Resolve names through the API (list environments on the cluster, then services per environment) so every row lands on the right service and its current request settings.

## 2b.4 Apply the Phase 2 guardrails on top

KRR output is the measurement, not the final recommendation:

- Never recommend below the minimum thresholds (CPU 50m, memory 128MB).
- Seasonal business: if the timeframe does not cover the last peak, do not right-size below that peak (Dimension 1 rule).
- Production with expected growth: keep the growth buffer from the business context on top of KRR's number.
- Translate to Qovery service settings (CPU in millicores, memory in MB via `PUT /application/{appId}`), applied only after user confirmation per Phase 4.

In the Phase 3 report, tag these rows with source `KRR (P99, OOM-aware, {days}d)` so they are distinguishable from formula-based estimates. For a shareable client-facing HTML version, the CSV output can be dropped into the [KRR Report Generator](https://github.com/Qovery/krr-report-generator).

## 2b.5 Fallback

Analysis fails or preconditions unmet (no observability, no Prometheus, CLI too old and not upgradable) → fall back to Dimension 1 formulas using `GET /cluster/{clusterId}/metrics`, and record in the report that recommendations are formula-based rather than KRR-based.
