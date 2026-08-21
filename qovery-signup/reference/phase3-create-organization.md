# Phase 3 — Interview, Create, and Enrich the Organization

An organization is the top-level container for everything in Qovery (projects, environments, clusters, members). Interview the user, create the org, and enrich its profile (description + logo + icon) from their website — then let Phase 4 configure Qovery for their use case.

## 3.1 Guided interview

Ask the user (one at a time, plain menus where it helps):

1. **Organization name** — what to call it (case-insensitive). Usually the company or team name.
2. **Website** — the company/product URL. Used to auto-fill the description, logo, and icon (§3.3) and stored as `website_url`. Optional but recommended; skip enrichment if they have none.
3. **Use case** — what they want to do with Qovery: e.g. "deploy a Node.js API + Postgres to AWS", "preview environments for PRs", "run internal tools", "migrate off Heroku". This drives how Phase 4 configures Qovery and what you hand to **qovery-onboard**.
4. **Plan** — see §3.2. Default individuals to `USER_2025`.

Confirm the name and plan before creating (org creation is a real, billable-tier resource).

## 3.2 Plans

Current plans are the **2025** tiers — `FREE`, `PROFESSIONAL`, and `BUSINESS` are deprecated:

| Plan value | For |
|---|---|
| `USER_2025` | Individuals / getting started (default) |
| `TEAM_2025` | Small teams |
| `BUSINESS_2025` | Growing companies |
| `ENTERPRISE_2025` | Large orgs (SSO, advanced controls) |

Verify current names/pricing at <https://www.qovery.com/pricing> if unsure.

## 3.3 Enrich from the website (description, logo, icon)

If the user gave a website, derive profile fields from it:

```bash
bash templates/scripts/enrich-from-website.sh <website-url>
```

It returns candidate `description`, `logo_url`, `icon_url` (plus a `candidates` list with alternatives — the site's own og:image/favicon **and** deterministic fallbacks `https://logo.clearbit.com/<domain>` for the logo and Google's favicon service for the icon). It decodes HTML entities so the URLs are valid.

**Show the candidates to the user and let them confirm or swap** (og:image is usually a wide social card; Clearbit is usually a cleaner square logo). If extraction found nothing useful, write a one-line description yourself from what you know about the company and confirm it. Never set a field the user hasn't seen.

## 3.4 Create the organization (with the enriched profile)

There is no `qovery organization` command; use `qovery api`, which reuses the stored credentials from Phase 2 — no token handling. Pass the whole profile via `--input` (handles descriptions with spaces/quotes cleanly):

```bash
NEW_ORG_ID=$(qovery api organization --input - <<JSON | jq -r '.id'
{
  "name": "My Org",
  "plan": "USER_2025",
  "website_url": "https://example.com",
  "description": "One-line company description",
  "logo_url": "https://logo.clearbit.com/example.com",
  "icon_url": "https://www.google.com/s2/favicons?domain=example.com&sz=128"
}
JSON
)
echo "Created organization: $NEW_ORG_ID"
```

For a bare org (no website), the short form is enough: `qovery api organization --field name="My Org" --field plan=USER_2025`.

Errors: `access token is invalid or expired…` → re-do Phase 2; `400` → check `plan` is a current value and `name` is present; `409` → the name is taken.

## 3.5 Update an existing org's profile (or fill it in later)

To enrich an org that already exists, `PUT` it. **`name` and `plan` are required on update** — echo the current values and add the new fields:

```bash
ORG_ID="<org-uuid>"
CUR=$(qovery api organization/$ORG_ID)
echo "$CUR" | jq '{name, plan} + {
  website_url: "https://example.com",
  description: "One-line company description",
  logo_url:   "https://logo.clearbit.com/example.com",
  icon_url:   "https://www.google.com/s2/favicons?domain=example.com&sz=128"
}' | qovery api organization/$ORG_ID --method PUT --input -
```

## 3.6 Point the CLI at the new organization

```bash
qovery context set
```

Select the new organization (and later a project/environment) so subsequent commands target it.

## 3.7 Billing restriction on brand-new orgs (set expectations)

A newly created org has **no credit card**, so it carries `billing_deployment_restriction: NO_CREDIT_CARD`: managed (cloud) cluster creation and deployments are blocked until a card is added (Console → **Settings → Billing**). A local demo cluster works without a card (Phase 4). Mention this now so it isn't a surprise.

Carry the **use case** from §3.1 into Phase 4.
