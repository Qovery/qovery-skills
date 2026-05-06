## PHASE 4: Deployment Plan Summary

Before deploying, present a complete summary:

> **Builder Portal Deployment Plan**
>
> **Portal Application:**
> - Name: `builder-portal`
> - Domain: `{custom_domain or 'Qovery-generated URL'}`
> - SSO Provider: {Google Workspace / Okta / Azure AD / OIDC}
> - Branding: {company_name}, {primary_color}
>
> **Templates Available to Builders:**
>
> | Template | Blueprint Env | Description |
> |----------|--------------|-------------|
> | Sales Tools | xxx-xxx | Build CRM integrations and dashboards |
> | Data Analytics | yyy-yyy | Build reporting and analytics tools |
>
> **Configuration:**
> - Max environments per builder: {N}
> - Builders can extend TTL: {yes/no} (max: {duration})
> - Builders can delete environments: {yes/no}
>
> **Deployment Target:**
> - Organization: {org_name}
> - Cluster: {cluster_name} ({region})
> - Project: builder-portal *(new)*
> - CPU: 500m, Memory: 512MB
> - Port: 3000 (HTTPS, public)
>
> **Environment Variables:** {count} vars ({secret_count} secrets)
>
> **Generated Files:**
> - builder-portal/ ({file_count} files)
> - Dockerfile (multi-stage Node.js build)

Ask for explicit confirmation before proceeding.

---
