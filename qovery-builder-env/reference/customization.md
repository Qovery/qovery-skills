## Customization Guide

After the blueprint is running, customize any of these settings. All changes are optional — the defaults work for most teams.

### Change TTL (auto-stop/auto-delete)

**Default:** 24h auto-stop, 7d auto-delete.

To change the auto-stop schedule, edit the `ttl-auto-shutdown` cron job in the Qovery Console or update the `scheduled_at` field via the API.

Common schedules:

| TTL | Cron Expression | Description |
|-----|----------------|-------------|
| Business hours | `0 20 * * 1-5` | Stop at 8pm weekdays |
| 8 hours | `0 */8 * * *` | Stop every 8 hours |
| 24 hours (default) | `0 */24 * * *` | Stop every 24 hours |
| 1 week | `0 0 * * 0` | Stop every Sunday midnight |

To add auto-delete after extended inactivity, use `templates/scripts/ttl-delete-job.sh` as a reference.

### Change Resource Limits

**Default:** 1 CPU, 2GB RAM for workspace; 250m CPU, 256MB RAM for database.

Edit the workspace or database service in the Qovery Console, or via API:
```bash
curl -s -X PUT "https://api.qovery.com/application/{appId}" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"cpu": 2000, "memory": 4096, ...all other required fields...}'
```

IMPORTANT: `PUT` requires ALL fields, not just the ones being changed. Fetch the current config first with `GET /application/{appId}`.

### Switch Isolation Mode

**Default:** Project-per-builder (each builder gets their own Qovery project — maximum isolation).

**Alternative:** Shared project — all builder environments in a single project. Simpler to manage, but builders can see each other's environment names.

To switch: when provisioning new builders, skip the "create project" step and clone the blueprint into the shared `builder-workspaces` project instead. Use a shared RBAC role instead of per-builder roles.

### Add SSO

Configure SSO in the Qovery Console:
1. Go to Organization Settings > Authentication
2. Set up SAML or OIDC with your provider (Google Workspace, Okta, Azure AD)
3. Builders will authenticate with their company credentials

Documentation: https://www.qovery.com/docs/using-qovery/configuration/organization/authentication

### Add a Database to the Blueprint

By default, the blueprint does not include a database — builders can provision one on demand by asking the AI tools ("I need a PostgreSQL database for my app") and Qovery will create one via the deploy skill.

If most builders need a database, add one to the blueprint so it's automatically available in every cloned environment:

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

After adding, redeploy the blueprint to validate, then stop it. Future builder clones will include the database automatically. Connection strings are auto-injected as environment variables by Qovery (`QOVERY_DATABASE_*`).

Note: Each cloned environment gets its own empty database. Data is not shared between builders.

### Git Auto-Load (Per-Builder Project)

The workspace entrypoint automatically clones a git repo on startup when `GIT_REPO_URL` is set. This is configured per-builder as Qovery environment variables.

**Supported providers:**

| Provider | Token Username (auto-detected from URL) |
|---|---|
| GitHub (`github.com`) | `x-access-token` — use a GitHub PAT or fine-grained token |
| GitLab (`gitlab.com` or self-hosted) | `oauth2` — use a GitLab PAT or project token |
| Bitbucket (`bitbucket.org`) | `x-token-auth` — use a Bitbucket app password |
| Other | `x-access-token` (default fallback) |

**Behavior:**
- First start: clones the repo, installs dependencies (npm/pip if detected)
- Container restart: pulls latest changes from the configured branch
- If `GIT_REPO_URL` is not set: starts with an empty project directory

**Example env vars for a builder:**
```
GIT_REPO_URL=https://github.com/myorg/sales-dashboard.git
GIT_TOKEN=ghp_xxxxxxxxxxxx        (secret)
GIT_BRANCH=main
GIT_USER_NAME=Alice Smith
GIT_USER_EMAIL=alice@company.com
```

### Live Preview

The workspace includes two mechanisms for previewing web apps:

**1. Live Preview extension (`ms-vscode.live-server`)**
- Works for static HTML/CSS/JS files
- Right-click a `.html` file → "Show Preview" → opens inline in VS Code
- Auto-refreshes on file save
- Runs on port 3100 (configurable via VS Code settings)

**2. Auto port forwarding for dev servers**
- When Claude Code or the builder runs `npm run dev` (or any dev server), VS Code detects the port automatically
- A notification appears: "Your application running on port 5173 is available"
- Click "Open in Browser" → opens in VS Code's Simple Browser panel
- Access externally via code-server's built-in proxy: `https://{workspace-url}/proxy/{port}/`
- Configured via `remote.autoForwardPorts: true` in VS Code settings

