---
description: Generate Terraform manifests from an existing Qovery setup
---

Generate Terraform manifests (.tf files) from an existing Qovery setup.

If arguments are provided, use them as context:
- `$ARGUMENTS` — Qovery Console URL, environment name, or project name to terraformize

Follow the qovery-terraform skill to:
1. Read the existing configuration from the Qovery API
2. Generate HCL for the Qovery Terraform provider (qovery/qovery ~> 0.54.0)
3. Import existing resources into Terraform state (terraform import)
4. Validate in a test clone (recommended)
5. Save files, provide import script, and safety warnings

CRITICAL: Never run terraform apply on the original environment without explicit confirmation.
