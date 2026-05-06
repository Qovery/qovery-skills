## PHASE 3: Configure the Portal

### 3.1 Environment Variables

Set the following environment variables on the portal application in Qovery:

| Variable | Secret? | Description |
|----------|---------|-------------|
| `QOVERY_API_TOKEN` | Yes | Platform API token — the portal uses this to call the Qovery API |
| `SSO_PROVIDER` | No | SSO provider: `google`, `okta`, `azure`, or `oidc` |
| `SSO_CLIENT_ID` | No | OAuth2 client ID from the SSO provider |
| `SSO_CLIENT_SECRET` | Yes | OAuth2 client secret from the SSO provider |
| `SSO_ISSUER_URL` | No | OIDC issuer URL (not needed for Google) |
| `PORTAL_URL` | No | Public URL of the portal (used for SSO callback) |
| `SESSION_SECRET` | Yes | Random string for session encryption (generate with `openssl rand -hex 32`) |
| `COMPANY_NAME` | No | Displayed in the header and login page |
| `COMPANY_LOGO_URL` | No | Logo URL (optional) |
| `PRIMARY_COLOR` | No | Hex color for branding (e.g., `#2563EB`) |
| `MAX_ENVIRONMENTS_PER_BUILDER` | No | Max environments per builder (e.g., `3`) |

### 3.2 SSO Setup Guide

Guide the platform engineer through configuring SSO with their chosen provider:

**Google Workspace:**
1. Go to https://console.cloud.google.com/apis/credentials
2. Create a new OAuth 2.0 Client ID (Web application)
3. Add authorized redirect URI: `https://{portal-domain}/auth/callback`
4. Copy the Client ID and Client Secret
5. Set `SSO_PROVIDER=google`, `SSO_CLIENT_ID`, `SSO_CLIENT_SECRET`

**Okta:**
1. Go to Okta Admin Console > Applications > Create App Integration
2. Select OIDC - OpenID Connect, Web Application
3. Set Sign-in redirect URI: `https://{portal-domain}/auth/callback`
4. Copy Client ID, Client Secret, and Okta domain
5. Set `SSO_PROVIDER=oidc`, `SSO_ISSUER_URL=https://{okta-domain}`, `SSO_CLIENT_ID`, `SSO_CLIENT_SECRET`

**Azure AD (Entra ID):**
1. Go to Azure Portal > Microsoft Entra ID > App Registrations > New Registration
2. Set Redirect URI: `https://{portal-domain}/auth/callback` (Web type)
3. Create a Client Secret under Certificates & Secrets
4. Copy Application (client) ID and client secret value
5. Set `SSO_PROVIDER=oidc`, `SSO_ISSUER_URL=https://login.microsoftonline.com/{tenant-id}/v2.0`, `SSO_CLIENT_ID`, `SSO_CLIENT_SECRET`

**Generic OIDC:**
1. Register the portal as an OIDC client with your provider
2. Set the redirect URI: `https://{portal-domain}/auth/callback`
3. Set `SSO_PROVIDER=oidc`, `SSO_ISSUER_URL`, `SSO_CLIENT_ID`, `SSO_CLIENT_SECRET`

### 3.3 Template Configuration

If the platform engineer has multiple blueprint environments, update the `builder-platform-config.yaml` to include a `templates` section:

```yaml
templates:
  - name: "Sales Tools"
    description: "Build CRM integrations, sales dashboards, and pipeline tools"
    blueprint_env_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    icon: "chart-bar"
  - name: "Data Analytics"
    description: "Build data visualization, reporting, and analytics tools"
    blueprint_env_id: "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
    icon: "table"
  - name: "General Purpose"
    description: "Full-stack workspace — build anything"
    blueprint_env_id: "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"
    icon: "code"
```

Each template maps to a different blueprint environment created by the `qovery-builder-env` skill. The portal reads this config and presents the templates as cards on the "Create New Workspace" page.

If only one blueprint exists, the template picker is skipped and the builder goes directly to environment creation.

