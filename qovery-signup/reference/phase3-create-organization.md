# Phase 3 — Create the Organization

An organization is the top-level container for everything in Qovery (projects, environments, clusters, members). Create one only after the user confirms the **name** and **plan**.

## 3.1 Choose a name and plan

Ask the user for an organization name (case-insensitive) and which plan to start on. The current plans are the **2025** tiers — `FREE`, `PROFESSIONAL`, and `BUSINESS` are deprecated:

| Plan value | For |
|---|---|
| `USER_2025` | Individuals / getting started (default) |
| `TEAM_2025` | Small teams |
| `BUSINESS_2025` | Growing companies |
| `ENTERPRISE_2025` | Large orgs (SSO, advanced controls) |

Confirm both before creating — verify current names/pricing at <https://www.qovery.com/pricing> if unsure.

## 3.2 Create it (via the CLI's authenticated API access)

There is no `qovery organization` command; use `qovery api`, which reuses the stored credentials from Phase 2 — no token handling:

```bash
qovery api organization --field name="My Org" --field plan=USER_2025
```

The response is the new `Organization` object — capture its `id`:

```bash
NEW_ORG_ID=$(qovery api organization --field name="My Org" --field plan=USER_2025 | jq -r '.id')
echo "Created organization: $NEW_ORG_ID"
```

Optional fields (repeat `--field`): `description`, `website_url`, `admin_emails` (invite teammates at creation).

**Equivalent raw API** (only if not using the CLI — needs an owner token and the standard headers from [auth.md](auth.md)):

```bash
qovery api organization --input - <<'JSON'
{ "name": "My Org", "plan": "USER_2025" }
JSON
```

Errors:
- `access token is invalid or expired…` → not authenticated; go back to Phase 2.
- `400` → check the `plan` value is one of the current plans above and `name` is present.

## 3.3 Point the CLI at the new organization

```bash
qovery context set
```

Follow the prompts to select the new organization (and later a project/environment). This sets the default context so subsequent commands target the right org.

## 3.4 Billing restriction on brand-new orgs (set expectations)

A newly created organization has **no credit card**, so it carries `billing_deployment_restriction: NO_CREDIT_CARD`: managed (cloud) cluster creation and deployments are blocked until a card is added in the Console (**Settings → Billing**). A local **demo cluster works without a card** (see Phase 4). Tell the user this now so the restriction later isn't a surprise.

Continue to Phase 4 for next steps and the hand-off to qovery-onboard.
