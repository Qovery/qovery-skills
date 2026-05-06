## PHASE 7: Complete Example — Full-Stack Application

Here is a complete, production-ready Terraform configuration for a typical full-stack app (Next.js frontend + API backend + PostgreSQL database). Copy and adapt this as a starting point:

```hcl
# ============================================================
# qovery.tf — Complete Full-Stack Deployment on Qovery
# ============================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = "~> 0.54.0"
    }
  }
}

provider "qovery" {
  token = var.qovery_access_token
}

# --- Variables ---

variable "qovery_access_token" {
  type      = string
  sensitive = true
}

variable "qovery_project_id" { type = string }
variable "qovery_cluster_id" { type = string }
variable "git_repository_url" { type = string }

variable "git_branch" {
  type    = string
  default = "main"
}

variable "environment_name" {
  type    = string
  default = "production"
}

variable "environment_mode" {
  type    = string
  default = "PRODUCTION"
  # Valid values: PRODUCTION, STAGING, DEVELOPMENT
}

variable "use_managed_database" {
  description = "true = cloud-managed DB (production), false = container DB (dev/test)"
  type        = bool
  default     = false
}

variable "jwt_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# --- Environment ---
# Shared variables are set here — inherited by ALL services, avoiding duplication.

resource "qovery_environment" "main" {
  project_id = var.qovery_project_id
  cluster_id = var.qovery_cluster_id
  name       = var.environment_name
  mode       = var.environment_mode

  # Environment-scoped variables — shared by all services (no duplication!)
  environment_variables = [
    {
      key   = "NODE_ENV"
      value = var.environment_mode == "PRODUCTION" ? "production" : "development"
    },
    {
      key   = "LOG_LEVEL"
      value = var.environment_mode == "PRODUCTION" ? "warn" : "info"
    }
  ]
}

# --- Deployment Stages ---

resource "qovery_deployment_stage" "database" {
  environment_id = qovery_environment.main.id
  name           = "Database"
  description    = "Database must start before backend"
}

resource "qovery_deployment_stage" "backend" {
  environment_id = qovery_environment.main.id
  name           = "Backend"
  description    = "Backend API services"
  is_after       = qovery_deployment_stage.database.id
}

resource "qovery_deployment_stage" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "Frontend"
  description    = "Frontend applications"
  is_after       = qovery_deployment_stage.backend.id
}

# --- Database ---

resource "qovery_database" "postgres" {
  environment_id = qovery_environment.main.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = var.use_managed_database ? "MANAGED" : "CONTAINER"
  storage        = var.use_managed_database ? 20 : 10
  cpu            = var.use_managed_database ? 0 : 250
  memory         = var.use_managed_database ? 0 : 512
  accessibility  = "PRIVATE"

  deployment_stage_id = qovery_deployment_stage.database.id
}

# --- Backend API ---

resource "qovery_application" "backend" {
  environment_id = qovery_environment.main.id
  name           = "backend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/backend"
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = var.environment_mode == "PRODUCTION" ? 2 : 1
  max_running_instances = var.environment_mode == "PRODUCTION" ? 4 : 1

  deployment_stage_id = qovery_deployment_stage.backend.id
  auto_deploy         = true

  ports = [
    {
      internal_port       = 8080
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      name                = "api"
    }
  ]

  healthchecks = {
    liveness_probe = {
      type = {
        http = {
          port   = 8080
          scheme = "HTTP"
          path   = "/health"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
    readiness_probe = {
      type = {
        http = {
          port   = 8080
          scheme = "HTTP"
          path   = "/health"
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  # Service-specific variables (only what's unique to this service)
  environment_variables = [
    {
      key   = "PORT"
      value = "8080"
    }
  ]

  # Aliases: live pointers to built-in variables (stay in sync automatically)
  # Use aliases instead of duplicating connection strings!
  environment_variable_aliases = [
    {
      key   = "DATABASE_URL"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL"
    },
    {
      key   = "DATABASE_HOST"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_HOST_INTERNAL"
    },
    {
      key   = "DATABASE_PASSWORD"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_PASSWORD"
    }
  ]

  # Overrides: change the value of a variable inherited from environment scope
  # Backend needs debug logging — override the environment-level "warn"/"info"
  environment_variable_overrides = var.environment_mode != "PRODUCTION" ? [
    {
      key   = "LOG_LEVEL"
      value = "debug"
    }
  ] : []

  secrets = var.jwt_secret != "" ? [
    {
      key   = "JWT_SECRET"
      value = var.jwt_secret
    }
  ] : []
}

# --- Frontend ---

resource "qovery_application" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "frontend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/frontend"
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = 1
  max_running_instances = 2

  deployment_stage_id = qovery_deployment_stage.frontend.id
  auto_deploy         = true

  ports = [
    {
      internal_port       = 3000
      external_port       = 443
      protocol            = "HTTP"
      publicly_accessible = true
      name                = "web"
    }
  ]

  healthchecks = {
    liveness_probe = {
      type = {
        http = {
          port   = 3000
          scheme = "HTTP"
          path   = "/"
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  # NODE_ENV and LOG_LEVEL are inherited from the environment scope — no need to set them here!
  # Only set service-specific variables.

  # Interpolation: compose a URL from an alias (resolved at deploy time)
  environment_variables = [
    {
      key   = "NEXT_PUBLIC_API_URL"
      value = "https://{{BACKEND_HOST_EXTERNAL}}"
    }
  ]

  # Aliases: create a friendly name that points to the backend's auto-generated host variable
  environment_variable_aliases = [
    {
      key   = "BACKEND_HOST_EXTERNAL"
      value = "QOVERY_APPLICATION_Z${upper(element(split("-", qovery_application.backend.id), 0))}_HOST_EXTERNAL"
    }
  ]
}

# --- Outputs ---

output "environment_id" {
  value = qovery_environment.main.id
}

output "backend_url" {
  value = qovery_application.backend.external_host
}

output "frontend_url" {
  value = qovery_application.frontend.external_host
}

output "database_host" {
  value = qovery_database.postgres.internal_host
}
```

---

