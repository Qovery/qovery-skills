---
name: qovery-builder-portal
description: Generates and deploys a self-service web portal for non-tech builders. Provides SSO login, one-click environment creation from templates, dashboard with status/URLs/TTL, and start/stop/extend/delete controls. Built with Vite + TypeScript + React + TanStack Router + Tailwind (frontend) and Express + TypeScript (backend). Deployed on Qovery. Reads builder-platform-config.yaml from the qovery-builder-env skill. Use when a platform engineer needs a web UI on top of Qovery for non-technical users (after qovery-builder-env has been run).
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: builder-portal
---

# Qovery Builder Portal Skill

This skill generates and deploys a self-service web portal that lets non-technical users (sales, finance, operations, marketing) create and manage builder environments through a simple UI — without requiring any knowledge of Qovery, Kubernetes, or infrastructure.

The portal is deployed on Qovery itself (dogfooding) and calls the Qovery API behind the scenes. Builders authenticate via SSO, pick a template, and click "Create" — the portal handles blueprint cloning, TTL lifecycle jobs, RBAC, and deployment automatically.

**Prerequisite:** `qovery-builder-env` must be run first to set up blueprint environments, RBAC, and the `builder-platform-config.yaml` config file. This skill reads that file.

## When to Use This Skill

Trigger phrases:
- "Generate a builder portal for my team"
- "Create a self-service UI for our builder environments"
- "Deploy a web portal where non-tech users can create their own environments"
- "Build a Lovable-style portal on top of Qovery"
- `/qovery-builder-portal` (slash command)

## Workflow checklist

```
Builder Portal Progress:
- [ ] Phase 1 — Understand portal requirements (templates, branding, SSO, limits)
- [ ] Phase 2 — Generate the portal application (backend from templates, frontend from spec)
- [ ] Phase 3 — Configure SSO + per-template variables
- [ ] Phase 4 — Deployment plan summary + USER CONFIRMATION
- [ ] Phase 5 — Deploy on Qovery (project, app, env vars, custom domain)
- [ ] Phase 6 — Generate operations runbook
```

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | API token flow |
| Phase 1 | [reference/phase1-requirements.md](reference/phase1-requirements.md) | Authentication, builder-env discovery, branding/SSO/limits |
| Phase 2 | [reference/phase2-generate-app.md](reference/phase2-generate-app.md) | Project structure + when to use templates vs generate |
| Phase 3 | [reference/phase3-configuration.md](reference/phase3-configuration.md) | Environment variables, SSO setup (Google / Okta / Azure / OIDC), templates |
| Phase 4 | [reference/phase4-deployment-plan.md](reference/phase4-deployment-plan.md) | Plan summary template + confirmation gate |
| Phase 5 | [reference/phase5-deploy.md](reference/phase5-deploy.md) | Project, env, application, secrets, custom domain, deploy |
| Phase 6 | [reference/phase6-operations.md](reference/phase6-operations.md) | Adding templates, rotating secrets, troubleshooting |

## Code templates (copy verbatim)

The backend is provided as ready-to-use TypeScript templates — the portal's correctness depends on these files being copied without modification. Adapt only what Phase 2 marks as "agent-generated".

```
templates/
├── Dockerfile                                   # 4-stage Node.js build
├── package.json                                 # all deps pinned
├── .env.example
└── src/
    ├── shared/types.ts                          # shared types (frontend + backend)
    ├── server/
    │   ├── index.ts                             # Express assembly
    │   ├── config.ts                            # YAML config loader
    │   ├── services/
    │   │   ├── qovery.ts                        # typed Qovery API client
    │   │   └── provisioner.ts                   # blueprint clone + TTL job + RBAC
    │   ├── routes/
    │   │   ├── auth.ts                          # SSO login/callback/logout
    │   │   ├── environments.ts                  # CRUD environments
    │   │   ├── templates.ts                     # list templates
    │   │   └── me.ts                            # current user
    │   └── middleware/auth.ts                   # session validator
    └── client/
        ├── lib/api.ts                           # typed fetch wrapper
        └── components/EnvironmentCard.tsx       # env card with status, URLs, actions
```

The agent-generated frontend pages and remaining components are described in [reference/phase2-generate-app.md](reference/phase2-generate-app.md).

## Quick reference

### API endpoints (portal backend)

```
GET    /auth/login                    Redirect to SSO provider
GET    /auth/callback                 SSO callback (creates session)
GET    /auth/logout                   Destroy session

GET    /api/environments              List my environments
POST   /api/environments              Create new (body: { templateId })
POST   /api/environments/:id/start    Start (redeploy) an environment
POST   /api/environments/:id/stop     Stop an environment
DELETE /api/environments/:id          Delete an environment

GET    /api/templates                 List available templates
GET    /api/me                        Current user profile
```

### Environment variables

Required:

```
QOVERY_API_TOKEN          # secret — platform API token
SSO_PROVIDER              # google | okta | azure | oidc
SSO_CLIENT_ID
SSO_CLIENT_SECRET         # secret
PORTAL_URL                # e.g. https://builder.company.com
SESSION_SECRET            # secret — `openssl rand -hex 32`
```

Optional:

```
SSO_ISSUER_URL            # required for OIDC / Okta / Azure
COMPANY_NAME
COMPANY_LOGO_URL
PRIMARY_COLOR             # e.g. #2563EB
MAX_ENVIRONMENTS_PER_BUILDER     # default 3
BUILDER_PLATFORM_CONFIG_PATH     # default ./builder-platform-config.yaml
```

## Reference links

- **Qovery Documentation**: <https://www.qovery.com/docs/getting-started/introduction>
- **Qovery Console**: <https://console.qovery.com>
- **Qovery API Reference**: <https://www.qovery.com/docs/api-reference/introduction>
- **Vite**: <https://vite.dev>
- **TanStack Router**: <https://tanstack.com/router>
- **Tailwind CSS**: <https://tailwindcss.com>
- **Passport.js**: <https://www.passportjs.org>
- **passport-google-oauth20**: <https://www.passportjs.org/packages/passport-google-oauth20/>
- **passport-openidconnect**: <https://www.passportjs.org/packages/passport-openidconnect/>
- **Qovery Builder Env Skill** (prerequisite): <https://github.com/Qovery/qovery-skills>
