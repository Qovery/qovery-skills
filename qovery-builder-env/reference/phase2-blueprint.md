## Phase 2: Create Blueprint

The blueprint is a fully configured environment that will be cloned for each builder. It contains the workspace service (all-in-one container), a PostgreSQL database, and a TTL auto-stop cron job.

### 2.1 Create the project

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-workspaces", "description": "Self-service builder environments"}'
```

Or via CLI:
```bash
qovery project create --name "builder-workspaces"
```

### 2.2 Set AI API keys as project secrets

Set the Anthropic API key (from Phase 1.3) as a project-level secret so all builder environments inherit it automatically:

```bash
curl -s -X POST "https://api.qovery.com/project/{projectId}/environmentVariable" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"key": "ANTHROPIC_API_KEY", "value": "{key-or-placeholder}", "scope": "PROJECT", "is_secret": true}'
```

Builders never see the key value — it's encrypted and injected at runtime.

### 2.3 Create the blueprint environment

```bash
curl -s -X POST "https://api.qovery.com/project/{projectId}/environment" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-blueprint", "cluster": "{clusterId}", "mode": "DEVELOPMENT"}'
```

### 2.4 Add the workspace service

The workspace uses `templates/Dockerfile` — the combined all-in-one container with VS Code, OpenCode, Claude Code, Qovery CLI, Node.js, Python, and Git.

The Dockerfile needs to be in a git repository for Qovery to build it. Ask the user:
> "Which git repository should I push the workspace Dockerfile to? (Or provide a path if it's already in a repo)"

Options:
- Push to an existing repo (e.g., `infra/builder-workspace/Dockerfile`)
- Create a new repo (e.g., `qovery-builder-platform`)

After the Dockerfile is in git, create the workspace application:

```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/application" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "workspace",
    "description": "Builder workspace — VS Code + OpenCode + Claude Code",
    "git_repository": {
      "url": "{git-repo-url}",
      "branch": "main",
      "root_path": "{path-to-dockerfile-dir}",
      "provider": "GITHUB"
    },
    "build_mode": "DOCKER",
    "dockerfile_path": "Dockerfile",
    "cpu": 1000,
    "memory": 2048,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {"internal_port": 8080, "external_port": 443, "publicly_accessible": true, "protocol": "HTTP", "is_default": true, "name": "ide"}
    ],
    "healthchecks": {
      "readiness_probe": {
        "type": {"tcp": {"port": 8080}},
        "initial_delay_seconds": 30,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "failure_threshold": 9
      }
    },
    "auto_preview": false,
    "auto_deploy": false
  }'
```

### 2.5 Add PostgreSQL database

```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/database" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "postgres",
    "type": "POSTGRESQL",
    "version": "16",
    "mode": "CONTAINER",
    "accessibility": "PRIVATE",
    "cpu": 250,
    "memory": 256,
    "storage": 10
  }'
```

### 2.6 Create TTL auto-stop cron job

Each builder environment auto-stops after 24 hours to save costs. The job uses `curlimages/curl` with a raw Dockerfile (no git repo needed).

First, generate a shutdown token:
```bash
# The token value must NOT be displayed — see auth.md security rules
qovery token create --name "blueprint-ttl" --duration 8760h > /dev/null
```

Then create the cron job — use the reference script at `templates/scripts/ttl-stop-job.sh` for the full API call. The key parameters:
- Image: `curlimages/curl:8.11.1` via `dockerfile_raw`
- Schedule: `0 */24 * * *` (every 24 hours)
- Command: `curl -sf -X POST https://api.qovery.com/environment/{envId}/stop -H "Authorization: Token $SHUTDOWN_TOKEN"`
- The `SHUTDOWN_TOKEN` is set as a secret on the job

### 2.7 Deploy and validate the blueprint

```bash
# Deploy
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/deploy" \
  -H "Authorization: Bearer $(qovery auth token --print)"
```

Watch the deployment — poll statuses every 15-30 seconds:
```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{blueprintEnvId}/statuses" | jq '{
    environment: .environment.state,
    services: [
      (.applications[] | {name: .name, state, type: "app"}),
      (.databases[] | {name: .name, state, type: "db"}),
      (.jobs[] | {name: .name, state, type: "job"})
    ]
  }'
```

When all services are `DEPLOYED`, verify the workspace is accessible:
```bash
# Get the workspace URL
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{workspaceAppId}/link" | jq '.results[0].url'
```

Open the URL and confirm VS Code loads in the browser. Check the terminal works (`opencode --version`, `claude --version`, `qovery version`).

On failure: fetch logs with `qovery log --service "workspace" --since 10m` and diagnose.

### 2.8 Stop the blueprint

The blueprint is a template — it should not consume resources when idle:
```bash
curl -s -X POST "https://api.qovery.com/environment/{blueprintEnvId}/stop" \
  -H "Authorization: Bearer $(qovery auth token --print)"
```

Confirm to the user:
> "Blueprint created and validated. The workspace loaded correctly at {url}.
> Blueprint is now stopped — it will be cloned for each builder in Phase 3."
