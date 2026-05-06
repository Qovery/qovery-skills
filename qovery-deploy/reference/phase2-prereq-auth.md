## PHASE 2: Prerequisites & Authentication

### Install Qovery CLI

The CLI is needed regardless of the deployment method (even with Terraform, the CLI is useful for monitoring, logs, and shell access).

```bash
# macOS (Homebrew)
brew tap Qovery/qovery-cli
brew install qovery-cli

# Linux
curl -s https://get.qovery.com | bash

# Windows (Scoop)
scoop bucket add qovery https://github.com/Qovery/scoop-qovery-cli
scoop install qovery-cli

# Docker
docker run ghcr.io/qovery/qovery-cli:latest help

# Verify installation
qovery version
```

### Authenticate

```bash
# Interactive browser-based login
qovery auth

# OR for headless environments, set an existing API token
export QOVERY_CLI_ACCESS_TOKEN="your-api-token"
```

### Set Context

The CLI uses a context-based approach. Set your default organization, project, and environment:

```bash
# Interactive context selection
qovery context set

# Verify
qovery project list
qovery environment list
```

### Obtain an API Token for API Calls

Many operations in this skill use the Qovery REST API directly (via `curl`). You need a token for the `Authorization` header. Try these methods in order — use the first one that works:

**Method 1: Generate a token via the CLI (preferred)**

If the user is already authenticated via `qovery auth`, the CLI can generate an API token without leaving the terminal:

```bash
# Generate a named token (easy to identify and clean up later)
qovery token --name "deploy-skill-$(date +%Y%m%d)"

# The command outputs the token — save it
export QOVERY_API_TOKEN="qov_..."
```

Use this token in API calls with the header: `Authorization: Token $QOVERY_API_TOKEN`

This token is permanent (no expiration) and can be deleted later from the Qovery Console (Organization Settings > API Tokens) or via the API when no longer needed. The agent should offer to clean it up after deployment is complete (see Phase 9).

**Method 2: Use the CLI's JWT token (fallback)**

If `qovery token` fails (e.g., insufficient permissions), the CLI stores a JWT token locally after authentication. This can be used directly:

```bash
# Extract JWT from CLI context
export QOVERY_JWT_TOKEN=$(cat ~/.qovery/context.json | jq -r '.access_token')
```

Use this token with a **Bearer** header instead of Token: `Authorization: Bearer $QOVERY_JWT_TOKEN`

IMPORTANT: JWT tokens expire (check the `access_token_expiration` field in `context.json`). If the token is expired, re-authenticate with `qovery auth` to refresh it. API tokens from Method 1 do not expire.

**Method 3: User provides an existing API token (manual)**

If the user already has an API token from the Qovery Console:

```bash
export QOVERY_API_TOKEN="your-existing-token"
```

**Method 4: Generate from the Qovery Console (last resort)**

Direct the user to: Qovery Console > Organization Settings > API Tokens > Generate.

**Summary of auth headers used in this skill:**

| Token Source | Header Format |
|---|---|
| API Token (from `qovery token` or Console) | `Authorization: Token $QOVERY_API_TOKEN` |
| JWT Token (from `~/.qovery/context.json`) | `Authorization: Bearer $QOVERY_JWT_TOKEN` |

All `curl` examples in this skill use `Authorization: Token $QOVERY_API_TOKEN`. If you are using a JWT token instead, replace `Token` with `Bearer` in the header.

### Install Terraform (if using Terraform path)

```bash
# macOS
brew install terraform

# Linux
curl -fsSL https://releases.hashicorp.com/terraform/1.13.0/terraform_1.13.0_linux_amd64.zip -o terraform.zip
unzip terraform.zip && sudo mv terraform /usr/local/bin/

# Verify
terraform version
```

---
