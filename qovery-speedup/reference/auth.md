# Qovery Authentication

Qovery skills authenticate against the API using one of the following methods,
checked in this order:

## 1. Existing API token in environment

```bash
echo "${QOVERY_API_TOKEN:-${QOVERY_CLI_ACCESS_TOKEN:-}}"
```

If set, use it directly as `Authorization: Token $QOVERY_API_TOKEN`.

## 2. CLI already authenticated (`qovery auth token`)

```bash
qovery auth token --print 2>/dev/null
```

If the CLI is authenticated, `qovery auth token --print` outputs a valid access
token (automatically refreshed if expired). Use it directly:

```bash
curl -H "Authorization: Bearer $(qovery auth token --print)" https://api.qovery.com/organization
```

Or generate a named API token for longer-running scripts:

```bash
qovery token create --name "skill-$(date +%Y%m%d-%H%M%S)" --duration 24h
```

The `qovery token create` command prints the token — capture it into `QOVERY_API_TOKEN`.

## 3. Interactive login

If neither of the above works, prompt the user:

```bash
qovery auth                      # interactive browser login
# OR for headless:
export QOVERY_CLI_ACCESS_TOKEN=qov_xxx
```

After login, fall through to step 2 to obtain a token.
