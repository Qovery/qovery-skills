---
name: qovery-terraform
description: Generate Terraform manifests from an existing Qovery setup. Reads the current configuration from the Qovery API, generates HCL for the Qovery Terraform provider, imports existing resources into Terraform state, and validates in a test clone. Supports single or multiple environments. Use when the user wants to convert a Console-managed Qovery setup to infrastructure-as-code.
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: terraform-export
---

# Qovery Terraform Skill

Generates Terraform manifests from an existing Qovery setup — reads the current configuration from the Qovery API, produces HCL for the Qovery Terraform provider (`qovery/qovery ~> 0.54.0`), imports existing resources into Terraform state, and optionally validates in a test clone before touching anything.

Supports single environments or multiple environments merged into one configuration.

## Usage Tracking

**EXECUTE THIS BASH COMMAND IMMEDIATELY — before any other action. Do not skip.**

```bash
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  QOVERY_AUTH_HEADER="Token $QOVERY_API_TOKEN"
elif command -v qovery >/dev/null 2>&1 && qovery auth token --print >/dev/null 2>&1; then
  QOVERY_AUTH_HEADER="Bearer $(qovery auth token --print)"
else
  QOVERY_AUTH_HEADER=""
fi
if [ -n "$QOVERY_AUTH_HEADER" ]; then
  QOVERY_ORG_ID=$(curl -s -H "Authorization: $QOVERY_AUTH_HEADER" \
    "https://api.qovery.com/organization" | jq -r '.results[0].id' 2>/dev/null)
  SKILL_NAME="qovery-terraform"
  [ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
    -H "Authorization: $QOVERY_AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -H "User-Agent: QoverySkill/qovery-terraform (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
    -d "{\"skill_name\":\"${SKILL_NAME}\"}" > /dev/null 2>&1 || true
fi
```

> **API rule:** The `User-Agent` header above is required on **every** `curl` call to `api.qovery.com` — not just this tracking call. Never omit it.

## CRITICAL SAFETY RULES

> **NEVER run `terraform apply` on the original environment without explicit user confirmation.**
>
> **ALWAYS validate with `terraform plan` (must show zero changes) before proceeding.**
>
> **ALWAYS offer to validate in a test clone (Phase 4) before touching original resources.**
>
> **NEVER write secret values to `.tf` files** — use `TF_VAR_` env vars or a `.tfvars` file (gitignored).
>
> **WARN about managed databases** — recreation destroys ALL data. Flag every managed DB with a warning.
>
> **Show `terraform plan` output to the user before ANY `terraform apply`.**

## When to Use This Skill

Trigger phrases:
- "Terraformize my Qovery setup"
- "Convert my environment to Terraform"
- "Export my Qovery config as infrastructure-as-code"
- "I want to manage my Qovery resources with Terraform"
- "Generate Terraform from my existing Qovery project"
- "Turn my Qovery Console config into .tf files"
- `/qovery-terraform` (slash command)

## Workflow checklist

```
Terraformize Existing Setup:
- [ ] Phase 1 — Context: check CLI + Terraform, auth, identify target (URL or names), read config from API
- [ ] Phase 2 — Generate: produce .tf files (provider, variables, resources, outputs, tfvars)
- [ ] Phase 3 — Import: terraform init + import for each resource, plan must show zero changes
- [ ] Phase 4 — Validate: clone to test project, apply there, verify, cleanup (recommended, skippable)
- [ ] Phase 5 — Finalize: save files, git commit, provide import script, safety warnings
```

## Supported resource types

| Qovery Resource | Terraform Resource | Notes |
|---|---|---|
| Environment | `qovery_environment` | Mode, cluster binding |
| Application | `qovery_application` | Git source, Docker build, ports, health checks |
| Container | `qovery_container` | Registry image, ports, health checks |
| Database (container) | `qovery_database` | mode = "CONTAINER" — safe to recreate |
| Database (managed) | `qovery_database` | mode = "MANAGED" — **WARNING: recreation destroys data** |
| Job (lifecycle) | `qovery_job` | on_start/on_stop/on_delete triggers |
| Job (cron) | `qovery_job` | Cron schedule |
| Helm chart | `qovery_helm` | Repository + chart, values override |
| Terraform service | `qovery_terraform_service` | Engine (Terraform/OpenTofu), variables |
| Deployment stage | `qovery_deployment_stage` | Ordering (is_before/is_after) |
| Environment variables | Inline on each resource | Secrets as variable references, never plaintext |

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Auth | [reference/auth.md](reference/auth.md) | Token handling + security rules |
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from Console URLs |
| Phase 1 | [reference/phase1-context.md](reference/phase1-context.md) | Check prerequisites, auth, identify target, read full config from API |
| Phase 2 | [reference/phase2-generate.md](reference/phase2-generate.md) | HCL generation rules + one example per resource type |
| Phase 3 | [reference/phase3-import.md](reference/phase3-import.md) | terraform init, import commands, plan validation (zero diff required) |
| Phase 4 | [reference/phase4-validate.md](reference/phase4-validate.md) | Clone to test project, apply, verify, cleanup (recommended, skippable) |
| Phase 5 | [reference/phase5-finalize.md](reference/phase5-finalize.md) | Save files, git commit, import script, next steps, safety warnings |

## Quick reference

```bash
# Prerequisites
terraform version    # >= 1.0 required
qovery version       # Qovery CLI for auth + monitoring

# Terraformize from a Console URL
/qovery-terraform https://console.qovery.com/organization/xxx/project/yyy/environment/zzz

# Or by name
/qovery-terraform org="My Org" project="backend" environment="production"

# After generation: init, import, plan
terraform init
bash import.sh                    # runs all terraform import commands
terraform plan                    # must show "No changes"

# Validate in test clone (Phase 4)
terraform apply -var-file="terraform-test.tfvars" -auto-approve

# Production use (after validation)
terraform plan                    # review changes
terraform apply                   # apply (with confirmation)
```

## Generated file structure

```
terraform/
├── provider.tf           # qovery/qovery ~> 0.54.0
├── variables.tf          # token, org_id, project_id, cluster_id, secrets
├── {env-name}.tf         # all resources for one environment
├── outputs.tf            # resource IDs, external hosts
├── terraform.tfvars      # actual values (secrets as placeholders)
├── import.sh             # one-time import script
└── .gitignore            # .terraform/, *.tfstate, terraform-test.tfvars
```

For multi-environment:
```
terraform/
├── provider.tf
├── variables.tf
├── environments/
│   ├── production.tf
│   ├── staging.tf
│   └── development.tf
├── outputs.tf
├── terraform.tfvars
├── import.sh
└── .gitignore
```

## Reference links

- **Qovery Terraform Provider**: <https://registry.terraform.io/providers/Qovery/qovery/latest/docs>
- **Terraform Examples**: <https://github.com/Qovery/terraform-examples>
- **Qovery API**: <https://www.qovery.com/docs/api-reference/introduction>
- **Qovery CLI**: <https://www.qovery.com/docs/cli/commands/overview>
- **Qovery Console**: <https://console.qovery.com>
