## Phase 2: Generate Terraform Manifests

Generate HCL files that reproduce the existing Qovery configuration exactly. The agent reads each API response from Phase 1 and translates it into the corresponding Terraform resource.

### 2.1 Provider + Variables (boilerplate)

**`provider.tf`:**
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

**`variables.tf`:**
```hcl
variable "qovery_access_token" {
  description = "Qovery API access token"
  type        = string
  sensitive   = true
}

variable "qovery_organization_id" {
  description = "Qovery organization ID"
  type        = string
}

variable "qovery_project_id" {
  description = "Qovery project ID"
  type        = string
}

variable "qovery_cluster_id" {
  description = "Qovery cluster ID"
  type        = string
}
```

Add a `variable` block for each secret environment variable found (with `sensitive = true`).

### 2.2 Data Sources

```hcl
data "qovery_organization" "main" {
  id = var.qovery_organization_id
}

data "qovery_cluster" "main" {
  id             = var.qovery_cluster_id
  organization_id = var.qovery_organization_id
}
```

### 2.3 Mapping Rules — API to HCL

For each resource type below, map the API response fields to HCL attributes. Use the sanitized service name as the Terraform resource name (lowercase, hyphens to underscores).

IMPORTANT: When generating HCL, include ALL fields from the API response that have corresponding Terraform attributes. Omitting fields causes `terraform plan` to show diffs.

---

### qovery_environment

**API:** `GET /environment/{envId}`
**Mapping:**

| API Field | HCL Attribute |
|---|---|
| `name` | `name` |
| `mode` | `mode` (DEVELOPMENT, STAGING, PRODUCTION, PREVIEW) |
| `cluster_id` | `cluster_id` |

**Example:**
```hcl
resource "qovery_environment" "production" {
  project_id = var.qovery_project_id
  cluster_id = var.qovery_cluster_id
  name       = "production"
  mode       = "PRODUCTION"
}
```

---

### qovery_deployment_stage

**API:** `GET /environment/{envId}/deploymentStage`
**Mapping:**

| API Field | HCL Attribute |
|---|---|
| `name` | `name` |
| `description` | `description` |
| ordering | `is_before` or `is_after` (reference another stage) |

Only generate if custom stages exist (more than just the default stage). Use `is_after` to chain stages.

**Example:**
```hcl
resource "qovery_deployment_stage" "infrastructure" {
  environment_id = qovery_environment.production.id
  name           = "infrastructure"
}

resource "qovery_deployment_stage" "backend" {
  environment_id = qovery_environment.production.id
  name           = "backend"
  is_after       = qovery_deployment_stage.infrastructure.id
}
```

---

### qovery_application

**API:** `GET /application/{appId}`
**Mapping:**

| API Field | HCL Attribute |
|---|---|
| `name` | `name` |
| `git_repository.url` | `git_repository.url` |
| `git_repository.branch` | `git_repository.branch` |
| `git_repository.root_path` | `git_repository.root_path` |
| `build_mode` | `build_mode` (DOCKER, BUILDPACKS) |
| `dockerfile_path` | `dockerfile_path` |
| `cpu` | `cpu` (millicores) |
| `memory` | `memory` (MB) |
| `min_running_instances` | `min_running_instances` |
| `max_running_instances` | `max_running_instances` |
| `auto_preview` | `auto_preview` |
| `auto_deploy` | `auto_deploy` |
| `ports[]` | `ports` block (map keyed by name) |
| `healthchecks` | `healthchecks` block |
| `deployment_stage_id` | `deployment_stage_id` (reference) |

**Ports mapping:**
```hcl
ports = {
  "http" = {
    internal_port       = 8080
    external_port       = 443
    publicly_accessible = true
    protocol            = "HTTP"
    is_default          = true
  }
}
```

**Healthchecks mapping** (include both readiness and liveness if present):
```hcl
healthchecks = {
  readiness_probe = {
    type = {
      http = {
        path   = "/health"
        port   = 8080
        scheme = "HTTP"
      }
    }
    initial_delay_seconds = 30
    period_seconds        = 10
    timeout_seconds       = 5
    failure_threshold     = 3
  }
}
```

