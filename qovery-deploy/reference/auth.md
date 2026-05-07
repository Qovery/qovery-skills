# Qovery Authentication

## Security — Token Handling Rules

**CRITICAL: NEVER display, log, print, or capture Qovery token values.**

- NEVER run `echo $QOVERY_API_TOKEN`, `echo $QOVERY_CLI_ACCESS_TOKEN`, or any command that prints token values to stdout
- NEVER include actual token values in responses to the user — use `***` or `(hidden)` if you need to reference them
- NEVER store tokens in shell variables via command substitution that the agent can read — always use them inline
- NEVER include real token values in generated code, scripts, or config files — use env var references like `$QOVERY_API_TOKEN`
- NEVER run `qovery token create` yourself — the command prints the new token to stdout. Ask the user to run it themselves and export the result. See "Not authenticated" below.
- Prefer the `qovery` CLI (e.g., `qovery api`, `qovery environment list`, `qovery log --service "name"`) over `curl` with tokens — the CLI authenticates internally without exposing tokens

Skills authenticate using one of two tiers, checked in order. Stop at the first one that works.

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

## Not authenticated — ask the user

If neither tier works, do **not** generate a token from inside the agent. Instead, instruct the user to run one of these themselves so the secret never enters the agent's command stream:

**Option A — interactive login (recommended).** Falls back to Tier 1:

```bash
qovery auth        # opens a browser; the agent never sees the credential
```

After login, retry Tier 1.

**Option B — long-lived API token.** The user runs this in their own shell and exports the result. The agent does not run `qovery token create` and does not read the output:

```bash
# User runs this manually, NOT the agent:
qovery token create --name "skill-$(date +%Y%m%d)" --duration 24h
# Then the user copies the printed token into a secure store and exports it:
export QOVERY_API_TOKEN=qov_xxx
```

After the user exports the token in the shell that runs the skill, retry Tier 2.
