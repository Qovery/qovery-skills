## Phase 4: Validate in a Test Environment (Recommended)

This phase creates a clone of the original environment in a separate test project, applies the generated Terraform there, and verifies everything works. The original environment is NEVER touched.

**This phase is strongly recommended but can be skipped** if the user explicitly confirms. The `terraform plan` in Phase 3 validates the HCL matches the existing state, but Phase 4 validates that the Terraform manifests can actually CREATE working resources from scratch.

### 4.1 Create a Test Project

Create a temporary project for validation — separate from the original to avoid any interference:

```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Bearer $(qovery auth token --print)" \
  -H "Content-Type: application/json" \
  -d '{"name": "terraform-validation-test", "description": "Temporary project for Terraform validation — delete after test"}'
```

Store the test project ID.

### 4.2 Generate Test `.tfvars`

Create a `terraform-test.tfvars` that overrides the project ID to point to the test project. The original project/environment are NOT referenced:

```hcl
# terraform-test.tfvars — points to the TEST project, not the original
qovery_access_token    = "..."  # Or use TF_VAR_qovery_access_token
qovery_organization_id = "{org-id}"
qovery_project_id      = "{test-project-id}"    # TEST project, NOT original
qovery_cluster_id      = "{cluster-id}"
```

IMPORTANT: The test `.tfvars` uses the TEST project ID. The original project/environment are untouched.

### 4.3 Apply to Test Environment

Create a fresh Terraform workspace for the test (to keep state separate):

```bash
terraform workspace new test
terraform plan -var-file="terraform-test.tfvars"     # Review first
terraform apply -var-file="terraform-test.tfvars"     # Apply to test project
```

This creates all resources (environment, applications, databases, jobs) in the test project from scratch — proving the Terraform manifests can reproduce the setup.

### 4.4 Verify

Check that the test environment deploys successfully:

```bash
# Get the test environment ID from Terraform output
terraform output -var-file="terraform-test.tfvars"

# Check statuses via API
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/environment/{testEnvId}/statuses" | jq '{
    environment: .environment.state,
    services: [(.applications // [])[] | {name: .name, state}]
  }'
```

Wait for all services to be `DEPLOYED`. If any service fails:
- Fetch logs: `qovery log --service "{name}" --since 10m`
- Diagnose and fix the HCL
- Re-apply: `terraform apply -var-file="terraform-test.tfvars"`

### 4.5 Clean Up

Delete the test environment and project — they served their purpose:

```bash
# Destroy test resources via Terraform
terraform destroy -var-file="terraform-test.tfvars" -auto-approve

# Switch back to default workspace
terraform workspace select default
terraform workspace delete test

# Delete the test project via API
curl -s -X DELETE "https://api.qovery.com/project/{testProjectId}" \
  -H "Authorization: Bearer $(qovery auth token --print)"

# Remove test tfvars
rm terraform-test.tfvars
```

### 4.6 Confirm

> "Terraform manifests validated successfully against a test clone.
>
> All resources deployed correctly in the test project. The test project has been cleaned up.
>
> Your Terraform manifests are production-ready. Proceeding to finalize."
