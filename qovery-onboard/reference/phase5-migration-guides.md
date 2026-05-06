## PHASE 5: Migration Guides

### 5.1 Migrating from Heroku (Detailed)

#### Concept Mapping

| Heroku | Qovery | Notes |
|---|---|---|
| **Dyno** | **Application** | Container running your code |
| **Add-on (Postgres/Redis)** | **Database** | Managed or container mode |
| **Config Vars** | **Environment Variables** | Use aliases for DB connections |
| **Pipeline** | **Deployment Stages** | Control deployment order |
| **Review Apps** | **Preview Environments** | Auto-created per PR |
| **Procfile** | **Dockerfile** | Explicit container definition |
| **Buildpack** | **Dockerfile** | You control the build |
| **Release phase** | **Lifecycle Job** | DB migrations, seeding |
| **Heroku CLI** | **Qovery CLI** | Similar commands, different syntax |
| **heroku.yml** | **qovery.tf** (Terraform) | Infrastructure as code |

#### Step 1: Create Dockerfiles

Heroku uses Buildpacks; Qovery uses Dockerfiles. Create a Dockerfile for each app. The **qovery-deploy** skill has templates for all common frameworks — ask "deploy my application with Qovery" after onboarding.

Common Heroku Procfile to Dockerfile mappings:

**Ruby/Rails** (`web: bundle exec puma -C config/puma.rb`):
```dockerfile
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y build-essential libpq-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && bundle install
COPY . .
RUN SECRET_KEY_BASE=placeholder bundle exec rake assets:precompile 2>/dev/null || true
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

**Node.js** (`web: node server.js`):
```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

**Python/Django** (`web: gunicorn myproject.wsgi`):
```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN python manage.py collectstatic --noinput 2>/dev/null || true
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "myproject.wsgi:application"]
```

#### Step 2: Import Environment Variables

Use the Qovery CLI to import Heroku config vars directly:

```bash
# Install Heroku CLI if not already: brew install heroku/brew/heroku
# Login to Heroku: heroku login

# Export Heroku vars and import into Qovery
heroku config --app your-heroku-app --json | \
  qovery env parse --heroku-json > heroku.env && \
  qovery env import heroku.env && \
  rm heroku.env
```

IMPORTANT: Review the imported variables and mark sensitive ones (API keys, secrets, passwords) as **Secret** type in Qovery, not regular environment variables.

#### Step 3: Database Migration

For database connections:
- Create a Qovery database (managed mode for production, container for dev)
- Use an **alias** for `DATABASE_URL` pointing to `QOVERY_DATABASE_POSTGRESQL_{NAME}_CONNECTION_URI_INTERNAL`
- Do NOT hardcode the Heroku database URL

For data migration:
1. Make the Qovery database temporarily publicly accessible
2. Use `pg_dump` / `pg_restore` to copy data:
   ```bash
   # Dump from Heroku
   heroku pg:backups:capture --app your-heroku-app
   heroku pg:backups:download --app your-heroku-app

   # Restore to Qovery (use port-forward for secure access)
   qovery port-forward --service "postgres" --port 5432:5432
   pg_restore -h localhost -p 5432 -U qovery_user -d qovery_db latest.dump
   ```
3. Set the database back to private

#### Step 4: Release Phase → Lifecycle Job

If you have a Heroku release phase for database migrations:
```yaml
# Heroku Procfile
release: bundle exec rake db:migrate
```

Create a Qovery lifecycle job instead:
- Source: same Git repo
- Schedule: `on_start` (runs on every deployment)
- Command: `bundle exec rake db:migrate`
- Deployment stage: same as or before the backend

#### Heroku FAQ for Qovery

| Heroku Question | Qovery Answer |
|---|---|
| How do I set custom domains? | Application Settings > Domains, or via API |
| How do I monitor my apps? | Deploy Datadog or Grafana via Helm, or use Qovery Observe |
| Do you have Review Apps? | Yes — Preview Environments, auto-created per PR |
| How do I rollback? | Deployment History > select previous version > Redeploy |
| How does auto-scaling work? | Set `min_running_instances < max_running_instances` |
| Can I get a shell / SSH? | `qovery shell --service "name"` or Console shell button |
| How do I manage DB migrations? | Lifecycle Jobs with `on_start` schedule |
| Can I use Terraform? | Yes — Qovery Terraform Provider, full IaC support |

### 5.2 Migrating from Vercel / Netlify

| Vercel/Netlify Concept | Qovery Equivalent |
|---|---|
| Project | Application |
| Preview Deployment | Preview Environment |
| Environment Variables | Environment Variables (with scopes, aliases, overrides) |
| Serverless Functions | Applications or Jobs |
| Edge Functions | Not directly supported — use Applications |
| Custom Domains | Application Settings > Domains |
| Build Command | Dockerfile |

**Key differences:**
- Vercel auto-detects framework; Qovery uses Dockerfiles (more control but requires a Dockerfile)
- The **qovery-deploy** skill creates Dockerfiles automatically for React, Vite, Next.js, and more
- SSR apps (Next.js) work natively with standalone output mode
- Static sites use an nginx Dockerfile (the deploy skill generates this)

**Migration steps:**
1. Create a Dockerfile (use the qovery-deploy skill)
2. Import environment variables from Vercel project settings
3. Set up custom domains in Qovery
4. Configure Preview Environments for PR-based deployments

### 5.3 Migrating from Render / Railway / Fly.io

| Concept | Qovery Equivalent |
|---|---|
| Service / App | Application |
| Database | Database (managed or container) |
| Cron Job | Cron Job |
| Environment Groups | Environment scope variables |
| Blueprint (Render) | Terraform manifest |
| Dockerfile | Dockerfile (compatible) |

**Migration steps:**
1. Dockerfiles are usually compatible — copy them directly
2. Export environment variables and import into Qovery
3. Create databases in Qovery with the same type and version
4. Migrate data using `pg_dump`/`pg_restore` (or equivalent for MySQL/MongoDB)
5. Update custom domain DNS to point to Qovery

### 5.4 Migrating from Manual Kubernetes

If you're running Kubernetes manually (kubectl apply, Helm, Kustomize):

**Option A: BYOK** — Install Qovery on your existing cluster (Phase 4). Your existing workloads continue running; Qovery manages new deployments alongside them.

**Option B: Re-deploy on Qovery Managed Cluster** — Let Qovery manage the cluster entirely. Migrate workloads:

| K8s Resource | Qovery Equivalent |
|---|---|
| Deployment | Application or Container |
| StatefulSet | Application with persistent storage |
| CronJob | Cron Job |
| Job | Lifecycle Job |
| ConfigMap | Environment Variables |
| Secret | Secrets (environment variables marked as secret) |
| Ingress | Application port configuration (publicly_accessible: true) |
| Service | Automatic (Qovery creates services internally) |
| Helm Release | Helm service in Qovery |
| PVC | Application storage configuration |

**Migration steps:**
1. For each Deployment: create a Qovery Application or Container
2. For ConfigMaps/Secrets: import as Qovery environment variables
3. For Helm charts: create Qovery Helm services pointing to the same charts
4. For custom resources: use Qovery Terraform services or BYOK
5. Consider using `qovery terraform export` if you want to manage as Terraform

---

