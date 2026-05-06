## PHASE 5: Deploy via Terraform Provider (Production Path)

Use this path when the user chose "Terraform" or wants a production-grade, reproducible setup. This is the RECOMMENDED approach for production environments.

### 5.1 Provider Configuration

Create a `qovery.tf` file (or `main.tf`) at the project root:

```hcl
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
```

### 5.2 Variables File

Create a `variables.tf`:

```hcl
variable "qovery_access_token" {
  description = "Qovery API token"
  type        = string
  sensitive   = true
}

variable "qovery_organization_id" {
  description = "Qovery Organization ID"
  type        = string
}

variable "qovery_project_id" {
  description = "Qovery Project ID"
  type        = string
}

variable "qovery_cluster_id" {
  description = "Qovery Cluster ID"
  type        = string
}

variable "environment_name" {
  description = "Name of the environment"
  type        = string
  default     = "production"
}

variable "environment_mode" {
  description = "Environment mode: PRODUCTION, STAGING, or DEVELOPMENT"
  type        = string
  default     = "PRODUCTION"
}

variable "git_repository_url" {
  description = "Git repository URL"
  type        = string
}

variable "git_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}

variable "auto_deploy_enabled" {
  description = "Enable auto-deploy on git push"
  type        = bool
  default     = true
}
```

### 5.3 Look Up Existing Resources (Alternative to hardcoding IDs)

If the user prefers looking up resources by name instead of providing IDs:

```hcl
data "qovery_organization" "my_org" {
  name = "My Organization"
}

data "qovery_project" "my_project" {
  organization_id = data.qovery_organization.my_org.id
  name            = "My Project"
}

data "qovery_cluster" "my_cluster" {
  organization_id = data.qovery_organization.my_org.id
  name            = "production"
}
```

Then use `data.qovery_project.my_project.id` instead of `var.qovery_project_id`, etc.

### 5.4 Environment

```hcl
resource "qovery_environment" "main" {
  project_id = var.qovery_project_id
  cluster_id = var.qovery_cluster_id
  name       = var.environment_name
  mode       = var.environment_mode
}
```

### 5.5 Deployment Stages

Deployment stages control the order in which services are deployed. This is critical for dependencies (e.g., database must be running before the backend starts).

```hcl
# Stage 1: Infrastructure (databases, terraform services)
resource "qovery_deployment_stage" "infrastructure" {
  environment_id = qovery_environment.main.id
  name           = "Infrastructure"
  description    = "Databases and cloud resources"
}

# Stage 2: Backend
resource "qovery_deployment_stage" "backend" {
  environment_id = qovery_environment.main.id
  name           = "Backend"
  description    = "Backend API services"
  is_after       = qovery_deployment_stage.infrastructure.id
}

# Stage 3: Frontend
resource "qovery_deployment_stage" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "Frontend"
  description    = "Frontend applications"
  is_after       = qovery_deployment_stage.backend.id
}

# Stage 4: Jobs (seed data, migrations, etc.)
resource "qovery_deployment_stage" "jobs" {
  environment_id = qovery_environment.main.id
  name           = "Jobs"
  description    = "Background jobs and data seeding"
  is_after       = qovery_deployment_stage.backend.id
}
```

### 5.6 Database — Container Mode (Dev/Test)

```hcl
resource "qovery_database" "postgres" {
  environment_id = qovery_environment.main.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "CONTAINER"
  storage        = 10
  cpu            = 250
  memory         = 512
  accessibility  = "PRIVATE"

  deployment_stage_id = qovery_deployment_stage.infrastructure.id
}
```

### 5.7 Database — Managed Mode (Production)

```hcl
resource "qovery_database" "postgres" {
  environment_id = qovery_environment.main.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "MANAGED"
  instance_type  = "db.t3.medium"
  storage        = 20
  accessibility  = "PRIVATE"

  deployment_stage_id = qovery_deployment_stage.infrastructure.id
}
```

