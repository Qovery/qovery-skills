# Databases

Covers choosing a database type, connecting to it, backups and restores, version and instance changes, and the common breakages around connection variables. Databases are one of the most frequent support topics.

## Contents

- Which kind of database should I use?
- My app cannot connect to the database
- Connect from a laptop or a SQL client
- Backups, snapshots and restores
- Upgrading versions and instance sizes
- Swapping a database service (for example Redis to Valkey)
- Database creation fails or the name is "already taken"
- Deleting a database, environment or cluster that holds databases
- Running migrations
- Known limits

## Which kind of database should I use?

| | Managed database (Blueprint) | Container database |
|---|---|---|
| Use for | Production | Development, testing, previews |
| Runs as | A cloud managed service in the cluster's cloud account (for example Amazon RDS, ElastiCache), a Helm chart, or a SaaS, depending on the blueprint | One container with a persistent volume on the Kubernetes cluster |
| Backups | Provided by the cloud service | **None.** No automated backups or snapshots |
| Created with | **New service > Databases & Caches** blueprint (for example **Amazon RDS for PostgreSQL**) | **Database** service |

Answer "is a container database OK for production?" with no: it is a single instance with no automated backups. Existing databases created in the older **Managed** mode keep working; new managed databases are created from a Blueprint. Eligible AWS PostgreSQL managed databases can be migrated to a blueprint without moving data.

An existing database that Qovery does not manage (for example in another VPC or a SaaS) is also fine: reach it over VPC peering (see `reference/networking-domains.md`) and pass its URL as a secret variable.

Docs: <https://www.qovery.com/docs/configuration/database>, <https://www.qovery.com/docs/configuration/blueprints>.

## My app cannot connect to the database

**Symptom.** `connection refused`, `ECONNREFUSED`, `could not translate host name`, timeouts, `password authentication failed`.

**Likely causes.**
- The app uses the external hostname or URL of a private database, or a hostname copied from another environment.
- The variable the app reads (`DATABASE_URL`) is not set, is a plain copy of an old value, or is an alias pointing at the wrong database.
- The database is still deploying, or failed to deploy.
- For managed or external databases: security groups or the network path (peering) do not allow the cluster.

**How to check.**
1. Database status: `qovery database list` or the environment view; it must be deployed.
2. Variables: Qovery injects built-in variables for each database, including an internal host and an internal connection URL (names follow `QOVERY_<TYPE>_<ID>_HOST_INTERNAL` and `..._DATABASE_URL_INTERNAL`). Check that the app's variable is an **alias** to the internal one (`qovery application env list`).
3. From inside the cluster, test the connection with `qovery shell` into the app and a client tool, or `qovery port-forward`.

**Fix.** Create an alias with the name the app expects (for example `DATABASE_URL`) pointing to the database's `..._DATABASE_URL_INTERNAL` built-in variable, then redeploy the app. For managed databases, open the security group to the cluster. See `reference/secrets-env.md` for aliases.

## Connect from a laptop or a SQL client

**Answer.** Use `qovery port-forward`, which tunnels a local port to a pod in the cluster without making the database public:

```bash
qovery port-forward "<Console URL of the database>" --port 5432:5432
# or: qovery port-forward --pod "<database pod name>" --port 5432:5432
```

Without a URL or `--pod`, the command targets the service in the CLI context and asks the user to confirm or pick one, so an agent should pass the URL. Then connect a client to `localhost:5432` with the credentials from the database's built-in variables (shown in the Console). The user needs the **Port-forward** permission on that environment type.

Port-forward reaches pods in the cluster. A managed database that runs outside the cluster (for example Amazon RDS) is not a pod: run the client from inside the cluster with `qovery shell` into an application pod, or use the access path you already have to that VPC (bastion, AWS Systems Manager, VPN).

**Unstable tunnels.** Port-forward opens one tunnel per TCP connection. A client or AI agent that opens a new connection per query, or a server-side idle timeout (for example PostgreSQL `idle_session_timeout`), looks like the tunnel flapping. Port-forward is meant for debugging and admin work, not for production traffic or high-churn automated clients: use a connection pool, or run the workload inside the cluster.

Switching a database to **Public** accessibility also works but exposes it to the internet; prefer port-forward.

Docs: <https://www.qovery.com/docs/cli/commands/port-forward>.

## Backups, snapshots and restores

- Container databases have no automated backups. Take dumps yourself (for example a cron job running `pg_dump` to object storage), or move production data to a managed database.
- Managed databases rely on the cloud provider's backups. Backup window, retention and point-in-time restore are configured through the blueprint inputs or on the provider side; check the blueprint's README.
- Point-in-time restore on RDS: restore a temporary copy, copy the data back or point the app to a new blueprint service. Guide: <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/restoring-rds-point-in-time>.
- `SnapshotQuotaExceeded` when deleting a managed database: Qovery takes a final snapshot before deletion. Delete old snapshots in the cloud console or ask the provider for a higher quota, then retry. Snapshots and automated backups of legacy managed databases are not deleted by Qovery.

## Upgrading versions and instance sizes

- Change version, instance type or disk size from Qovery, never directly in the cloud console: direct changes drift from Qovery's configuration and can be reverted.
- Cloud providers apply some changes (for example major engine upgrades on RDS) in the next maintenance window rather than immediately. Apply the change in Qovery first, then force it from the provider console if needed.
- For a major PostgreSQL upgrade with minimal downtime on RDS, the documented path is an RDS Blue/Green deployment, then aligning the configuration on Qovery: <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/upgrading-rds-instance>.

## Swapping a database service (for example Redis to Valkey)

**Symptom.** After replacing one database service with another, the app reads an empty or stale `REDIS_URL` and fails.

**Cause.** The app's variable was an alias to the old database's built-in variable. Deleting the old database removed the alias target, and re-creating the variable by hand as plain text loses the link (and stores a secret as a plain value).

**Fix.** Before deleting the old database, re-point the alias to the new database's built-in URL variable (API call, or the rename swap in the Console), then redeploy the app, then delete the old database. If the variable was already turned into a plain value, delete it and create the alias under the same name with no deployment in between. Steps in `reference/secrets-env.md` (section "Aliases").

## Database creation fails or the name is "already taken"

- A failed creation can leave a partial resource. Check the cloud console for a half-created instance before retrying, so you do not end up with two.
- If a retry with the same name is refused, wait a few minutes and retry; if it persists, escalate with the service name and the time of the first failure.
- Managed database deployment failures on the database stage with no clear error in the logs are worth escalating with the deployment ID.

## Deleting a database, environment or cluster that holds databases

- Delete environments (and their blueprint databases) **before** deleting the cluster. Blueprint resources live in the cloud account; if the cluster is deleted first, those resources stay behind and keep billing, and must be removed by hand in the cloud console.
- Cluster deletion errors about a VPC, subnet or private network that is not empty usually mean such a leftover resource. See `reference/aws-eks.md`.

## Running migrations

Run schema migrations as a **lifecycle job** triggered on deploy and placed in a deployment stage before the app, not in the app's start command. Migrations at startup delay readiness and make health checks fail. Docs: <https://www.qovery.com/docs/configuration/lifecycle-job>.

## Known limits

- Container databases: single instance, no automated backups. Not for production.
- Built-in database variables are only injected into services of the same environment.
- Port-forward is for interactive use, not for applications or high-churn clients.
