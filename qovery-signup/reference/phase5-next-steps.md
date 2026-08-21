# Phase 5 — Next Steps and Hand-off

The user now has an account and an organization. Close the loop: confirm it, unblock deployments, and route them to the right next skill.

## 5.1 Confirm the organization exists

```bash
qovery api organization | jq -r '.results[] | "\(.name) — \(.id)"'
```

The new org should appear. If the user set the context in Phase 3, subsequent `qovery` commands target it by default.

## 5.2 Unblock real deployments (add a credit card) — or use the demo cluster

A brand-new org is under `NO_CREDIT_CARD` restriction: **managed clusters and cloud deployments are blocked** until a card is added.

- **To deploy on real cloud infrastructure**: add a card in the Console → **Settings → Billing** (`qovery console` opens the Console in a browser). This lifts the restriction.
- **To try Qovery with no card**: spin up a local demo cluster (k3s + Qovery on the user's machine):

  ```bash
  qovery demo up        # create the local demo cluster
  qovery demo destroy   # tear it down when done
  ```

Recommend the demo path for someone just exploring, and the credit-card path when they're ready to deploy to their own cloud.

## 5.3 Invite teammates (optional)

Add members when creating the org (`--field admin_emails=…`) or later in the Console under **Settings → Members**. Enterprise plans support SSO / enterprise connections (`qovery enterprise-connection`).

## 5.4 Generate an API token for automation (optional)

For CI/CD or scripts, create a token and store it securely (never printed):

```bash
qovery token
```

Save it in the user's secret manager as `QOVERY_API_TOKEN` (or `QOVERY_CLI_ACCESS_TOKEN` for the CLI). See [auth.md](auth.md) for handling rules.

## 5.5 Configure for the use case (optional, no billing needed)

Use the **use case** captured in Phase 3.1 to start shaping Qovery. Creating a **project** is free and needs no cluster or credit card — it's a good first structural step that matches the user's intent:

```bash
qovery api organization/$NEW_ORG_ID/project --field name="<use-case project, e.g. Backend API>" \
  --field description="<from the use case>"
```

Name the project after what they're building (e.g. "Backend API", "PR Previews", "Internal Tools"). Deeper configuration — clusters, environments, deployment pipelines — is billing/cluster-gated and belongs to qovery-onboard (§5.6); don't attempt cluster or environment creation here.

## 5.6 Hand off to qovery-onboard (with a brief)

Sign-up is done — the heavier setup lives in the **qovery-onboard** skill. Hand it the context you gathered so it doesn't re-ask:

- **Organization**: `<name>` (`<uuid>`), plan `<plan>`
- **Use case**: `<the use case from Phase 3.1>`
- **Website / domain**: `<website_url>`
- **Billing**: card added? (yes → managed clusters available; no → demo cluster only)

qovery-onboard will then pick a cloud provider and create a cluster (managed or BYOK), structure projects/environments, and set security/cost/RBAC defaults. If instead they just want to ship an app immediately, point them at **qovery-deploy**.

Summary to give the user:
- ✅ CLI installed and authenticated (credentials stored locally by the CLI)
- ✅ Organization `<name>` created (id `<uuid>`) — profile enriched from `<website>` (description, logo, icon)
- ✅ First project `<name>` created for the use case (if applicable)
- ▶️ Next: add a credit card **or** `qovery demo up`, then run **qovery-onboard** (with the brief above) to create a cluster and environments
