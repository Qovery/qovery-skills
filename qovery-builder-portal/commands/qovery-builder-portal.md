---
description: Generate and deploy a self-service web portal for non-tech builders
---

Generate and deploy a self-service web portal for non-tech builders using Qovery.

If arguments are provided, use them as context:
- `$ARGUMENTS` — SSO provider (google, okta, azure), custom domain, or Qovery Console URL

Prerequisite: The builder platform must be set up first using the qovery-builder-env skill.

Follow the qovery-builder-portal skill to:
1. Check for existing builder-env setup (builder-platform-config.yaml)
2. Configure the portal (SSO, branding, templates, limits)
3. Generate the complete portal application (Vite + React + Express + TypeScript)
4. Deploy the portal on Qovery
5. Verify SSO login and environment creation flow
6. Generate the operations guide
