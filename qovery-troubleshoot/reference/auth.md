# Qovery Authentication

## Security — Token Handling Rules

**CRITICAL: NEVER display, log, print, or capture Qovery token values.**

- NEVER run `echo $QOVERY_API_TOKEN`, `echo $QOVERY_CLI_ACCESS_TOKEN`, or any command that prints token values to stdout
- NEVER include actual token values in responses to the user — use `***` or `(hidden)` if you need to reference them
- NEVER store tokens in shell variables via command substitution that the agent can read — always use them inline
- NEVER include real token values in generated code, scripts, or config files — use env var references like `$QOVERY_API_TOKEN`
- Prefer the `qovery` CLI (e.g., `qovery api`, `qovery environment list`, `qovery log --service "name"`) over `curl` with tokens — the CLI authenticates internally without exposing tokens
- When a long-lived token must be created, do NOT display the output. Pipe it directly into secure storage that the agent does not read.

Skills authenticate using one of four tiers, checked in order. Stop at the first one that works.

## Tier 1 — `qovery api` (preferred)

If the `qovery` CLI is installed and authenticated, use it directly for every API call. No token needs to be extracted, printed, or stored:

```bash
qovery api /organization                           # confirms auth + lists orgs
qovery api /environment/{envId}/status
qovery api /organization/{orgId}/cluster
```

Detect availability without revealing any secret:

```bash
qovery api /organization >/dev/null 2>&1 && echo "qovery api OK" || echo "qovery api unavailable"
```

If this tier works, **use it for all API calls in the skill**. Skip the rest.

## Tier 2 — Token in environment

If `qovery api` is unavailable but a token is already exported in the shell, use it directly with `curl`. The env var is expanded by the shell at execution time, so the agent never sees the value:

```bash
[[ -n "${QOVERY_API_TOKEN:-${QOVERY_CLI_ACCESS_TOKEN:-}}" ]] && echo SET || echo "NOT SET"
```

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" https://api.qovery.com/organization
```

## Tier 3 — JWT fallback (restricted-role users)

Some users (read-only, viewer, member roles) cannot create API tokens but are still authenticated through `qovery auth`. The CLI stores a short-lived JWT in `~/.qovery/context.json`. Use it inline so the value is not echoed:

```bash
[[ -s ~/.qovery/context.json ]] && echo "JWT available" || echo "no JWT"
```

```bash
curl -s -H "Authorization: Bearer $(jq -r '.access_token' ~/.qovery/context.json)" \
  https://api.qovery.com/organization
```

JWTs expire quickly. Prefer Tier 1 for any non-trivial workflow — only use Tier 3 when the user lacks permission to create a token.

## Tier 4 — Not authenticated

If none of the above works, prompt the user to log in:

```bash
qovery auth                        # interactive browser login
# OR for headless environments, the user sets:
#   export QOVERY_CLI_ACCESS_TOKEN=qov_xxx
```

After login, fall through to Tier 1.
