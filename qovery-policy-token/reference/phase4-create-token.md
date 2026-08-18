# Phase 4 — Create the Policy Token

Only reach this phase when: (a) the local matrix is fully green (Phase 3), and (b) the user has explicitly confirmed the policy (Phase 2.5). Creation is a one-way step for the policy — there is no edit endpoint, so a wrong policy means deleting this token and creating another.

## 4.1 The create endpoint

```
POST https://api.qovery.com/organization/{organizationId}/policyApiToken
Authorization: Token $QOVERY_API_TOKEN        # a regular OWNER/ADMIN token
Content-Type: application/json
```

Request body:

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Unique within the org (`409` if taken) |
| `description` | no | What the token is for — shows in the Console and audit context |
| `opa_policy` | yes | The Rego policy as a string, **without** a `package` line |
| `expires_at` | no | RFC 3339 timestamp; omit or `null` for no expiry |

Response (2xx) includes: `id` (the token UUID — keep it, needed to revoke), `name`, `description`, `created_at`, and **`token`** — the secret value (`sk-qov-01-...`), used later as `Authorization: Token <token>`. **This is the only response that ever contains the token value.**

## 4.2 Create without exposing the secret

Use `templates/scripts/create-policy-token.sh` — it POSTs the policy and captures both `id` and `token` into shell state without ever printing the secret:

```bash
bash templates/scripts/create-policy-token.sh "$QOVERY_ORG_ID" "deploy-agent" policy.rego \
  "Deploys the staging environment"       # optional description
  # optional 5th arg: expires_at (RFC 3339)
```

The script:
1. Reads `policy.rego`, verifies it has **no** `package` line (else the API returns `400`), and JSON-encodes it with `jq` (so newlines/quotes are escaped correctly).
2. POSTs with the `User-Agent` header and owner/admin auth: `Authorization: Token $QOVERY_API_TOKEN` if set, otherwise falling back to the CLI's OIDC session (`Authorization: Bearer $(qovery auth token --print)`, used inline). Either works — the API accepts an API token or an OIDC Bearer for an owner/admin.
3. On success, writes the token to a shell env file the *user* controls and never echoes it — following the secrecy rules in `auth.md`. It prints only the non-secret `id`, `name`, and a masked confirmation.
4. On error, prints the HTTP status and the specific remedy below.

> **Token-secrecy rules (from `auth.md`) apply in full here.** Never `echo` the token, never store it in a variable the agent then prints, never write it into a repo file or generated script. Refer to it as `***`. It flows into the Phase 5 live-verify inline via an env var.

## 4.3 Error handling

| Status | Meaning | What to do |
|---|---|---|
| `400` | Policy is empty, > 65,536 chars, contains a `package` line, or does not compile | Re-check with `opa check` (Phase 3). Remove any `package` line. Fix the compile error the response reports. |
| `403` | Caller is not an org Owner or Admin | The regular API token used to create lacks permission. Ask the user for an owner/admin token, or have an admin run the create. |
| `409` | A policy token with that `name` already exists | Choose a different `name`, or list existing tokens (Phase 6) and revoke/reuse. |

## 4.4 Manual equivalent (for transparency)

If the user wants to see the raw call (do **not** paste a real token into the conversation):

```bash
POLICY_JSON=$(jq -Rs . < policy.rego)     # JSON-encode the rego file
curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/policyApiToken" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-policy-token (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  -d "{\"name\":\"deploy-agent\",\"description\":\"Deploys staging\",\"opa_policy\":${POLICY_JSON}}"
# The response .token is the secret — never print it; capture inline.
```

Carry the token `id` (non-secret) into Phase 6, and the token value (secret, in an env var) into Phase 5.
