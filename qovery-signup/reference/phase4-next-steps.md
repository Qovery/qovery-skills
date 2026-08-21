# Phase 4 — Next Steps and Hand-off

The user now has an account and an organization. Close the loop: confirm it, unblock deployments, and route them to the right next skill.

## 4.1 Confirm the organization exists

```bash
qovery api organization | jq -r '.results[] | "\(.name) — \(.id)"'
```

The new org should appear. If the user set the context in Phase 3, subsequent `qovery` commands target it by default.

## 4.2 Unblock real deployments (add a credit card) — or use the demo cluster

A brand-new org is under `NO_CREDIT_CARD` restriction: **managed clusters and cloud deployments are blocked** until a card is added.

- **To deploy on real cloud infrastructure**: add a card in the Console → **Settings → Billing** (`qovery console` opens the Console in a browser). This lifts the restriction.
- **To try Qovery with no card**: spin up a local demo cluster (k3s + Qovery on the user's machine):

  ```bash
  qovery demo up        # create the local demo cluster
  qovery demo destroy   # tear it down when done
  ```

Recommend the demo path for someone just exploring, and the credit-card path when they're ready to deploy to their own cloud.

## 4.3 Invite teammates (optional)

Add members when creating the org (`--field admin_emails=…`) or later in the Console under **Settings → Members**. Enterprise plans support SSO / enterprise connections (`qovery enterprise-connection`).

## 4.4 Generate an API token for automation (optional)

For CI/CD or scripts, create a token and store it securely (never printed):

```bash
qovery token
```

Save it in the user's secret manager as `QOVERY_API_TOKEN` (or `QOVERY_CLI_ACCESS_TOKEN` for the CLI). See [auth.md](auth.md) for handling rules.

## 4.5 Hand off to qovery-onboard

Sign-up is done — the heavier setup lives in the **qovery-onboard** skill. Route the user there to:
- pick a cloud provider and create a cluster (managed or BYOK),
- structure projects and environments,
- set security, cost, and RBAC defaults,
- migrate from another platform if needed.

If instead they just want to ship an app immediately, point them at **qovery-deploy**.

Summary to give the user:
- ✅ CLI installed and authenticated (credentials stored locally by the CLI)
- ✅ Organization `<name>` created (id `<uuid>`)
- ▶️ Next: add a credit card **or** `qovery demo up`, then run **qovery-onboard** to create a cluster and environments
