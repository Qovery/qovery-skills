## Phase 5: Finalize

### 5.1 Save Files

Ask where to save the generated Terraform files:

> "Where should I save the Terraform files?"
> 1. Current directory
> 2. New `terraform/` subdirectory
> 3. Existing repo path

Write all files:
- `provider.tf` — Qovery provider configuration
- `variables.tf` — input variables (including sensitive ones for secrets)
- `{env-name}.tf` (or `environments/*.tf` for multi-env) — all resources
- `outputs.tf` — resource IDs and external hosts
- `terraform.tfvars` — actual values (secret placeholders)
- `import.sh` — one-time import script with all `terraform import` commands
- `.gitignore` — excludes `.terraform/`, `*.tfstate`, `terraform-test.tfvars`

### 5.2 Git Commit (Optional)

If the user wants to version-control the manifests:

```bash
git add provider.tf variables.tf *.tf outputs.tf terraform.tfvars import.sh .gitignore
git commit -m "feat: terraformize {env-name} environment from existing Qovery setup

Generated from existing Qovery Console configuration using qovery-terraform skill.
Resources imported into Terraform state — terraform plan shows zero changes.

Resources: {N} applications, {N} databases, {N} jobs, {N} containers
Provider: qovery/qovery ~> 0.54.0"
```

IMPORTANT — remind the user:
- **DO NOT commit `.tfstate` files** — they contain resource IDs and may contain sensitive data
- **DO NOT commit actual secret values** in `.tfvars` — use `TF_VAR_` env vars in CI/CD
- The `.gitignore` already excludes these, but verify

### 5.3 Provide Import Script

If Phase 3 was completed (imports already done), remind the user the state is already populated. If Phase 3 was not yet run (the user generated files but hasn't imported yet), provide `import.sh` and instruct:

> "Run the import script ONCE to adopt your existing resources into Terraform state:
> ```bash
> export TF_VAR_qovery_access_token=your-token
> terraform init
> bash import.sh
> terraform plan    # Must show 'No changes'
> ```
> After importing, all future changes should be made via `.tf` files + `terraform apply`."

### 5.4 Next Steps

Present to the user:

> **Your Qovery infrastructure is now managed by Terraform.**
>
> **Day-to-day workflow:**
> ```bash
> # 1. Edit the .tf files
> # 2. Preview changes
> terraform plan
> # 3. Apply changes
> terraform apply
> ```
>
> **Adding a new service:**
> Add a new `qovery_application`, `qovery_database`, etc. resource block to your `.tf` file, then run `terraform apply`.
>
> **Removing a service:**
> Remove the resource block from `.tf`, then run `terraform apply`. Terraform will delete the service from Qovery.
>
> **IMPORTANT RULES:**
> - Make changes through `.tf` files + `terraform apply` — NOT through the Qovery Console
> - If you make changes in the Console, run `terraform plan` to detect drift and reconcile
> - The `.tfstate` file is your source of truth — do NOT delete it
> - Consider remote state (S3, GCS, Terraform Cloud) for team collaboration
> - Secrets: always use `TF_VAR_` env vars or a `.tfvars` file (gitignored)

### 5.5 Safety Warnings

For each managed database found, present a prominent warning:

> **Database Warnings:**
>
> | Database | Type | Mode | Warning |
> |---|---|---|---|
> | postgres-prod | POSTGRESQL | MANAGED | Any change forcing recreation DESTROYS ALL DATA. Ensure backups exist. |
> | redis-prod | REDIS | MANAGED | Same risk. |
>
> For managed databases, always run `terraform plan` before `terraform apply` and carefully review any changes to database resources. If the plan shows "must be replaced", **DO NOT apply** without verified backups.

For stateful services (any service with persistent volumes):

> **Stateful services** — if Terraform needs to recreate a service that has persistent storage, the data on that storage will be lost. Always check `terraform plan` output for "must be replaced" warnings.
