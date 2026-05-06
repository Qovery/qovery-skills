## PHASE 5: Deployment Plan Summary

Before executing any operations, present a complete summary of the deployment plan to the user and get explicit confirmation. This is the most important checkpoint — the next phase creates real cloud resources.

### 5.1 Generate the Summary

Present a structured summary:

> **Preview Environment Plan**
>
> **Context:**
> - PR: **#{number}** — {title} (`{pr_branch}` → `{base_branch}`)
> - Repository: `{repo-url}`
> - Organization: **{org_name}** | Cluster: **{cluster_name}** ({region})
> - Project: **{project_name}**
>
> **Blueprint:** `{blueprint_name}` *(existing / will be created from `{source_env}`)*
>
> **Preview environment to create:**
> - Name: `preview-pr-{number}`
> - Mode: `PREVIEW`
> - Cloned from: `{blueprint_name}`
>
> **Services — branch changes:**
>
> | Service | Type | Current Branch | New Branch |
> |---------|------|---------------|------------|
> | backend | Application | main | feat/my-feature |
> | frontend | Application | main | feat/my-feature |
> | postgres | Database | — | — (cloned config, empty data) |
> | redis | Database | — | — (cloned config) |
> | auto-shutdown | Cron Job | — | — (will be created) |
>
> **Auto-shutdown:**
> - Strategy: {stop/delete/recycle/manual/PR-merge}
> - Scheduled: {datetime} ({duration} from now)
>
> **Warnings:**
> - Database data is NOT cloned — seed scripts may be needed
> - A Qovery API token will be generated for the auto-shutdown job
> - Preview environments consume cluster resources while running

Adapt the template to the actual context. Omit sections that don't apply.

### 5.2 Get Confirmation

Ask the user:

> "Does this plan look correct? I'll proceed once you confirm. Let me know if you want to change anything or if you have additional instructions."

**CRITICAL: Do NOT proceed to Phase 6 until the user explicitly confirms.** The next phase creates cloud resources and deploys services.

### 5.3 Handle Changes

If the user wants to modify the plan:
1. Adjust the relevant settings
2. Re-present the **full updated summary**
3. Get confirmation again

Common change requests:
- Different cluster
- Different blueprint source
- Different auto-shutdown duration
- Add/remove services from branch switching
- Skip database cloning
- Add environment variables specific to the preview

---

