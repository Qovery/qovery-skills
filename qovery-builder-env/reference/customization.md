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
