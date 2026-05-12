## Phase 3: Import Existing Resources

Import the existing Qovery resources into Terraform state so that `terraform plan` shows zero changes. This is a one-time operation — it tells Terraform "these resources already exist, adopt them."

### 3.1 Initialize Terraform

```bash
terraform init
```

This downloads the Qovery provider and initializes the working directory. Must succeed before any import or plan.

### 3.2 Import Each Resource

Generate and run an import command for every resource. The syntax is:

```bash
terraform import <resource_type>.<resource_name> <qovery-resource-id>
```

**Generate `import.sh`** — a shell script with all import commands:

```bash
#!/bin/bash
# import.sh — One-time import of existing Qovery resources into Terraform state
# Run this ONCE after generating the .tf files.
set -e

echo "Importing existing Qovery resources into Terraform state..."

terraform import qovery_environment.production {env-id}
terraform import qovery_deployment_stage.infrastructure {stage-id}
terraform import qovery_deployment_stage.backend {stage-id}
terraform import qovery_application.backend {app-id}
terraform import qovery_application.frontend {app-id}
terraform import qovery_container.worker {container-id}
terraform import qovery_database.postgres {db-id}
terraform import qovery_job.db_migration {job-id}
terraform import qovery_job.cleanup {job-id}
# terraform import qovery_helm.redis {helm-id}
# terraform import qovery_terraform_service.s3_bucket {tf-service-id}

echo ""
echo "Import complete. Run 'terraform plan' to verify."
```

Replace the placeholder IDs with the actual resource IDs captured in Phase 1.

For multi-environment setups, include imports for all environments and their resources.

### 3.3 Validate with `terraform plan`

```bash
terraform plan
```

**Expected output:** `No changes. Your infrastructure matches the configuration.`

This means the generated HCL exactly matches the current state of the Qovery resources. The import was successful.

**If changes are shown:**

The HCL doesn't perfectly match reality. Common causes:

| Mismatch | Cause | Fix |
|---|---|---|
| Default values appearing as "add" | API returns defaults that HCL omits | Add the default value explicitly to HCL |
| Port ordering differs | API returns ports in a different order | Reorder ports in HCL to match |
| Healthcheck fields differ | API normalizes field names | Match the exact field names from the plan output |
| Empty blocks showing as "remove" | HCL has `ports = {}` but API returns no ports | Remove the empty block |
| Environment variable ordering | Variables listed in different order | Order doesn't matter for plan — these diffs are cosmetic |

**Process:**
1. Read the `terraform plan` diff carefully
2. Identify which HCL attributes don't match
3. Fix the HCL to match the current state (NOT the desired state — that comes later)
4. Re-run `terraform plan`
5. Repeat until plan shows zero changes

**CRITICAL: Do NOT proceed to Phase 4 or 5 until `terraform plan` shows zero changes.** A non-zero plan means the HCL doesn't accurately represent the current state, and `terraform apply` would modify the environment.

### 3.4 Present Plan to User

Show the `terraform plan` output and confirm:

> "Terraform plan shows **no changes** — the generated manifests match your existing configuration exactly.
>
> Your Qovery resources are now tracked by Terraform state. Any future changes should be made via the `.tf` files and `terraform apply`.
>
> Would you like to validate in a test environment (recommended) or finalize now?"

If the user wants to skip validation (Phase 4):
> "Are you sure? The plan showed zero changes, which is good. However, validating in a test clone catches edge cases that plan doesn't detect (e.g., the resources actually deploying correctly from Terraform). Skip test validation? (y/N)"
