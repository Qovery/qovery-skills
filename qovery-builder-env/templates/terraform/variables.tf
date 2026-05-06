variable "qovery_organization_id" {
  description = "Qovery organization ID"
  type        = string
}

variable "qovery_cluster_id" {
  description = "Cluster ID for builder environments"
  type        = string
}

variable "isolation" {
  description = "Isolation mode: 'shared-project' or 'project-per-builder'"
  type        = string
  default     = "project-per-builder"
}

variable "ttl_stop_cron" {
  description = "Cron schedule for TTL auto-stop (e.g., '0 20 * * 1-5' for 8pm weekdays)"
  type        = string
  default     = "0 20 * * 1-5"
}

variable "ttl_delete_cron" {
  description = "Cron schedule for TTL auto-delete (e.g., '0 0 * * 0' for weekly). Set to empty string to disable."
  type        = string
  default     = ""
}

variable "builders" {
  description = "Map of builders to provision"
  type = map(object({
    email = string
    team  = string
  }))
  default = {}
}

variable "ide_git_repository_url" {
  description = "Git repository URL containing the workspace Dockerfile"
  type        = string
}

variable "ide_dockerfile_path" {
  description = "Path to the Dockerfile within the repository"
  type        = string
  default     = "dockerfiles/vscode-server/Dockerfile"
}

variable "workspace_cpu" {
  description = "CPU allocation for workspace (millicores)"
  type        = number
  default     = 1000
}

variable "workspace_memory" {
  description = "Memory allocation for workspace (MB)"
  type        = number
  default     = 2048
}

variable "include_database" {
  description = "Include a PostgreSQL database in each builder environment"
  type        = bool
  default     = true
}
