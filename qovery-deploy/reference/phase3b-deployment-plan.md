## PHASE 3B: Deployment Plan Summary

Before executing any operations (Phase 4 or Phase 5), you MUST present a complete summary of the deployment plan to the user and get explicit confirmation. This applies to BOTH the CLI+API path and the Terraform path.

### 3B.1 Generate the Summary

Based on all information gathered in Phase 1 (user answers, resolved organization, resolved cluster) and Phase 3 (codebase analysis, Dockerfile creation), compile a deployment plan. Present it in a clear, structured format:

> **Deployment Plan**
>
> **Target Infrastructure:**
> - Organization: **{org_name}** (`{org_id}`)
> - Cluster: **{cluster_name}** ({cloud_provider}, {region})
> - Project: **{project_name}** *(new — will be created / existing)*
> - Environment: **{env_name}** (mode: {PRODUCTION/STAGING/DEVELOPMENT}) *(new — will be created / existing)*
> - Deployment method: **{CLI + API / Terraform}**
>
> **Services to deploy:**
>
> | Service | Type | Source | Port | Public | CPU | Memory |
> |---------|------|--------|------|--------|-----|--------|
> | backend | Application | git: main, path: /backend | 8080 | Yes | 500m | 512MB |
> | frontend | Application | git: main, path: /frontend | 3000 | Yes | 500m | 512MB |
> | worker | Container | registry: my-org/worker:v1.0 | — | No | 250m | 256MB |
>
> **Databases to provision:**
>
> | Name | Type | Version | Mode | Storage | Instance |
> |------|------|---------|------|---------|----------|
> | postgres | PostgreSQL | 16 | Container | 10GB | — |
> | redis | Redis | 7 | Container | 5GB | — |
>
> **Blueprints to deploy** *(reused from the catalog instead of hand-rolled Terraform — see Phase 3C)*:
>
> | Name | Blueprint tag | Provider | Category |
> |------|---------------|----------|----------|
> | prod-postgres | aws/postgres/17/1.0.1 | AWS | Managed Database |
>
> **Deployment stages (execution order):**
> 1. **Infrastructure**: postgres, redis
> 2. **Backend**: backend, worker
> 3. **Frontend**: frontend
>
> **Environment variables to set:**
> - `PORT` = `8080`
> - `NODE_ENV` = `production`
> - `DATABASE_URL` = alias -> `QOVERY_DATABASE_..._CONNECTION_URI_INTERNAL`
> - `PROD_DATABASE_URL` (backend) = alias -> `prod-postgres` blueprint's `endpoint` output *(see Phase 3C/6.10 — every app depending on a blueprint MUST have its connection wired via alias here)*
> - `JWT_SECRET` = *(secret — value provided by user)*
> - *(N other variables from .env file)*
>
> **Files to create/modify:**
> - `backend/Dockerfile` *(new — Node.js Express template)*
> - `backend/.dockerignore` *(new)*
> - `frontend/Dockerfile` *(new — Next.js template)*
> - `next.config.mjs` *(modified — added `output: 'standalone'`)*
>
> **Warnings:**
> - No `/health` endpoint detected in backend — will use TCP health check probe instead of HTTP
> - Database `postgres` is in **Container** mode — suitable for dev/test but not recommended for production workloads
> - Frontend has no `.dockerignore` — `node_modules` will be excluded via the generated file

Adapt this template to the actual services detected. Omit sections that don't apply (e.g., no "Databases" section if no databases are needed, no "Blueprints" section if the catalog had no match for anything requested, no "Files to create" if all Dockerfiles exist).

For the **Terraform path**, also include:
> **Terraform files to generate:**
> - `qovery.tf` — main infrastructure definition
> - `variables.tf` — input variables
> - `terraform.tfvars` — variable values *(will contain org/cluster/project IDs)*

### 3B.2 Get Confirmation

After presenting the summary, ask the user for explicit confirmation:

> "Does this deployment plan look correct? I'll proceed with creating these resources once you confirm. Let me know if you want to change anything (e.g., different cluster, more memory, managed database instead of container, etc.)."

**CRITICAL: Do NOT proceed to Phase 4 or Phase 5 until the user explicitly confirms.** This is the most important checkpoint in the deployment workflow — the next phases create real cloud resources, deploy services, and may incur costs.

### 3B.3 Handle Changes

If the user wants to modify the plan:
1. Adjust the relevant settings based on their feedback
2. Re-present the **full updated summary** (not just the changed parts — the user should always see the complete picture)
3. Get confirmation again before proceeding

Common change requests:
- Switch cluster (e.g., "use staging instead of production")
- Change database mode (e.g., "use managed for production", "use the RDS blueprint instead of a container database")
- Adjust resources (e.g., "give the backend 1GB memory")
- Change port or public accessibility
- Add/remove services
- Switch deployment method (CLI+API vs Terraform)

---
