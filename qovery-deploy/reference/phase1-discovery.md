## PHASE 1: Discovery & User Questionnaire

Before doing anything, you MUST gather information by asking the user these questions. Do NOT skip this phase. Ask them conversationally, not as a wall of text — group related questions together.

### Group 1: Qovery Account & Infrastructure

#### Step 1: Authenticate

Before asking any questions, try to detect an existing token automatically:
1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set in the environment
2. If not, try `qovery auth token --print` — if the CLI is authenticated, this outputs a valid token (auto-refreshed if expired). Use it directly with `Authorization: Bearer $(qovery auth token --print)` or generate a named API token via `qovery token create --name "deploy-skill" --duration 24h`.
3. If the CLI is not authenticated, run `qovery auth` for interactive login, then use step 2.
- Only ask the user to manually create a token at Qovery Console > Organization Settings > API Tokens if none of the above options work
- Tokens should be stored securely (never commit to git)

#### Step 2: Resolve Organization

**Shortcut:** If the user provided a Qovery Console URL, extract the organization ID (and any other IDs) from it using the URL Detection rules above. Use the extracted IDs directly and skip the resolution questions for any resources already identified. You can still resolve names via the API to confirm with the user what was detected.

After authenticating, **proactively list all organizations** the user has access to:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | {id, name}'
```

- **If 0 organizations**: The user does not have a Qovery account or has not been invited to any organization. Direct them to sign up at https://console.qovery.com — they need an organization before anything else.
- **If 1 organization**: Confirm with the user and move on:
  > "I found your organization: **{name}**. I'll use this one."
- **If multiple organizations**: Present the full list and ask the user to choose. Do NOT silently pick the first one:
  > "I found multiple Qovery organizations on your account:
  > 1. **Acme Corp** (id: abc-123)
  > 2. **Personal Projects** (id: def-456)
  > 3. **Staging Org** (id: ghi-789)
  >
  > Which organization should I deploy to?"

Store the selected organization ID — it will be used for all subsequent API calls.

#### Step 3: Resolve Cluster

After selecting the organization, **proactively list all clusters** in that organization:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'
```

- **If 0 clusters**: The user MUST create a cluster before deploying. Go to **Phase 2B: Cluster Setup** after completing Phase 2 prerequisites. Cluster creation takes 15-30 minutes.
- **If 1 cluster**: Confirm the cluster details with the user:
  > "I found one cluster: **{name}** ({cloud_provider}, {region}, status: {status}). I'll deploy to this cluster."
  - If the cluster status is NOT `DEPLOYED` or `READY`, warn the user: "This cluster is currently in **{status}** state and cannot accept deployments. Please wait for it to be ready or choose a different cluster."
- **If multiple clusters**: Present the full list with key details and ask the user to choose. Do NOT silently pick one:
  > "I found multiple clusters in your organization:
  >
  > | # | Name | Provider | Region | Status |
  > |---|------|----------|--------|--------|
  > | 1 | production | AWS | us-east-1 | DEPLOYED |
  > | 2 | staging | AWS | eu-west-1 | DEPLOYED |
  > | 3 | dev | GCP | us-central1 | DEPLOYED |
  >
  > Which cluster should I deploy to?"
  - Only show clusters with `DEPLOYED` or `READY` status as valid options. If a cluster is in another state, list it but mark it as unavailable (e.g., "~~dev~~ (status: DEPLOYING — not ready)").

IMPORTANT: Do NOT skip the cluster check. Without a running cluster, no services can be deployed. Store the selected cluster ID — it will be used when creating environments.

**NEVER guess a cluster by pattern-matching its name against the user's username, org name, or project name** (e.g. picking `local-demo-acarrano` because the user is Alessandro Carrano). A name match is not consent. With more than one cluster, always show the full list and ask — no exceptions, even if one name looks like an obvious personal/demo cluster. This matters even more when the deployment involves cloud resources (a database, a Blueprint, a Terraform service) whose provider/region must match the chosen cluster — silently picking the wrong cluster here means provisioning real infrastructure in the wrong place, cloud account, or region.

#### Step 4: Resolve Project & Environment

Ask the user:

4. **Do you already have a Qovery project and environment, or should we create them?**
   - If they have existing ones, ask for the names (you will look them up via the API using the resolved organization ID)
   - If not, you will create them in the selected organization, targeting the selected cluster

### Group 2: Project Analysis

Before asking more questions, **analyze the codebase yourself** by looking at:

- `package.json` — Node.js (check for `next`, `react`, `vite`, `express`, `fastify`, `nestjs`)
- `go.mod` / `go.sum` — Go
- `requirements.txt` / `pyproject.toml` / `Pipfile` — Python (check for `flask`, `django`, `fastapi`, `uvicorn`, `gunicorn`)
- `pom.xml` / `build.gradle` / `build.gradle.kts` — Java (check for `spring-boot`)
- `Gemfile` — Ruby (check for `rails`)
- `composer.json` — PHP (check for `laravel`)
- `*.csproj` / `*.sln` — .NET
- `Dockerfile` — Already has one?
- `.dockerignore` — Exists?
- `docker-compose.yml` / `docker-compose.yaml` — Multi-service architecture?
- `.env` / `.env.example` / `.env.local` — Environment variables?
- `*.tf` — Terraform modules?
- `Chart.yaml` — Helm chart?

Then tell the user what you detected and ask:

5. **Is my analysis correct?** (confirm language, framework, detected services)

6. **What port does your application listen on?** (often detectable from code, but confirm)

7. **Should the application be publicly accessible?** (exposed to the internet via HTTPS)

### Group 3: Database & Services

8. **Does your project need a database?**
   - If YES: which type? (PostgreSQL, MySQL, MongoDB, Redis)
   - Look for database connection strings in code, ORM configs (Prisma, TypeORM, SQLAlchemy, GORM, etc.)

9. **Is this deployment for development/testing or production?**
   - Regardless of the answer, check the **Blueprint catalog first** (Phase 3C) before reaching for a native database resource or a hand-rolled Terraform service — the catalog can offer both cloud-managed and container-based variants, so it's worth checking even for dev/test.
   - **Dev/test, no blueprint match** -> Use Qovery's native database service in Container mode (cheaper, runs on the Kubernetes cluster, fast to provision, disposable).
   - **Production, no blueprint match** -> Managed-mode database (e.g. AWS RDS) or a hand-rolled Terraform service for setups the catalog doesn't cover (e.g. a custom Aurora Serverless topology).

10. **Do you need any additional cloud resources?** (S3 buckets, Redis cache, message queues, Lambda functions, CDN, etc.)
    - Check the **Blueprint catalog** (Phase 3C) first, in any environment. Anything not covered by a blueprint can still be provisioned via a hand-rolled Qovery Terraform service.

11. Whatever gets deployed above (blueprint, native container/managed database, or Terraform service), the application(s) depending on it MUST have their environment variables wired to it via **alias** before the deployment is considered complete (Phase 6.10). Never leave an application pointing at a hardcoded or missing connection string for a piece of infrastructure that was just provisioned.

### Group 4: Deployment Method

11. **How would you like to deploy?**
    - **Option A: CLI + API** — Quickest way to get started. Good for development and staging environments. Uses `qovery` CLI commands and `curl` API calls to create and deploy services.
    - **Option B: Terraform Provider (Recommended for production)** — Declarative, reproducible, version-controlled infrastructure as code. Creates a `qovery.tf` file that defines your entire stack. Can be committed to git and used in CI/CD pipelines.

After gathering all answers, proceed to the appropriate phase.

---
