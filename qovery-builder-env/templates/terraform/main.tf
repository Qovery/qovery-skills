terraform {
  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = ">= 0.54.0"
    }
  }
}

provider "qovery" {}

# Data source for the organization
data "qovery_organization" "main" {
  id = var.qovery_organization_id
}

# Blueprints project (holds the template — not accessed by builders)
resource "qovery_project" "blueprints" {
  organization_id = var.qovery_organization_id
  name            = var.isolation == "project-per-builder" ? "builder-blueprints" : "builder-workspaces"
  description     = var.isolation == "project-per-builder" ? "Blueprint templates (platform team only)" : "Self-service builder environments for non-tech teams"
}

# Builder blueprint environment (template — cloned for each builder)
resource "qovery_environment" "blueprint" {
  project_id = qovery_project.blueprints.id
  cluster_id = var.qovery_cluster_id
  name       = "builder-blueprint"
  mode       = "DEVELOPMENT"
}

# Workspace IDE application (in the blueprint)
resource "qovery_application" "workspace_blueprint" {
  environment_id = qovery_environment.blueprint.id
  name           = "workspace"

  git_repository = {
    url       = var.ide_git_repository_url
    branch    = "main"
    root_path = "/"
  }

  build_mode      = "DOCKER"
  dockerfile_path = var.ide_dockerfile_path
  cpu             = var.workspace_cpu
  memory          = var.workspace_memory

  min_running_instances = 1
  max_running_instances = 1
  auto_preview          = false
  auto_deploy           = false

  ports = {
    "ide" = {
      internal_port       = 8080
      external_port       = 443
      publicly_accessible = true
      protocol            = "HTTP"
      is_default          = true
    }
  }

  healthchecks = {
    readiness_probe = {
      type = {
        tcp = {
          port = 8080
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      failure_threshold     = 9
    }
  }
}

# Database (in the blueprint)
resource "qovery_database" "postgres_blueprint" {
  count          = var.include_database ? 1 : 0
  environment_id = qovery_environment.blueprint.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "CONTAINER"
  accessibility  = "PRIVATE"
  cpu            = 250
  memory         = 256
  storage        = 10
}

# AI API keys as project-level secrets
# Note: Secrets must be managed via the Qovery API or Console — Terraform
# does not expose secret values for security. Set these manually:
#   ANTHROPIC_API_KEY, OPENAI_API_KEY
# at project scope on the blueprints project (inherited by cloned environments).

# Individual builder environments (one per builder — NEVER shared)
module "builder" {
  source   = "./modules/builder-env"
  for_each = var.builders

  organization_id  = var.qovery_organization_id
  builder_name     = each.key
  builder_email    = each.value.email
  builder_team     = each.value.team
  shared_project_id = qovery_project.blueprints.id
  cluster_id       = var.qovery_cluster_id
  blueprint_env_id = qovery_environment.blueprint.id
  isolation        = var.isolation
  ttl_stop_cron    = var.ttl_stop_cron
  ttl_delete_cron  = var.ttl_delete_cron
}
