## PHASE 6: Portal Operations Guide

Generate an operations guide for the platform team:

> # Builder Portal — Operations Guide
>
> ## Portal URL
> {portal-url}
>
> ## Adding a New Template
> 1. Create a new blueprint environment using the `qovery-builder-env` skill
> 2. Add it to the `templates` section in `builder-platform-config.yaml`:
>    ```yaml
>    - name: "New Template Name"
>      description: "What builders can build with this template"
>      blueprint_env_id: "new-blueprint-env-id"
>      icon: "icon-name"
>    ```
> 3. Commit and push to git
> 4. The portal will pick up the new template on next restart (or redeploy)
>
> ## Changing Max Environments Per Builder
> Update the `MAX_ENVIRONMENTS_PER_BUILDER` environment variable on the portal application in the Qovery Console.
>
> ## Updating Branding
> Update `COMPANY_NAME`, `COMPANY_LOGO_URL`, or `PRIMARY_COLOR` environment variables in the Qovery Console. Redeploy the portal.
>
> ## Rotating SSO Credentials
> 1. Generate new credentials in your SSO provider dashboard
> 2. Update `SSO_CLIENT_ID` and `SSO_CLIENT_SECRET` in the Qovery Console
> 3. Redeploy the portal
>
> ## Rotating the Qovery API Token
> 1. Generate a new API token in Qovery Console > Organization Settings > API Tokens
> 2. Update `QOVERY_API_TOKEN` secret in the Qovery Console
> 3. Redeploy the portal
>
> ## Monitoring
> - Portal logs: `qovery log --service "portal" --follow`
> - Portal errors: `qovery log --service "portal" --filter "Error"`
> - Builder environment statuses: Qovery Console > builder-workspaces project
>
> ## Troubleshooting
> - **SSO login fails**: Check `SSO_CLIENT_ID`, `SSO_CLIENT_SECRET`, `SSO_ISSUER_URL`. Verify the callback URL matches `PORTAL_URL/auth/callback`.
> - **"Not authenticated" errors**: Check `SESSION_SECRET` is set. Check browser cookies are not blocked.
> - **Environment creation fails**: Check `QOVERY_API_TOKEN` is valid. Check the blueprint environment exists and is accessible.
> - **"Maximum environments" error**: Increase `MAX_ENVIRONMENTS_PER_BUILDER` or ask the builder to delete unused environments.
> - **Portal not loading**: Check the portal application logs in Qovery Console.

