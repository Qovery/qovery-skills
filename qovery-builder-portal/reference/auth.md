# Qovery Authentication

Qovery skills authenticate against the API using one of the following methods,
checked in this order:

## 1. Existing API token in environment

```bash
echo "${QOVERY_API_TOKEN:-${QOVERY_CLI_ACCESS_TOKEN:-}}"
```

If set, use it directly as `Authorization: Token $QOVERY_API_TOKEN`.

## 2. CLI context (already logged in)

```bash
test -f ~/.qovery/context.json && qovery context
```

If the CLI is authenticated, generate a named API token for scripts:

```bash
qovery token create --name "skill-$(date +%Y%m%d-%H%M%S)" --duration 24h
```

The command prints the token — capture it into `QOVERY_API_TOKEN`.

## 3. Interactive login

If neither of the above works, prompt the user:

```bash
qovery auth                      # interactive browser login
# OR for headless:
export QOVERY_CLI_ACCESS_TOKEN=qov_xxx
```

After login, fall through to step 2 to obtain an API token.

## 4. JWT fallback

If the user cannot create an API token (limited role), extract the JWT from
the CLI context as a last resort:

```bash
JWT=$(jq -r '.access_token' ~/.qovery/context.json)
curl -H "Authorization: Bearer $JWT" https://api.qovery.com/organization
```

JWTs expire quickly — prefer API tokens for any non-trivial workflow.