**Example:**
```hcl
resource "qovery_application" "backend" {
  environment_id = qovery_environment.production.id
  name           = "backend"

  git_repository = {
    url       = "https://github.com/org/repo.git"
    branch    = "main"
    root_path = "/backend"
  }

  build_mode      = "DOCKER"
  dockerfile_path = "Dockerfile"
  cpu             = 1000
  memory          = 2048
  min_running_instances = 1
  max_running_instances = 2
  auto_preview = false
  auto_deploy  = false

  ports = {
    "http" = {
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
        tcp = { port = 8080 }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      failure_threshold     = 9
    }
  }

  deployment_stage_id = qovery_deployment_stage.backend.id
}
```

---

### qovery_container

**API:** `GET /container/{containerId}`
**Mapping:** Similar to application but uses `image_name`, `tag`, `registry_id` instead of `git_repository`.

**Example:**
```hcl
resource "qovery_container" "worker" {
  environment_id = qovery_environment.production.id
  name           = "worker"
  image_name     = "my-org/worker"
  tag            = "v1.2.3"
  registry_id    = "{registry-id}"
  cpu            = 500
  memory         = 512
  min_running_instances = 1
  max_running_instances = 1

  ports = {}
  healthchecks = {}
}
```

---

### qovery_database

**API:** `GET /database/{dbId}`
**Mapping:**

| API Field | HCL Attribute |
|---|---|
| `name` | `name` |
| `type` | `type` (POSTGRESQL, MYSQL, REDIS, MONGODB) |
| `version` | `version` |
| `mode` | `mode` (CONTAINER, MANAGED) |
| `accessibility` | `accessibility` (PRIVATE, PUBLIC) |
| `cpu` | `cpu` (container mode only) |
| `memory` | `memory` (container mode only) |
| `storage` | `storage` (container mode only) |
| `instance_type` | `instance_type` (managed mode only) |

**WARNING for managed databases:**
> Add a comment above every managed database resource:
> ```hcl
> # WARNING: This is a MANAGED database. Any change that forces recreation
> # will DESTROY ALL DATA. Ensure backups exist before modifying.
> ```

**Example (container):**
```hcl
resource "qovery_database" "postgres" {
  environment_id = qovery_environment.production.id
  name           = "postgres"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "CONTAINER"
  accessibility  = "PRIVATE"
  cpu            = 250
  memory         = 256
  storage        = 10
}
```

**Example (managed):**
```hcl
# WARNING: MANAGED database — recreation DESTROYS ALL DATA. Ensure backups exist.
resource "qovery_database" "postgres_prod" {
  environment_id = qovery_environment.production.id
  name           = "postgres-prod"
  type           = "POSTGRESQL"
  version        = "16"
  mode           = "MANAGED"
  accessibility  = "PRIVATE"
  instance_type  = "db.t3.medium"
}
```

---

### qovery_job

**API:** `GET /job/{jobId}`
**Mapping:**

| API Field | HCL Attribute |
|---|---|
| `name` | `name` |
| `cpu` | `cpu` |
| `memory` | `memory` |
| `max_nb_restart` | `max_nb_restart` |
| `max_duration_seconds` | `max_duration_seconds` |
| `source.docker.git_repository` | `source.docker.git_repository` block |
| `source.docker.dockerfile_raw` | `source.docker.dockerfile_raw` |
| `source.image` | `source.image` block |
| `schedule.on_start` | `schedule.on_start` block (lifecycle) |
| `schedule.cronjob` | `schedule.cronjob` block (cron) |

**Example (lifecycle job):**
```hcl
resource "qovery_job" "db_migration" {
  environment_id     = qovery_environment.production.id
  name               = "db-migration"
  cpu                = 500
  memory             = 512
  max_nb_restart     = 1
  max_duration_seconds = 300
  auto_preview       = false

  source = {
    docker = {
      git_repository = {
        url       = "https://github.com/org/repo.git"
        branch    = "main"
        root_path = "/migrations"
      }
      dockerfile_path = "Dockerfile"
    }
  }

  schedule = {
    on_start = {}
  }
}
```

