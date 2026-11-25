# Environment variables and secrets

Covers scopes and overrides, built-in variables, aliases, interpolation, secrets, build-time variables and references across environments. Variable mistakes are behind a large share of "my app cannot connect" and "the value is wrong" questions.

## Contents

- How Qovery resolves a variable
- "My service does not see the variable" or "the value is wrong"
- Aliases: create, re-point, swap
- Interpolation with `{{VAR}}`
- Referencing a service in another environment
- Secrets
- Variables during the Docker build
- Config files
- External secret managers
- Known limits

## How Qovery resolves a variable

- **Scopes.** Project, environment and service. A narrower scope overrides a broader one: service beats environment, environment beats project.
- **Built-in variables.** Qovery injects read-only variables for each service and database of the environment (internal host, port, credentials, connection URLs) and for outputs of lifecycle jobs, Terraform services and blueprints. Their names embed the service identifier, so copy them from the **Variables** list instead of typing them.
- **Changes apply on the next deployment.** Creating, editing, renaming or deleting a variable does not change running pods. Redeploy the service.

Docs: <https://www.qovery.com/docs/configuration/environment-variables>.

## "My service does not see the variable" or "the value is wrong"

**How to check.**
```bash
qovery application env list      # also: qovery container env list, qovery cronjob env list, qovery lifecycle env list
qovery environment env list
```

Go through these causes in order:
1. **Not redeployed** since the variable changed.
2. **Overridden** at a narrower scope: the same name exists on the service and on the environment, and the service value wins.
3. **Alias pointing at the wrong target**, or a target that was deleted (for example after replacing a database).
4. **Wrong endpoint**: `..._HOST` and `..._DATABASE_URL` are external endpoints that only resolve when the database is public; services in the cluster need `..._HOST_INTERNAL` and `..._DATABASE_URL_INTERNAL`.
5. **Name typo** in the app or in an interpolated value.
6. **Different environment**: built-in variables of one environment are not injected into another (see below).

If the Console shows one value and the running app sees another after a redeploy, collect the variable name, its scope and the service, and escalate.

## Aliases: create, re-point, swap

An alias exposes an existing variable under another name, for example `DATABASE_URL` pointing at the database's built-in `..._DATABASE_URL_INTERNAL`. Create it from the target: **Variables**, find the target, **Create alias**, enter the name the app expects.

Rules worth knowing:
- An alias inherits the target's type: an alias on a secret is a secret.
- An alias cannot target another alias, an external secret, or a variable at a narrower scope.
- Two variables cannot share a name in the same scope (`409 Variable already exists`).

**Re-point an alias** (for example when moving from one database to another). The Console target field is read-only. Use the API, which keeps the alias name and ID; `value` is the **name** of the new target variable:

```bash
qovery api "variable/<ALIAS_ID>" --method PUT --input - <<'JSON'
{ "key": "REDIS_URL", "value": "QOVERY_..._NEW_TARGET_NAME" }
JSON
```

This only works on a variable that is already an alias. Sent to a plain variable, it stores the target name as a literal string.

**Without the API**, swap by renaming, in this order: create an alias on the new target under a temporary name (`REDIS_URL_NEW`); rename the old one (`REDIS_URL` to `REDIS_URL_LEGACY`); rename the new one to `REDIS_URL`; redeploy; delete the legacy one once confirmed.

Do not delete an alias and recreate it, and do not replace it with a plain variable holding the copied value: in between, a deployment starts without the variable, and a copied secret ends up as plain text that no longer follows the database.

Docs: <https://www.qovery.com/docs/configuration/environment-variables#aliases>.

## Interpolation with `{{VAR}}`

A value can reference other variables: `DATABASE_URL=postgresql://{{DB_USER}}:{{DB_PASSWORD}}@{{DB_HOST}}:5432/app`. Interpolation is resolved for the service that consumes the variable, with the variables that service can see. A reference to a variable the service cannot see stays unresolved.

## Referencing a service in another environment

Built-in variables and aliases do not cross environments. To call a service or database in another environment, set a plain variable to its full internal DNS name (`<service-host>.<namespace>.svc.cluster.local`, where the host is the target's `..._HOST_INTERNAL` value and the namespace is the target environment's namespace), and update it if that environment is recreated or cloned. Both environments must be on the same cluster for internal DNS to resolve.

## Secrets

- Secret values are encrypted, cannot be read back in the Console or API, and are masked in deployment logs. You can only update or delete them.
- Mark tokens, passwords, keys and connection strings as secrets. A plain variable holding a credential is visible to anyone who can read the environment.
- Who can see or edit variables depends on the user's role; see `reference/billing-access.md`.

## Variables during the Docker build

A variable reaches the build only if the Dockerfile declares it:

| Dockerfile | Passed as | Ends up |
|---|---|---|
| `ARG NAME` | build argument | In the image configuration and build cache, visible to anyone who can pull the image |
| `RUN --mount=type=secret,id=NAME` | BuildKit secret | Mounted as a file for that one step only |

- Marking a variable as a secret in Qovery does **not** change this. A secret whose name matches an `ARG` is still baked into the image metadata. To keep it out, use a secret mount.
- `id=` is required on secret mounts; Qovery rejects a mount without it. Add `required=true` to fail early when the variable is missing.
- Changing the value of a declared build variable triggers a rebuild. Rotating a build secret does not re-run a cached step; turn on **Disable BuildKit cache** in the service Build settings if that step must run again.

Docs: <https://www.qovery.com/docs/configuration/environment-variables#build-time-variables>.

## Config files

To ship a whole file (a JSON config, a certificate, an `.npmrc`), use a **file** variable: its value is written to the path you choose in the container. Docs: <https://www.qovery.com/docs/configuration/environment-variables#variable-as-file>.

## External secret managers

Qovery can read secrets from AWS Secrets Manager, AWS Parameter Store and GCP Secret Manager (through the cluster secret manager integration). Aliases cannot target an external secret. Docs: <https://www.qovery.com/docs/configuration/environment-variables#external-secrets>.

## Known limits

- Variable changes need a redeploy.
- No variable sharing across environments; use plain values with the full DNS name.
- A variable's type (plain, secret, alias, file) cannot be changed after creation; delete and recreate it under the same name, with no deployment in between.
