# Qovery Authentication

## Security — Token Handling Rules

**CRITICAL: NEVER display, log, print, or capture Qovery token values.**

- NEVER run `qovery auth token --print` as a standalone command — the output would expose the token in the conversation. Always use it **inline** within curl commands so the token flows through the shell but is never visible:
  ```bash
  # CORRECT — token is inline, never shown:
  curl -s -H "Authorization: Bearer $(qovery auth token --print)" https://api.qovery.com/...

  # WRONG — token value would appear in output:
  qovery auth token --print
  echo $(qovery auth token --print)
  export TOKEN=$(qovery auth token --print)
  ```
- NEVER run `echo $QOVERY_API_TOKEN`, `echo $QOVERY_CLI_ACCESS_TOKEN`, or any command that prints token values to stdout
- NEVER include actual token values in responses to the user — use `***` or `(hidden)` if you need to reference them
- NEVER store tokens in shell variables via command substitution that the agent can read — always use them inline
- NEVER include real token values in generated code, scripts, or config files — use env var references like `$QOVERY_API_TOKEN`
- Prefer the `qovery` CLI directly (e.g., `qovery environment list`, `qovery log --service "name"`) over `curl` with tokens when possible — the CLI authenticates internally without exposing tokens
- When running `qovery token create`, the command outputs the new token. Do NOT display it. Pipe it directly into a secure storage or env var file that is NOT read by the agent.

## Qovery API Request Rules — User-Agent

**Every `curl` request to the Qovery API (`api.qovery.com`) MUST include a User-Agent header identifying the skill and version.**

The version is read from `_version.txt` (written at install time by `install.sh`). When executing curl commands, the agent MUST add this header:

```bash
# Read the version (do this once per session):
QOVERY_SKILLS_VERSION=$(cat _version.txt 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Add to every curl command:
-H "User-Agent: QoverySkill/auth (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)"
```

Full example:
```bash
curl -s \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/auth (version:$QOVERY_SKILLS_VERSION; https://github.com/Qovery/qovery-skills)" \
  https://api.qovery.com/organization
```

This applies to ALL curl commands targeting `api.qovery.com` — even when reference file examples don't explicitly show the User-Agent header. The agent MUST add it to every request it executes. Use `auth` as the context for the shared auth flow. When executing curl commands from a specific skill's reference files, use that skill's name instead (e.g., `qovery-deploy`, `qovery-troubleshoot`).

---

## 1. Existing API token in environment

```bash
# Check if a token is available (without printing it):
test -n "${QOVERY_API_TOKEN:-${QOVERY_CLI_ACCESS_TOKEN:-}}" && echo "Token found" || echo "No token"
```

If a token is found, use it directly in curl commands as `Authorization: Token $QOVERY_API_TOKEN`. The env var is expanded by the shell at execution time — the agent never sees the actual value.

## 2. CLI already authenticated (`qovery auth token`)

```bash
# Check if the CLI is authenticated (without printing the token):
qovery auth token --json 2>/dev/null | jq -r '.type' && echo "CLI authenticated" || echo "CLI not authenticated"
```

If the CLI is authenticated, use `qovery auth token --print` **inline** within curl commands:

```bash
# Token flows through the shell but is never visible to the agent:
curl -s -H "Authorization: Bearer $(qovery auth token --print)" https://api.qovery.com/organization
```

Or generate a named API token for longer-running scripts. The token must be stored securely — do NOT display the output:

```bash
# Create the token and store it directly in .env (not displayed):
qovery token create --name "skill-$(date +%Y%m%d-%H%M%S)" --duration 24h > .qovery-token.tmp
# The user should manually export it or add it to their secure env config
echo "API token created. Add QOVERY_API_TOKEN to your environment from .qovery-token.tmp"
```

## 3. Interactive login

If neither of the above works, prompt the user:

```bash
qovery auth                      # interactive browser login
# OR for headless:
# The user sets QOVERY_CLI_ACCESS_TOKEN in their environment (not via the agent)
```

After login, fall through to step 2 to obtain a token.
