# Change one service in any way EXCEPT delete it.
# Replace <APP_UUID> with the real service UUID resolved in Phase 1.
# NOTE: `method != "DELETE"` blocks HTTP DELETE only. If a destructive action on this
# service is exposed as POST/PUT and you must block it too, scope more tightly or add
# an explicit path guard. Do NOT add a `package` line — Qovery injects one per token.

default allow := false

allowed_application_id := "<APP_UUID>"

allow if {
	input.request.method != "DELETE"
	input.qovery_metadata.service_id == allowed_application_id
}
