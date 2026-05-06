## PHASE 2: Set Up the Platform Foundation

### 2.1 Resolve Organization & Cluster

**Shortcut:** If the user provided a Qovery Console URL, extract the organization ID from it.

After authenticating, list all organizations:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  https://api.qovery.com/organization | jq '.results[] | {id, name}'
```

- **If 1 organization**: Confirm and move on.
- **If multiple**: Present the list and ask which one to use.

Then list all clusters:

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'
```

**Recommendation:** Use a **dedicated cluster** for builder environments, separate from production. This provides:
- Cost isolation (builder costs are clearly separated)
- Security isolation (builders can't accidentally affect production)
- Different instance types (smaller, cheaper nodes for dev workloads)
- Independent scaling

If no suitable cluster exists, reference the qovery-onboard skill: "Say 'Set up Qovery for my organization' to create a new cluster."

### 2.2 Create the Builder Project(s)

Based on the isolation level chosen in Phase 1.3, create the project structure:

**Option A: Shared Project** (all builders in one project)

Create a single project for the blueprint template and all builder environments:

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-workspaces", "description": "Self-service builder environments for non-tech teams"}'
```

This project will contain:
- The builder environment blueprint (template)
- All individual builder environments (one per builder — NOT shared)

Simpler to manage, but builders can see each other's environment names in the Qovery Console (though RBAC prevents them from modifying each other's environments).

**Option B: Project-per-Builder** (full isolation — recommended for security)

Create a **blueprints project** for the template, then a **separate project per builder** during provisioning (Phase 4):

```bash
# Create the blueprints project (holds only the template — builders don't see this)
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-blueprints", "description": "Blueprint templates for builder environments (platform team only)"}'
```

Individual builder projects will be created during provisioning (Phase 4.2) — one project per builder named `builder-{name}`. Each builder's RBAC role is scoped to their own project only, so they cannot see anyone else's environments or data.

This is the recommended approach when:
- Builders work with sensitive data (CRM, financial, customer PII)
- Compliance requires environment isolation (SOC2, ISO 27001, HIPAA)
- The organization has many builders (20+)
- Different teams should not see each other's work

### 2.3 Set Up RBAC — Create a "Builder" Custom Role

Create a custom role with restricted permissions so builders can deploy their own environments but cannot touch production or other projects.

**Step 1: Create the custom role**
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/customRole" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Builder", "description": "Non-tech builders: can deploy dev environments, no production access"}'
```

**Step 2: Configure cluster permissions**

The cluster permission is the same regardless of isolation mode:
```bash
curl -s -X PUT "https://api.qovery.com/organization/{orgId}/customRole/{roleId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Builder",
    "description": "Non-tech builders: can deploy dev environments, no production access",
    "cluster_permissions": [
      {"cluster_id": "{builderClusterId}", "permission": "ENV_CREATOR"},
      {"cluster_id": "{prodClusterId}", "permission": "VIEWER"}
    ],
    "project_permissions": []
  }'
```

**Step 3: Configure project permissions (depends on isolation mode)**

**If shared project** (Option A):
Add the shared project to the role so all builders can access it:
```bash
# Add project permissions for the shared builder-workspaces project
# All builders share this role and can see each other's environments
"project_permissions": [
  {
    "project_id": "{builderWorkspacesProjectId}",
    "is_admin": false,
    "permissions": [
      {"environment_type": "DEVELOPMENT", "permission": "DEPLOYER"},
      {"environment_type": "STAGING", "permission": "VIEWER"},
      {"environment_type": "PRODUCTION", "permission": "NO_ACCESS"},
      {"environment_type": "PREVIEW", "permission": "DEPLOYER"}
    ]
  }
]
```

**If project-per-builder** (Option B):
Do NOT add project permissions at role creation time. Instead, each builder's project permissions are added **dynamically** during provisioning (Phase 4.2) when their project is created. This means:
- The base "Builder" role has cluster permissions only (no project permissions yet)
- When a builder is provisioned, the provisioning script updates the role OR creates a unique per-builder role that includes their specific project
- Each builder can ONLY see their own project

IMPORTANT: With project-per-builder isolation, you have two approaches:
1. **One role, dynamically updated**: Add each new builder's project to the shared "Builder" role. Simpler, but all builders share the same role definition. They can't actually access each other's environments because DEPLOYER only lets them deploy within their own project's environments.
2. **Per-builder roles**: Create a unique role per builder (e.g., "Builder-Alice") scoped to only their project. Maximum isolation — each builder has their own role with access to only their project. The provisioning script handles role creation automatically.

Recommend approach 2 (per-builder roles) for maximum security.

This ensures builders can:
- Deploy and manage their own DEVELOPMENT environments
- See logs, access URLs, and manage environment variables in THEIR environment only
- Access their environment via web IDE URL
- NOT touch production environments
- NOT see other builders' projects or environments (project-per-builder mode)
- NOT modify cluster settings

### 2.4 Configure SSO (if applicable)

If the company uses SSO (Google Workspace, Okta, Azure AD, etc.):

1. Guide the platform engineer to Qovery Console > Organization Settings > Authentication
2. Configure SAML or SSO integration
3. Ensure builders authenticate with company credentials
4. Map SSO groups to the "Builder" custom role if supported

> "SSO ensures builders log in with their company credentials. This means:
> - No separate passwords to manage
> - Automatic deprovisioning when someone leaves the company
> - Audit trail tied to real identities"

---

