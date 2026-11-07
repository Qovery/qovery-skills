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
# Is the CLI already signed in? (prints nothing secret)
qovery auth status --json | jq -e '.authenticated'

# If not, the user signs in. From an agent or a remote shell use --headless: it prints a URL
# the user opens in their browser. In Claude Code: ! qovery auth --headless
qovery auth --headless

# CI only: the user exports a token they created themselves (never the agent)
# export QOVERY_CLI_ACCESS_TOKEN=...
```

### Target organization, project and environment

`qovery context set` is an interactive picker (no flags), so an agent cannot drive it. Either ask
the user to run `! qovery context set`, or skip it and pass names explicitly, which every
command accepts:

```bash
qovery organization list --json
qovery project list --organization "My Org" --json
qovery environment list --organization "My Org" --project "My Project" --json
```

For REST calls, put explicit IDs in the path (`qovery api organization/<org-id>/project`).

### Calling the Qovery API

Many operations in this skill use the Qovery REST API. In order of preference:

**1. `qovery api` (preferred, no token at all)**

```bash
qovery api organization                                               # GET
qovery api organization/<org-id>/project --field name="web"           # POST from fields
qovery api environment/<env-id>/application --input - < app.json      # POST from a file
qovery api application/<app-id> --method PUT --input - < app.json
qovery api application/<app-id>/deploy --method POST
```

It reuses the CLI session (auto-refreshed) and sets the `Authorization` header itself. Add the
skill `User-Agent` with `-H` as described in auth.md.

**2. `curl` with the CLI session inline (when a script needs curl)**

```bash
curl -s -H "Authorization: $(qovery auth token --print --authorization-header)" https://api.qovery.com/organization
```

`--authorization-header` prints the whole header value with the correct scheme. Keep it inline:

```bash
# WRONG, exposes the value:
export QOVERY_BEARER_TOKEN=$(qovery auth token --print)
echo $(qovery auth token --print)
qovery auth token --print
```

**3. A token the user already exported**

If the user set `QOVERY_API_TOKEN` themselves, use `Authorization: Token $QOVERY_API_TOKEN`.

**Do not mint a long-lived API token.** There is no `qovery token create`; `qovery token` is an
interactive prompt for humans. A long-lived token is only needed for the Terraform path, and the
user creates it (Console > Organization Settings > API Tokens, ideally a scoped API Policy Token)
and exports it as `QOVERY_API_TOKEN` in their own shell.

**Summary of auth headers used in this skill:**

| Source | How |
|---|---|
| CLI session (preferred) | `qovery api <path>`, or `Authorization: $(qovery auth token --print --authorization-header)` |
| Token the user created (Terraform, CI) | `Authorization: Token $QOVERY_API_TOKEN` |

The `curl` examples in later phases show `Authorization: Token $QOVERY_API_TOKEN`; with a CLI
session, run them through `qovery api` instead, or swap the header for the inline form above.

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
