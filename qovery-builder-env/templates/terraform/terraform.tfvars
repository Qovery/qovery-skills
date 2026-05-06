qovery_organization_id = "{org-id}"
qovery_cluster_id      = "{cluster-id}"
isolation              = "project-per-builder"  # or "shared-project"
ttl_stop_cron          = "0 20 * * 1-5"         # Stop at 8pm weekdays
ttl_delete_cron        = ""                      # Empty = no auto-delete
ide_git_repository_url = "https://github.com/{org}/qovery-builder-platform"
ide_dockerfile_path    = "dockerfiles/vscode-server/Dockerfile"
workspace_cpu          = 1000
workspace_memory       = 2048
include_database       = true

# Each builder gets their own isolated environment (NEVER shared)
builders = {
  alice = { email = "alice@company.com", team = "sales" }
  bob   = { email = "bob@company.com",   team = "finance" }
  carol = { email = "carol@company.com", team = "ops" }
}

# To add a new builder: add a line here and run `terraform apply`
# To remove a builder: remove the line and run `terraform apply`
