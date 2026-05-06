## PHASE 5: Deploy the Portal on Qovery

### 5.1 Save Generated Code

Write all generated files to the `builder-portal/` directory within the `qovery-builder-platform` repository (created by `qovery-builder-env`).

### 5.2 Commit to Git

```bash
cd qovery-builder-platform
git add builder-portal/
git commit -m "feat: add builder self-service portal

Vite + TypeScript + React + TanStack Router + Tailwind frontend
Express + TypeScript backend with SSO (${SSO_PROVIDER})
Qovery API integration for environment provisioning
Multi-template support with ${template_count} templates"

git push origin main
```

### 5.3 Create Portal Project and Application in Qovery

```bash
# Create a project for the portal
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-portal", "description": "Self-service builder portal"}'

# Create the portal environment
curl -s -X POST "https://api.qovery.com/project/{portalProjectId}/environment" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "production", "cluster": "{clusterId}", "mode": "PRODUCTION"}'

# Create the portal application
curl -s -X POST "https://api.qovery.com/environment/{portalEnvId}/application" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "portal",
    "git_repository": {
      "url": "{git-repo-url}",
      "branch": "main",
      "root_path": "/builder-portal",
      "provider": "{git-provider}"
    },
    "build_mode": "DOCKER",
    "dockerfile_path": "Dockerfile",
    "cpu": 500,
    "memory": 512,
    "min_running_instances": 1,
    "max_running_instances": 1,
    "ports": [
      {"internal_port": 3000, "external_port": 443, "publicly_accessible": true, "protocol": "HTTP", "is_default": true, "name": "portal"}
    ],
    "healthchecks": {
      "readiness_probe": {
        "type": {"http": {"path": "/api/templates", "port": 3000, "scheme": "HTTP"}},
        "initial_delay_seconds": 15,
        "period_seconds": 10,
        "timeout_seconds": 5,
        "failure_threshold": 3
      }
    },
    "auto_deploy": true
  }'
```

### 5.4 Set Environment Variables

Set all 11 environment variables from Phase 3.1 on the portal application:

```bash
# Non-secret variables
for var in "SSO_PROVIDER={provider}" "PORTAL_URL=https://{domain}" "COMPANY_NAME={name}" "PRIMARY_COLOR={color}" "MAX_ENVIRONMENTS_PER_BUILDER={n}" "SSO_CLIENT_ID={id}" "SSO_ISSUER_URL={url}" "COMPANY_LOGO_URL={logo}"; do
  KEY="${var%%=*}"
  VALUE="${var#*=}"
  curl -s -X POST "https://api.qovery.com/application/{portalAppId}/environmentVariable" \
    -H "Authorization: Token $QOVERY_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"$KEY\", \"value\": \"$VALUE\"}"
done

# Secret variables
for var in "QOVERY_API_TOKEN={token}" "SSO_CLIENT_SECRET={secret}" "SESSION_SECRET={session}"; do
  KEY="${var%%=*}"
  VALUE="${var#*=}"
  curl -s -X POST "https://api.qovery.com/application/{portalAppId}/secret" \
    -H "Authorization: Token $QOVERY_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"$KEY\", \"value\": \"$VALUE\"}"
done
```

### 5.5 Configure Custom Domain (if provided)

```bash
curl -s -X POST "https://api.qovery.com/application/{portalAppId}/customDomain" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain": "{custom-domain}", "generate_certificate": true}'
```

After creating the custom domain, Qovery will provide DNS records to set up. Present them to the platform engineer:
> "Set up the following DNS record for your custom domain:
> - Type: CNAME
> - Name: {subdomain}
> - Value: {qovery-generated-cname-target}
>
> Once the DNS record is propagated, the portal will be accessible at https://{custom-domain}"

### 5.6 Deploy and Verify

```bash
curl -s -X POST "https://api.qovery.com/environment/{portalEnvId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Watch deployment and verify:
1. Poll environment status until DEPLOYED
2. Open the portal URL in a browser
3. Verify SSO login works (redirect to provider, callback, session created)
4. Verify the dashboard loads (shows "Create your first workspace" if empty)
5. Verify the templates page shows the configured templates
6. Optionally: create a test environment to verify the full flow

Present the result:

> **Builder Portal is live!**
>
> - URL: `https://{portal-url}`
> - SSO: {provider} configured
> - Templates: {N} available
>
> **Share this URL with your builders.** They can log in with their company credentials and start creating workspaces immediately.
>
> **Console:** https://console.qovery.com/organization/{orgId}/project/{portalProjectId}/environment/{portalEnvId}

---
