## PHASE 8: Advanced Patterns

### 8.1 Custom Domains

After deployment, add custom domains:

Via API:
```bash
curl -s -X POST "https://api.qovery.com/application/{appId}/customDomain" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain": "app.example.com"}'
```

Then create a CNAME DNS record pointing to the Qovery-generated domain. Qovery automatically provisions SSL/TLS certificates via Let's Encrypt.

### 8.2 Autoscaling

Configure horizontal pod autoscaling:

```hcl
resource "qovery_application" "backend" {
  # ... other config ...
  min_running_instances = 2
  max_running_instances = 10
  # HPA is automatically enabled when min != max
}
```

### 8.3 Persistent Storage

```hcl
resource "qovery_application" "backend" {
  # ... other config ...
  storage = [
    {
      type        = "FAST_SSD"
      size        = 10    # GB
      mount_point = "/data"
    }
  ]
}
```

### 8.4 Terraform Exporter

If the user already has services configured via the Qovery Console UI and wants to switch to Terraform:

1. Go to the environment in Qovery Console
2. Click environment settings (three dots) > "Export as Terraform"
3. Download the generated `.tf` files
4. Import existing resources to avoid recreating them:
   ```bash
   terraform import qovery_environment.main {environment-id}
   terraform import qovery_application.backend {application-id}
   terraform import qovery_database.postgres {database-id}
   ```
5. Run `terraform plan` — should show no or minimal changes

### 8.5 Git Provider Detection

Detect the git provider from the remote URL to set the correct `provider` field:

```bash
git remote get-url origin
```

- Contains `github.com` -> `GITHUB`
- Contains `gitlab.com` or a self-hosted GitLab domain -> `GITLAB`
- Contains `bitbucket.org` -> `BITBUCKET`

IMPORTANT: The user's Qovery organization must have the corresponding git provider connected (GitHub App installed, GitLab token, or Bitbucket integration). Check this at Organization Settings > Git Repository Access in the Qovery Console.

### 8.6 Monorepo Support

For monorepos with multiple services in subdirectories:

```
my-repo/
├── backend/
│   ├── Dockerfile
│   └── src/
├── frontend/
│   ├── Dockerfile
│   └── src/
├── jobs/
│   └── migrate/
│       └── Dockerfile
├── terraform/
│   └── s3-bucket/
│       └── main.tf
└── qovery.tf
```

Set `root_path` for each service:
- Backend: `root_path = "/backend"`
- Frontend: `root_path = "/frontend"`
- Migration job: `root_path = "/jobs/migrate"`
- Terraform service: `root_path = "/terraform/s3-bucket"`

Each service gets its own Dockerfile in its subdirectory.

### 8.7 Environment Cloning for Preview/Staging

Qovery supports cloning entire environments for preview or staging:

Via API:
```bash
curl -s -X POST "https://api.qovery.com/environment/{envId}/clone" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "preview-pr-42",
    "mode": "DEVELOPMENT",
    "cluster_id": "{clusterId}"
  }'
```

This creates a full copy of the environment with all its services, databases, and configuration — ideal for preview environments on pull requests.

### 8.8 Secure Local Access via Port-Forward

Use `qovery port-forward` to create a secure encrypted tunnel from your local machine to any service in the cluster — without making it publicly accessible. This is the recommended way to connect to databases and internal services for development, debugging, and administration.

#### Connect to Databases Locally

Databases should NEVER be publicly exposed. Use port-forward instead:

```bash
# PostgreSQL
qovery port-forward --service "postgres" --port 5432:5432
# Then connect: psql -h localhost -p 5432 -U myuser -d mydatabase

# MySQL
qovery port-forward --service "mysql" --port 3306:3306
# Then connect: mysql -h 127.0.0.1 -P 3306 -u myuser -p mydatabase

# MongoDB
qovery port-forward --service "mongodb" --port 27017:27017
# Then connect: mongosh "mongodb://localhost:27017/mydatabase"

# Redis
qovery port-forward --service "redis" --port 6379:6379
# Then connect: redis-cli -h localhost -p 6379
```

#### Use a Different Local Port (Avoid Conflicts)

If the default port is already in use locally:

```bash
# Forward remote 5432 to local 15432
qovery port-forward --service "postgres" --port 15432:5432
# Connect on localhost:15432
```

#### Run Your Local App Against a Remote Database

This is extremely useful for development — run your app locally but connect to the real database in the cluster:

```bash
# Terminal 1: start the tunnel
qovery port-forward --service "postgres" --port 5432:5432

# Terminal 2: run your local app pointing to the forwarded port
DATABASE_URL=postgresql://user:pass@localhost:5432/mydb npm run dev
```

You can use `qovery env parse` to export all environment variables from the remote environment as a local `.env` file, then override `DATABASE_URL` to point to `localhost`.

#### Access Internal Services for Debugging

Forward to applications or containers that are not publicly exposed:

```bash
# Forward an internal backend API
qovery port-forward --service "backend" --port 8080:8080
curl http://localhost:8080/api/health

# Forward a Helm-deployed service (e.g., admin panel)
qovery port-forward --service "windmill" --port 8000:8000
```

#### Important Notes

- The tunnel is **encrypted and authenticated** via Kubernetes — no credentials traverse the public internet
- Keep the terminal running — press Ctrl+C to close the tunnel
- If the pod restarts, the tunnel drops and must be re-established (just re-run the command)
- The `--port` flag uses `local:remote` format (e.g., `5432:5432` or `15432:5432`)
- This is for **development and debugging** — for production service-to-service communication, use the internal hostnames (`_HOST_INTERNAL` variables)

---

