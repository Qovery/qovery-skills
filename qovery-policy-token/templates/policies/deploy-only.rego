# Deploy a specific service/application and nothing else.
# Replace <ENV_UUID> and <APP_UUID> with real UUIDs resolved in Phase 1.
# Keep only the rule(s) that match the deploy route you intend to allow.
# Do NOT add a `package` line — Qovery injects one per token.

default allow := false

allowed_environment_id := "<ENV_UUID>"
allowed_application_id := "<APP_UUID>"

# Deploy a single service within the environment
allow if input.request.path == ["api", "environment", allowed_environment_id, "service", "deploy"]

# Deploy a single application directly
allow if input.request.path == ["api", "application", allowed_application_id, "deploy"]