### 5.8 Database — RDS Aurora via Terraform Service (Advanced Production)

For advanced database needs (Aurora Serverless, custom VPC configuration, etc.), use a Qovery Terraform service that runs your own Terraform module:

```hcl
resource "qovery_terraform_service" "rds_aurora" {
  environment_id      = qovery_environment.main.id
  deployment_stage_id = qovery_deployment_stage.infrastructure.id
  name                = "rds-aurora"
  description         = "AWS RDS Aurora Serverless v2 PostgreSQL"
  icon_uri            = "app://qovery-console/postgresql"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/terraform/rds-aurora"
  }

  auto_deploy = true

  engine = "TERRAFORM"
  engine_version = {
    explicit_version = "1.13"
  }

  # State managed inside the Kubernetes cluster (zero config)
  backend = {
    kubernetes = {}
  }

  job_resources = {
    cpu    = 500
    memory = 512
  }

  variables = [
    {
      key       = "aws_region"
      value     = "{{QOVERY_CLOUD_PROVIDER_REGION}}"
      is_secret = false
    },
    {
      key       = "vpc_id"
      value     = "{{QOVERY_KUBERNETES_CLUSTER_VPC_ID}}"
      is_secret = false
    },
    {
      key       = "cluster_name"
      value     = "my-aurora-cluster"
      is_secret = false
    }
  ]

  tfvars_files = []
}
```

The Terraform code in `/terraform/rds-aurora/` would be standard Terraform (e.g., `main.tf` with `aws_rds_cluster` resource). Qovery runs `terraform plan` and `terraform apply` inside a pod on the cluster, using the cluster's cloud credentials by default.

### 5.9 Application (Backend API)

```hcl
resource "qovery_application" "backend" {
  environment_id = qovery_environment.main.id
  name           = "backend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/backend"    # Adjust for monorepos, use "/" for single-app repos
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = 1
  max_running_instances = 2

  deployment_stage_id = qovery_deployment_stage.backend.id
  auto_deploy         = var.auto_deploy_enabled

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

  environment_variables = [
    {
      key   = "PORT"
      value = "8080"
    },
    {
      key   = "NODE_ENV"
      value = var.environment_mode == "PRODUCTION" ? "production" : "development"
    }
  ]

  secrets = [
    {
      key   = "JWT_SECRET"
      value = var.jwt_secret
    }
  ]
}
```

IMPORTANT: Adapt `internal_port`, `healthchecks.path`, and `environment_variables` to match the user's actual application. The health check path should be a real endpoint that returns 200 OK when the app is healthy.

### 5.10 Application (Frontend — Next.js / React / Vite)

```hcl
resource "qovery_application" "frontend" {
  environment_id = qovery_environment.main.id
  name           = "frontend"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/frontend"    # Adjust for monorepos
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"

  cpu                   = 500
  memory                = 512
  min_running_instances = 1
  max_running_instances = 2

  deployment_stage_id = qovery_deployment_stage.frontend.id
  auto_deploy         = var.auto_deploy_enabled

  ports = [
    {
      internal_port       = 3000    # 3000 for Next.js, 80 for nginx-served SPA
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
          port   = 3000    # Match internal_port
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

  environment_variables = [
    {
      key   = "NODE_ENV"
      value = "production"
    },
    {
      key   = "NEXT_PUBLIC_API_URL"
      value = "https://{{BACKEND_HOST_EXTERNAL}}"
    }
  ]

  # Create an alias to reference the backend's external host
  environment_variable_aliases = [
    {
      key   = "BACKEND_HOST_EXTERNAL"
      value = "QOVERY_APPLICATION_Z${upper(element(split("-", qovery_application.backend.id), 0))}_HOST_EXTERNAL"
    }
  ]
}
```

IMPORTANT: The `QOVERY_APPLICATION_Z{ID_PREFIX}_HOST_EXTERNAL` pattern is how Qovery auto-generates environment variable names for service interconnection. The ID prefix is the first segment of the service UUID (before the first hyphen), uppercased, prefixed with `Z`. This alias lets the frontend reference the backend's public URL dynamically.