**Non-tech builder flow:**
1. Talk to Claude Code: "Show me a preview of the app"
2. Claude Code runs the dev server
3. VS Code detects the port → builder clicks to preview
4. Preview opens in a panel next to the code

### Pre-load Custom Skills

The workspace container comes with all Qovery skills pre-installed. To add your own company-specific skills (custom deployment workflows, internal tool generators, etc.), extend the Dockerfile:

```dockerfile
# Add your custom skills to the workspace
COPY my-company-skills/ /home/coder/.config/opencode/skills/
```

Or add custom slash commands:
```dockerfile
COPY my-commands/ /home/coder/.config/opencode/commands/
```

Skills placed in `/home/coder/.config/opencode/skills/` are automatically discovered by OpenCode and Claude Code. Each skill must be a directory containing a `SKILL.md` file with the proper frontmatter.

To add skills at runtime (without rebuilding the image), mount a volume:
```
# Set as a Qovery environment variable or in the service configuration
# Mount path: /home/coder/.config/opencode/skills/my-custom-skill
```

### Add or Remove VS Code Extensions

The workspace uses the Microsoft VS Code Marketplace (configured via `EXTENSIONS_GALLERY` env var in the Dockerfile). To add more extensions, add lines to the Dockerfile:

```dockerfile
RUN code-server --install-extension <publisher>.<extension-name>
```

To revert to Open VSX (the default code-server registry), remove the `EXTENSIONS_GALLERY` environment variable from the Dockerfile.

### Add a Visual Builder Service

To add a Lovable-like visual builder to the blueprint, add a new service:

1. Add a container or application service to the blueprint environment
2. Point it to the visual builder's Docker image or git repository
3. Expose on a separate port (e.g., 3000, public HTTPS)
4. Redeploy the blueprint to validate
5. Stop the blueprint
6. Future builder clones will include the visual builder automatically

Existing builder environments need to be re-cloned to pick up the new service.

### Production Graduation

When a builder's app is ready for production:

1. **Platform team reviews** the builder's code (security, quality, dependencies)
2. **Clone to staging**: `qovery environment clone --environment "workspace" --name "staging-{app}"`
   - Deploy to a staging cluster or environment with stricter controls
3. **Validate**: run health checks, test with production-like data
4. **Promote to production**: clone the staging environment with production mode
   - Switch database from container to managed (e.g., RDS)
   - Increase CPU/memory
   - Set up custom domain and monitoring

IMPORTANT: Builders should NOT have direct access to production. Only the platform team (Admin role) manages production resources.

### Token Savings Analytics (RTK)

RTK is pre-installed in every builder workspace. It auto-rewrites shell commands to reduce LLM token consumption by 60-90% when using Claude Code or OpenCode. No configuration needed — the hooks are set up during the Docker build.

To view token savings across builder environments:
```bash
# Inside a builder workspace
rtk gain                    # Summary stats
rtk gain --graph            # ASCII graph (last 30 days)
rtk gain --daily            # Day-by-day breakdown
rtk discover                # Find missed savings opportunities
```

The platform team can use these metrics to track API cost efficiency across builders.

- RTK docs: https://www.rtk-ai.app/guide
- GitHub: https://github.com/rtk-ai/rtk

### Enterprise Security: Egress Firewall

For builders working with sensitive data (CRM, financial, customer PII), add a Squid egress proxy that controls which URLs the workspace can access. This prevents data exfiltration and ensures compliance.

This requires a more complex Dockerfile with:
1. **s6-overlay** as PID 1 (process supervisor managing code-server, Squid, dnsmasq)
2. **Squid** — forward HTTP/HTTPS proxy on 127.0.0.1:3128 with hostname ACL
3. **dnsmasq** — local DNS with per-domain forwarders
4. An **allowlist** of permitted domains (GitHub, npm, PyPI, Qovery API, etc.)

All outbound traffic is routed through the proxy, and only allowlisted domains are permitted. See the Tint devcontainer for a production reference implementation of this pattern: https://github.com/tint-ai/devcontainer

### Idle Monitor

Instead of a fixed 24h TTL, add an idle monitor that stops the environment after N minutes of no terminal or editor activity. This requires s6-overlay to manage the monitor as a service alongside code-server.

### Terraform

To terraformize the existing builder environment setup into `.tf` manifests, use the `qovery-terraform` skill (coming soon). It will reverse-engineer the current Qovery configuration into Terraform resources using the Qovery Terraform Provider.

For manual Terraform setup, see the Qovery Terraform Provider docs:
https://registry.terraform.io/providers/Qovery/qovery/latest/docs

Key resources:
- `qovery_project` — one per builder (or shared)
- `qovery_environment` — cloned from blueprint
- `qovery_application` — workspace service
- `qovery_database` — PostgreSQL

Use a `for_each` loop over a map of builders to provision at scale.
