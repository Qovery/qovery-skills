# Qovery Authentication

## Security — Token Handling Rules

**CRITICAL: NEVER display, log, print, or capture Qovery token values.**

- NEVER run `qovery auth token --print` (or `qovery auth token --json`) as a standalone command — the output dumps the token into the conversation. `--json` emits the raw access token too, so always pipe it through `jq` to extract only the field you need. Use `--print` **inline** within curl commands so the token flows through the shell but is never visible:
  ```bash
  # CORRECT — token is inline, never shown:
  curl -s -H "Authorization: Bearer $(qovery auth token --print)" https://api.qovery.com/...
  # CORRECT — check auth without printing the token (jq extracts one field only):
  qovery auth token --json 2>/dev/null | jq -r '.token_type'

  # WRONG — token value would appear in output:
  qovery auth token --print
  qovery auth token --json            # dumps the full access_token
  echo $(qovery auth token --print)
  export TOKEN=$(qovery auth token --print)
  ```
- NEVER run `echo $QOVERY_API_TOKEN`, `echo $QOVERY_CLI_ACCESS_TOKEN`, or any command that prints token values to stdout
- NEVER include actual token values in responses to the user — use `***` or `(hidden)` if you need to reference them
- NEVER store tokens in shell variables via command substitution that the agent can read — always use them inline
- NEVER include real token values in generated code, scripts, or config files — use env var references like `$QOVERY_API_TOKEN`
- Prefer the `qovery` CLI directly (e.g., `qovery environment list`, `qovery log --service "name"`) over `curl` with tokens when possible — the CLI authenticates internally without exposing tokens
- Prefer `qovery api <path>` over `curl` for REST calls: it authenticates with the CLI's stored session, so no token ever reaches the shell (e.g. `qovery api organization`, `qovery api organization/<id>/project --field name=web`, `qovery api <path> --method DELETE`).
- Do NOT mint long-lived API tokens. There is no `qovery token create` command; `qovery token` is an interactive prompt meant for humans. Only the Terraform provider needs a long-lived token, and the user creates it themselves (see section 4).

## Qovery API Request Rules — User-Agent

**Every `curl` request to the Qovery API (`api.qovery.com`) MUST include a User-Agent header identifying the skill and version.**

Spell the header out in full on every request. Do **not** capture it into a shell
variable first: each agent shell invocation is its own process, so a variable set in one
command expands to nothing in the next, and the header silently goes out empty.

`__QOVERY_SKILLS_VERSION__` below is not a variable to expand. `install.sh` replaces it
with the installed version, and the manual installation in the README does the same, so
in an installed skill the literal you read is already the real version — send it as-is.
If you still see the placeholder itself, the skill is running straight from a repo
checkout or a symlinked development install; send it unchanged anyway rather than
inventing a version, and the server will record the call with no version at all.
Replace `<skill-name>` with the skill currently running.

```bash
-H "User-Agent: QoverySkill/<skill-name> (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
```

Full example:
```bash
curl -s \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/<skill-name> (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)" \
  https://api.qovery.com/organization
```

This applies to ALL curl commands targeting `api.qovery.com` — even when reference file examples don't explicitly show the User-Agent header. The agent MUST add it to every request it executes. Use the name of the skill currently running (e.g. `qovery-deploy`, `qovery-troubleshoot`).

---

## 1. CLI already authenticated (preferred)

```bash
# Check without printing anything secret:
qovery auth status --json 2>/dev/null | jq -e '.authenticated' >/dev/null && echo "CLI authenticated" || echo "CLI not authenticated"
```

If the CLI is authenticated, make REST calls with `qovery api`. It reads the stored session
(and refreshes it), so there is no token to handle at all:

```bash
qovery api organization                                              # GET
qovery api organization/<org-id>/project --field name="web"          # POST with a JSON body built from fields
echo '{"name":"web"}' | qovery api organization/<org-id>/project --input -
qovery api organization/<org-id>/project/<project-id> --method DELETE
qovery api spec -o /tmp/qovery-openapi.json                          # the OpenAPI spec, to look up paths
```

`qovery api` also expands `{organizationId}`, `{projectId}`, `{environmentId}` from the CLI
context when one is set. It sets the `Authorization` header itself, so never pass one; add the
skill `User-Agent` with `-H` like any other header.

Only when a tool really needs a raw `curl` call, pass the session inline so the value never
lands in a variable or in the output. `--authorization-header` prints the full header value
with the right scheme (`Bearer` for an OAuth session, `Token` for an API token):

```bash
curl -s -H "Authorization: $(qovery auth token --print --authorization-header)" https://api.qovery.com/organization
```

## 2. Existing API token in environment (CI, or a token the user already set)

```bash
# Check if a token is available (without printing it):
test -n "${QOVERY_API_TOKEN:-${QOVERY_CLI_ACCESS_TOKEN:-}}" && echo "Token found" || echo "No token"
```

If the user set `QOVERY_CLI_ACCESS_TOKEN`, every `qovery` command and `qovery api` call uses it
automatically. With `curl`, use it as `Authorization: Token $QOVERY_API_TOKEN`. The env var is
expanded by the shell at execution time, so the agent never sees the value.

## 3. Interactive login

If neither of the above works, ask the user to sign in. A browser OAuth login creates a short-lived,
auto-refreshed session instead of a long-lived credential:

```bash
qovery auth              # opens a browser on a desktop machine
qovery auth --headless   # prints a URL to open elsewhere; use this from an agent, SSH or a container
```

Both are interactive: the user completes the browser step. In Claude Code, have them run
`! qovery auth --headless` so the URL appears in the session, then fall back to section 1.

## 4. Long-lived API token (Terraform only)

The Terraform provider (`QOVERY_API_TOKEN`) is the one place a long-lived token is needed.
The user creates it, never the agent: Console > Organization Settings > API Tokens, or the
interactive `qovery token` command (it prompts for organization, name and role, and takes no
flags). Prefer a scoped API Policy Token (see the qovery-policy-token skill). The user puts it in
their own secret store or shell; the agent only references `$QOVERY_API_TOKEN`.