### 5.11 Container Service (from Registry)

```hcl
resource "qovery_container" "worker" {
  environment_id = qovery_environment.main.id
  name           = "worker"
  registry_id    = "{registry-uuid}"    # Get from Qovery Console > Organization Settings > Container Registries
  image_name     = "my-org/my-worker"
  tag            = "v1.0.0"

  cpu    = 500
  memory = 512
  min_running_instances = 1
  max_running_instances = 1

  deployment_stage_id = qovery_deployment_stage.backend.id
  auto_deploy         = true

  healthchecks = {
    liveness_probe = {
      type = {
        tcp = {
          port = 8080
        }
      }
      initial_delay_seconds = 10
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
}
```

### 5.12 Helm Chart

```hcl
# First, register the Helm repository (at organization level)
resource "qovery_helm_repository" "bitnami" {
  organization_id       = var.qovery_organization_id
  name                  = "bitnami"
  kind                  = "HTTPS"
  url                   = "https://charts.bitnami.com/bitnami"
  skip_tls_verification = false
}

# Deploy a Helm chart
resource "qovery_helm" "redis" {
  environment_id      = qovery_environment.main.id
  deployment_stage_id = qovery_deployment_stage.infrastructure.id
  name                = "redis"
  description         = "Redis cache"

  allow_cluster_wide_resources = false

  source = {
    helm_repository = {
      helm_repository_id = qovery_helm_repository.bitnami.id
      chart_name         = "redis"
      chart_version      = "20.0.0"
    }
  }

  auto_deploy = true
  timeout_sec = 600

  # Override Helm values — use qovery.env.VAR_NAME to inject Qovery env vars
  values_override = {
    file = {
      raw = {
        file1 = {
          content = <<-EOT
            architecture: standalone
            auth:
              enabled: true
              password: "qovery.env.REDIS_PASSWORD"
            master:
              resources:
                requests:
                  cpu: 250m
                  memory: 256Mi
          EOT
        }
      }
    }
  }

  ports = {
    "redis" = {
      service_name        = "redis-master"
      namespace           = null
      internal_port       = 6379
      external_port       = 6379
      protocol            = "TCP"
      publicly_accessible = false
      is_default          = true
    }
  }

  environment_variables = []
}
```

IMPORTANT: In Helm values, use `qovery.env.VARIABLE_NAME` to inject Qovery environment variables into chart values. This is a Qovery-specific macro that gets replaced at deploy time.

### 5.13 Lifecycle Job (DB Migrations / Seeding)

A lifecycle job runs automatically when an environment lifecycle event occurs (deploy, stop, or delete).

```hcl
resource "qovery_job" "db_migrate" {
  environment_id = qovery_environment.main.id
  name           = "db-migrate"

  source = {
    docker = {
      git_repository = {
        url       = var.git_repository_url
        branch    = var.git_branch
        root_path = "/backend"
      }
      dockerfile_path = "Dockerfile"
    }
  }

  # Runs on environment deploy (start)
  schedule = {
    on_start = {
      enabled   = true
      arguments = ["npm", "run", "migrate"]
    }
  }

  cpu    = 500
  memory = 512

  deployment_stage_id  = qovery_deployment_stage.backend.id
  max_duration_seconds = 600
  max_nb_restart       = 0
  auto_deploy          = true

  healthchecks = {
    liveness_probe = {
      type = {
        exec = {
          command = ["echo", "ok"]
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  # Use an alias for database connection — stays in sync automatically
  environment_variable_aliases = [
    {
      key   = "DATABASE_URL"
      value = "QOVERY_DATABASE_POSTGRESQL_POSTGRES_CONNECTION_URI_INTERNAL"
    }
  ]
}
```

### 5.14 Cron Job

A cron job runs on a schedule defined with CRON syntax.

