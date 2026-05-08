variable "organization_id" { type = string }
variable "builder_name" { type = string }
variable "builder_email" { type = string }
variable "builder_team" { type = string }
variable "shared_project_id" { type = string }
variable "cluster_id" { type = string }
variable "blueprint_env_id" { type = string }
variable "isolation" { type = string }
variable "ttl_stop_cron" { type = string }
variable "ttl_delete_cron" { type = string }

# Step 1: Create per-builder project (if project-per-builder isolation)
resource "qovery_project" "builder" {
  count           = var.isolation == "project-per-builder" ? 1 : 0
  organization_id = var.organization_id
  name            = "builder-${var.builder_name}"
  description     = "Builder workspace for ${var.builder_name} (${var.builder_team})"
}

locals {
  project_id = var.isolation == "project-per-builder" ? qovery_project.builder[0].id : var.shared_project_id
}

# Step 2: Clone the blueprint environment into the builder's project
# Note: Environment cloning is not natively supported in the Qovery Terraform provider.
# Use a null_resource with the Qovery API to clone the blueprint.
resource "null_resource" "clone_blueprint" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -sf -X POST "https://api.qovery.com/environment/${var.blueprint_env_id}/clone" \
        -H "Authorization: Token $QOVERY_API_TOKEN" \
        -H "User-Agent: QoverySkill/qovery-builder-env (https://github.com/Qovery/qovery-skills)" \
        -H "Content-Type: application/json" \
        -d '{"name": "workspace", "cluster_id": "${var.cluster_id}", "mode": "DEVELOPMENT", "project_id": "${local.project_id}"}'
    EOT
  }

  triggers = {
    builder_name = var.builder_name
    project_id   = local.project_id
  }

  depends_on = [qovery_project.builder]
}

# Step 3: Invite the builder
resource "null_resource" "invite_builder" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -sf -X POST "https://api.qovery.com/organization/${var.organization_id}/inviteMember" \
        -H "Authorization: Token $QOVERY_API_TOKEN" \
        -H "User-Agent: QoverySkill/qovery-builder-env (https://github.com/Qovery/qovery-skills)" \
        -H "Content-Type: application/json" \
        -d '{"email": "${var.builder_email}", "role_id": "TODO_ROLE_ID"}' || true
    EOT
  }

  triggers = {
    builder_email = var.builder_email
  }

  depends_on = [null_resource.clone_blueprint]
}

# Note: The TTL lifecycle job and per-builder RBAC role creation are handled
# by the provisioning script (provision-builder.sh) since they require
# dynamic API calls that are complex to express in Terraform.
# For full automation, use the provisioning script alongside Terraform.

output "project_id" {
  value = local.project_id
}

output "builder_name" {
  value = "builder-${var.builder_name}"
}
