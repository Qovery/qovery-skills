# Constrain the request body: allow creating environment variables on ONE application,
# but only those whose key starts with "FEATURE_".
# Replace <APP_UUID> with the real application UUID resolved in Phase 1.
# Do NOT add a `package` line — Qovery injects one per token.

default allow := false

allowed_application_id := "<APP_UUID>"

allow if {
	input.request.method == "POST"
	input.request.path == ["api", "application", allowed_application_id, "environmentVariable"]
	startswith(input.request.body.key, "FEATURE_")
}