```hcl
resource "qovery_job" "daily_cleanup" {
  environment_id = qovery_environment.main.id
  name           = "daily-cleanup"

  source = {
    docker = {
      git_repository = {
        url       = var.git_repository_url
        branch    = var.git_branch
        root_path = "/jobs/cleanup"
      }
      dockerfile_path = "Dockerfile"
    }
  }

  schedule = {
    cronjob = {
      schedule = "0 2 * * *"    # Daily at 2 AM UTC
      command = {
        entrypoint = ""
        arguments  = []
      }
    }
  }

  cpu    = 250
  memory = 256

  deployment_stage_id  = qovery_deployment_stage.jobs.id
  max_duration_seconds = 1800
  max_nb_restart       = 0
  auto_deploy          = true

  healthchecks = {
    liveness_probe = {
      type = {
        exec = {
          command = ["echo", "ok"]
        }
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }
}
```

### 5.15 Terraform Service (S3, Lambda, CloudFront, etc.)

For any cloud resource not natively managed by Qovery, use a Terraform service. This runs your own Terraform code as a Qovery-managed job:

```hcl
resource "qovery_terraform_service" "s3_bucket" {
  environment_id      = qovery_environment.main.id
  deployment_stage_id = qovery_deployment_stage.infrastructure.id
  name                = "s3-bucket"
  description         = "AWS S3 storage bucket"

  git_repository = {
    url       = var.git_repository_url
    branch    = var.git_branch
    root_path = "/terraform/s3-bucket"
  }

  auto_deploy = true

  engine = "TERRAFORM"    # Or "OPENTOFU" for OpenTofu
  engine_version = {
    explicit_version = "1.13"
  }

  # State managed inside the Kubernetes cluster (zero config, recommended)
  backend = {
    kubernetes = {}
  }

  job_resources = {
    cpu    = 500
    memory = 512
  }

  variables = [
    {
      key       = "aws_region"
      value     = "{{QOVERY_CLOUD_PROVIDER_REGION}}"
      is_secret = false
    },
    {
      key       = "bucket_name"
      value     = "my-app-storage"
      is_secret = false
    }
  ]

  tfvars_files = []
}
```

The Terraform code in `/terraform/s3-bucket/` would be standard Terraform (e.g., `main.tf` with `aws_s3_bucket` resource). Qovery runs `terraform plan` and `terraform apply` inside a pod on the cluster, using the cluster's cloud credentials by default.

### 5.16 Outputs

```hcl
output "environment_id" {
  value       = qovery_environment.main.id
  description = "Qovery Environment ID"
}

output "backend_id" {
  value       = qovery_application.backend.id
  description = "Backend Application ID"
}

output "backend_external_host" {
  value       = qovery_application.backend.external_host
  description = "Backend public URL"
}

output "frontend_external_host" {
  value       = qovery_application.frontend.external_host
  description = "Frontend public URL"
}

output "database_internal_host" {
  value       = qovery_database.postgres.internal_host
  description = "Database internal hostname (accessible within the cluster)"
}

output "database_port" {
  value       = qovery_database.postgres.port
  description = "Database port"
}
```

### 5.17 Terraform Values File

Create a `terraform.tfvars` (NEVER commit secrets to git — use environment variables):

```hcl
qovery_organization_id = "your-org-uuid"
qovery_project_id      = "your-project-uuid"
qovery_cluster_id      = "your-cluster-uuid"
environment_name       = "production"
environment_mode       = "PRODUCTION"
git_repository_url     = "https://github.com/user/repo"
git_branch             = "main"
auto_deploy_enabled    = true
```

For the API token, ALWAYS use an environment variable:
```bash
export TF_VAR_qovery_access_token="your-api-token"
```

### 5.18 Deploy with Terraform

```bash
# Initialize
terraform init

# Set API token (never hardcode this)
export TF_VAR_qovery_access_token="your-api-token"

# Preview changes
terraform plan

# Apply
terraform apply

# View outputs
terraform output
```

---

