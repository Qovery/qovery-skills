## PHASE 6: Verification & Next Steps

### 6.1 Verify Everything Is Set Up

```bash
# Verify cluster is ready
qovery cluster list
# Should show your cluster with status DEPLOYED

# Verify environments
qovery environment list
# Should show development, staging, production

# Verify in Console
# https://console.qovery.com — check dashboard shows all resources
```

> "Your Qovery setup is complete! Here's a summary:
>   - Cluster: {name} ({provider}, {region}) — READY
>   - Project: {name}
>   - Environments: development, staging, production
>   - Deployment rules: dev (8am-8pm), staging (8am-10pm), production (24/7)
>   - Team: {X} members invited
>   - Git provider: connected
>
> View your dashboard: https://console.qovery.com"

### 6.2 Next Steps (Persona-Adapted)

**For developers / founders / non-technical:**
> "You're all set! To deploy your first application, just tell me:
>   'Deploy my application with Qovery'
> I'll analyze your code, create a Dockerfile if needed, and deploy it."

**For DevOps / platform engineers:**
> "Setup complete. Here are your next steps:
> 1. **Deploy a test application** to verify everything works end-to-end
> 2. **Review RBAC** — create custom roles at Organization Settings > Custom Roles for fine-grained access control (e.g., devs deploy to staging only)
> 3. **Export as Terraform** — once your first apps are deployed, export the config as Terraform for version-controlled IaC
> 4. **Set up monitoring** — deploy Datadog or Grafana via Helm, or enable Qovery Observe
> 5. **Configure CI/CD integration** — enable auto-deploy on git push for continuous deployment"

**For enterprise:**
> "Infrastructure is ready. Before deploying applications, consider these enterprise steps:
> 1. **Custom RBAC roles** — Organization Settings > Custom Roles (restrict production access to senior engineers)
> 2. **Private networking** — review VPC configuration, set up VPC peering if needed
> 3. **Audit logging** — enabled by default in Qovery Console
> 4. **SSO/SAML** — contact Qovery support for enterprise SSO integration
> 5. **Compliance review** — share your setup with Qovery support for a compliance-specific review
>
> Contact Qovery Enterprise support: support@qovery.com"

### 6.3 Reference the Other Qovery Skills

> "You now have access to the full suite of Qovery AI skills:
>
> **Deploy an application:**
>   'Deploy my application with Qovery' → qovery-deploy skill
>
> **Fix a problem:**
>   'My deployment is failing, can you help?' → qovery-troubleshoot skill
>
> **Optimize costs:**
>   'Optimize my Qovery costs' → qovery-optimize skill
>
> **Speed up deployments:**
>   'My deployments are slow' → qovery-speedup skill
>
> Each skill is loaded automatically when you ask the relevant question."

---

