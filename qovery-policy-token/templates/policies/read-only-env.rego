# Read-only access to a single environment.
# The token can GET/HEAD anything scoped to <ENV_UUID> and nothing else.
# Replace <ENV_UUID> with the real environment UUID resolved in Phase 1.
# Do NOT add a `package` line — Qovery injects one per token.

default allow := false

allowed_environment_id := "<ENV_UUID>"

allow if {
	input.request.method in {"GET", "HEAD"}
	input.qovery_metadata.environment_id == allowed_environment_id
}
