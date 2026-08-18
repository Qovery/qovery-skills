# Clone and deploy ANY environment in one project — and nothing else.
# Scope is the project: input.qovery_metadata.project_id resolves from the request path for
# clone/deploy action routes (verified live), so this covers every environment under the project,
# including freshly cloned ones. Reads, deletes, stops, and other projects are all denied by default.
# Replace <PROJECT_UUID> with the real project UUID resolved in Phase 1.
# Do NOT add a `package` line — Qovery injects one per token.

default allow := false

allowed_project_id := "<PROJECT_UUID>"

# Deploy any environment in the project:  POST /environment/{id}/deploy
allow if {
	input.request.method == "POST"
	input.qovery_metadata.project_id == allowed_project_id
	input.request.path[0] == "api"
	input.request.path[1] == "environment"
	input.request.path[3] == "deploy"
	count(input.request.path) == 4
}

# Clone any environment in the project:  POST /environment/{id}/clone
allow if {
	input.request.method == "POST"
	input.qovery_metadata.project_id == allowed_project_id
	input.request.path[0] == "api"
	input.request.path[1] == "environment"
	input.request.path[3] == "clone"
	count(input.request.path) == 4
}