**Example (cron job):**
```hcl
resource "qovery_job" "cleanup" {
  environment_id     = qovery_environment.production.id
  name               = "cleanup"
  cpu                = 250
  memory             = 256
  max_nb_restart     = 0
  max_duration_seconds = 60

  source = {
    image = {
      image_name  = "curlimages/curl"
      tag         = "8.11.1"
      registry_id = "{docker-hub-registry-id}"
    }
  }

  schedule = {
    cronjob = {
      entrypoint   = "sh"
      arguments    = ["-c", "curl -sf https://api.example.com/cleanup"]
      scheduled_at = "0 0 * * *"
      timezone     = "Etc/UTC"
    }
  }
}
```

---

### qovery_helm

**API:** `GET /helm/{helmId}`
**Mapping:** name, source (repository or git), chart_name, chart_version, values_override, ports.

Note: May also need a `qovery_helm_repository` resource if using a custom Helm repository.

**Example:**
```hcl
resource "qovery_helm_repository" "bitnami" {
  organization_id = var.qovery_organization_id
  name            = "bitnami"
  kind            = "HTTPS"
  url             = "https://charts.bitnami.com/bitnami"
}

resource "qovery_helm" "redis" {
  environment_id = qovery_environment.production.id
  name           = "redis"

  source = {
    helm_repository = {
      helm_repository_id = qovery_helm_repository.bitnami.id
      chart_name         = "redis"
      chart_version      = "18.6.1"
    }
  }

  values_override = {
    set = {
      "architecture" = "standalone"
      "auth.enabled" = "false"
    }
  }

  ports = {}
}
```

---

### qovery_terraform_service

**API:** `GET /terraformService/{id}`
**Mapping:** name, source (git), engine (TERRAFORM/OPENTOFU), terraform_backend_config, variables.

**Example:**
```hcl
resource "qovery_terraform_service" "s3_bucket" {
  environment_id = qovery_environment.production.id
  name           = "s3-bucket"

  source = {
    docker = {
      git_repository = {
        url       = "https://github.com/org/infra.git"
        branch    = "main"
        root_path = "/terraform/s3"
      }
    }
  }

  variables = {
    "AWS_REGION"  = "us-east-1"
    "BUCKET_NAME" = "my-bucket"
  }
}
```

---

### Environment Variables

**API:** `GET /environment/{envId}/environmentVariable` + per-service

**Rules:**
- **Non-secret variables:** Include `key` + `value` directly in HCL
- **Secret variables:** Include `key` only. Set `value = var.secret_{sanitized_key}` and add a corresponding `variable` block to `variables.tf` with `sensitive = true`. The actual value goes in `.tfvars` or `TF_VAR_` env var.
- **Aliases:** Use `environment_variable_aliases` block on the service
- **Overrides:** Use `environment_variable_overrides` block

Add environment-level variables to the `qovery_environment` resource. Add service-level variables to the corresponding `qovery_application`/`qovery_container`/`qovery_job` resource.

**NEVER write actual secret values to `.tf` files.**

---

### 2.4 Outputs

**`outputs.tf`:**
```hcl
output "environment_id" {
  value = qovery_environment.production.id
}

# One output per application's external host
output "backend_host" {
  value = qovery_application.backend.external_host
}
```

### 2.5 terraform.tfvars

Generate with actual values for non-secret variables. Secret values as placeholders:

```hcl
qovery_access_token    = "PASTE_TOKEN_HERE_OR_USE_TF_VAR"  # Use TF_VAR_qovery_access_token instead
qovery_organization_id = "{actual-org-id}"
qovery_project_id      = "{actual-project-id}"
qovery_cluster_id      = "{actual-cluster-id}"

# Secrets — set via TF_VAR_ env vars or paste here (DO NOT commit to git)
# secret_database_password = "REPLACE_ME"
```

### 2.6 .gitignore

```
.terraform/
*.tfstate
*.tfstate.backup
terraform-test.tfvars
```
