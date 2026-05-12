## Phase 1: Context Gathering

### 1.0 Check Prerequisites

Verify both Terraform and the Qovery CLI are installed:

```bash
terraform version    # Must be >= 1.0
qovery version       # Qovery CLI for auth + monitoring
```

If Terraform is not installed:
> "Terraform is required. Install it:
> - macOS: `brew install terraform`
> - Linux: download from https://developer.hashicorp.com/terraform/downloads
> - Or use OpenTofu: `brew install opentofu`"

If Qovery CLI is not installed:
> "Install the Qovery CLI: `curl -s https://get.qovery.com | bash`"

### 1.1 Authenticate

Use the same authentication flow as all Qovery skills — see [auth.md](auth.md).

The Terraform provider needs an API token. After authenticating, ensure `$QOVERY_API_TOKEN` is available (it will be passed as `TF_VAR_qovery_access_token`).

### 1.2 Identify the Target

**From Console URL** — if the user provides a Qovery Console URL, extract IDs using [console-url-detection.md](console-url-detection.md):
```
https://console.qovery.com/organization/{orgId}/project/{projectId}/environment/{envId}
```

**From names** — ask the user:
1. Which organization? (list with API, pick if multiple)
2. Which project? (list projects in org)
3. Which environment(s)?

**Multi-environment support** — ask:
> "Do you want to terraformize just this environment, or the entire project (all environments)?
> You can also select specific environments."

Options:
- **Single environment** — generates one `{env-name}.tf` file
- **All environments in a project** — generates one `.tf` file per environment in `environments/` directory
- **Selected environments** — user picks which ones

### 1.3 Read Existing Configuration from API

For each target environment, read the full configuration:

```bash
# Environment details
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}" | jq '{id, name, mode, cluster_id}'

# All applications
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/application" | jq '.results'

# Full config for each application (ports, healthchecks, git, CPU, memory)
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{appId}" | jq '.'

# All containers
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/container" | jq '.results'

# All databases
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/database" | jq '.results'

# All jobs
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/job" | jq '.results'

# All Helm charts
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/helm" | jq '.results'

# Environment-level variables
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/environmentVariable" | jq '.results'

# Per-service variables (for each application, container, job, etc.)
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/application/{appId}/environmentVariable" | jq '.results'

# Deployment stages
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{envId}/deploymentStage" | jq '.results'
```

Store all responses — they are used in Phase 2 to generate HCL.

### 1.4 Present Summary

Show the user what was found:

> "I found the following resources in **{env-name}** ({mode}):
> - {N} applications: {names}
> - {N} containers: {names}
> - {N} databases: {names} {warn if any MANAGED}
> - {N} jobs: {names}
> - {N} Helm charts: {names}
> - {N} deployment stages
> - {N} environment variables ({M} secrets)
>
> Ready to generate Terraform manifests?"

If any managed databases are found, warn immediately:
> "⚠ Found {N} managed database(s): {names}. These will be included in the Terraform manifests, but **any change that forces recreation will DESTROY ALL DATA**. Ensure backups exist."
