## PHASE 6: Deployment Plan Summary

Before executing any operations, present a complete summary and get explicit confirmation.

### 6.1 Generate the Summary

> **Builder Environment Platform Plan**
>
> **Target Infrastructure:**
> - Organization: **{org_name}** (`{org_id}`)
> - Cluster: **{cluster_name}** ({cloud_provider}, {region}) — dedicated for builders
> - Project: **builder-workspaces** *(new — will be created)*
>
> **RBAC:**
> - Custom role: **Builder** — DEPLOYER on DEV, VIEWER on staging, NO_ACCESS on production
> - Cluster permission: ENV_CREATOR on builder cluster
>
> **Builder Template:**
>
> | Service | Type | Image / Config | CPU | Memory | Port |
> |---------|------|---------------|-----|--------|------|
> | workspace | Application | VS Code Server (code-server) | 1000m | 2048MB | 8080 |
> | postgres | Database | PostgreSQL 16 (container) | 250m | 256MB | 5432 |
>
> **Pre-installed tools:** {VS Code + Copilot, Qovery CLI, Qovery Skills, Claude Code, OpenCode}
>
> **AI API Keys (platform-managed secrets):**
> - `ANTHROPIC_API_KEY` — set at project scope (secret)
> - `OPENAI_API_KEY` — set at project scope (secret)
>
> **Builders to provision:** {count}
> {list of builders with name, email, team}
>
> **Cost Controls:**
> - Auto-stop: weekdays 8pm-8am, weekends all day
> - Resource limits: {CPU}m CPU, {Memory}MB RAM per builder
> - Estimated cost: ~${X}/builder/month (stopped overnight)
>
> **Security:**
> - SSO: {provider or "not configured"}
> - Compliance: {SOC2, ISO 27001, etc. or "Qovery default (SOC2)"}
> - Audit trail: all operations tracked per-builder
>
> **Infrastructure as Code:** {Terraform / Scripts / Local only}
>
> **Warnings:**
> - Database data is per-builder (not shared) — each builder gets an empty database
> - AI API keys will be billed to the platform team's accounts
> - Builder environments consume cluster resources while running

### 6.2 Get Confirmation

> "Does this plan look correct? I'll proceed with creating the platform once you confirm. Let me know if you want to change anything."

**CRITICAL: Do NOT proceed until the user explicitly confirms.**

### 6.3 Handle Changes

If the user wants to modify the plan, adjust and re-present the full summary. Common changes:
- Different cluster
- Different IDE option
- Add/remove builders
- Change resource limits
- Change auto-stop schedule
- Add/remove database

---

