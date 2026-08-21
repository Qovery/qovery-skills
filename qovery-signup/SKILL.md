---
name: qovery-signup
description: Takes a brand-new user from nothing to a working Qovery account and first organization — checks the Qovery CLI is installed (installs it if missing), signs them in with `qovery auth --headless` (which creates the account on first OAuth login), then creates an organization via the API and sets the CLI context. Relies entirely on the CLI's own credential store, never handling raw tokens. Use when someone has no Qovery account yet, wants to sign up, log in, or create a new Qovery organization from scratch — then hands off to qovery-onboard for cluster and environment setup.
license: MIT
compatibility: opencode
metadata:
  audience: new-users
  workflow: signup-and-org-creation
---

# Qovery Sign-up Skill

Gets a brand-new user fully onboarded to the point of having an account and an organization: verify (or install) the Qovery CLI → sign in with `qovery auth --headless` (first login **is** the sign-up) → create an organization → set the CLI context → hand off to **qovery-onboard** for clusters and environments.

The whole flow leans on the **Qovery CLI's own credential store** — after `qovery auth`, every call authenticates internally, so no raw tokens ever flow through the shell or this conversation.

## Usage Tracking

**EXECUTE THIS BASH COMMAND after the user is authenticated (Phase 2). Skip it before auth — there is no token yet.**

```bash
QOVERY_ORG_ID=$(qovery api organization 2>/dev/null | jq -r '.results[0].id' 2>/dev/null)
SKILL_NAME="qovery-signup"
[ -n "$QOVERY_ORG_ID" ] && curl -s -X POST "https://api.qovery.com/organization/${QOVERY_ORG_ID}/skill-tracking" \
  -H "Authorization: Bearer $(qovery auth token --print 2>/dev/null)" \
  -H "Content-Type: application/json" \
  -H "User-Agent: QoverySkill/qovery-signup (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  -d "{\"skill_name\":\"${SKILL_NAME}\"}" > /dev/null 2>&1 || true
```

> **API rule:** every `curl` to `api.qovery.com` MUST carry the `User-Agent` header above. Prefer the `qovery` CLI / `qovery api` over raw curl whenever possible — it authenticates internally.

## CRITICAL RULES

> **Authentication is the CLI's job — not yours.** Never ask for, print, store, or paste raw tokens. The user signs in once with `qovery auth --headless`; after that, `qovery api …` and every `qovery` command use the locally stored credentials. See [reference/auth.md](reference/auth.md).
>
> **`qovery auth --headless` is interactive and needs the user's browser.** It prints a URL the user must open and complete (GitHub / GitLab / Google / email). You cannot do the browser step for them. In Claude Code, have the user run `! qovery auth --headless` so the URL appears in-session; then wait for them to confirm they finished.
>
> **First login = sign-up.** A brand-new user does not "register" separately — the account is created automatically on the first successful OAuth login. There is no API to create an account.
>
> **Confirm the org name and plan before creating.** Organization creation is a real, billable-tier resource. Get explicit confirmation of both. Default individuals to `USER_2025`.
>
> **There is no `qovery organization` CLI command.** Manage organizations through `qovery api organization …` (which uses the CLI's auth) or the REST API — not a CLI noun.
>
> **Set expectations about billing.** A new organization has no credit card, so managed clusters and deployments are blocked (`billing_deployment_restriction: NO_CREDIT_CARD`) until one is added. A local demo cluster (`qovery demo up`) works with no card.

## When to Use This Skill

Trigger phrases:
- "I'm new to Qovery, help me sign up"
- "Create a Qovery account / log me in"
- "Set up the Qovery CLI and authenticate"
- "Create a new Qovery organization"
- "How do I get started with Qovery from scratch?"
- `/qovery-signup` (slash command)

For setting up clusters, projects, environments, RBAC, and cloud providers **after** an org exists, hand off to **qovery-onboard**. For deploying an app, use **qovery-deploy**.

## Workflow checklist

```
Sign up + create an organization:
- [ ] Phase 1 — CLI setup: detect OS, check `qovery` is installed (install if missing), verify version
- [ ] Phase 2 — Authenticate: run `qovery auth --headless` (first login creates the account); verify auth
- [ ] Phase 3 — Interview + create + enrich: ask name, website, use case, plan; create the org; enrich its profile (description, logo, icon) from the website; set context
- [ ] Phase 4 — Configure + hand off: optional first project for the use case, billing/demo-cluster note, invite team, hand a brief to qovery-onboard
```

## Authentication model (how auth is handled)

1. **Install** the CLI (Phase 1) — `brew install qovery-cli` (macOS), `scoop install qovery-cli` (Windows), or a release binary (Linux). `qovery upgrade` updates it.
2. **`qovery auth --headless`** (Phase 2) prints a URL. The user opens it, signs in / signs up via OAuth, and the CLI saves credentials locally. Interactive `qovery auth` (no flag) opens a browser automatically when the machine has one.
3. **Everything after that uses the stored credentials** — `qovery api …`, `qovery project …`, etc. — so you never touch a token. If a call returns `access token is invalid or expired. Sign in using 'qovery auth'…`, the session lapsed; re-run Phase 2.
4. **CI / non-interactive** only: the user may set `QOVERY_CLI_ACCESS_TOKEN` (or `Q_CLI_ACCESS_TOKEN`) in their environment instead of interactive login. Generate one with `qovery token`. Never print it.

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Auth | [reference/auth.md](reference/auth.md) | Token-secrecy rules; prefer CLI-internal auth; User-Agent header |
| Phase 1 | [reference/phase1-cli-setup.md](reference/phase1-cli-setup.md) | Detect OS, check/install the CLI per platform, verify version |
| Phase 2 | [reference/phase2-authenticate.md](reference/phase2-authenticate.md) | `qovery auth --headless` flow, account creation, verifying auth, token env vars |
| Phase 3 | [reference/phase3-create-organization.md](reference/phase3-create-organization.md) | Interview (name, website, use case, plan); create via `qovery api`; enrich profile (description/logo/icon) from the website; update via PUT; set context; billing restriction |
| Phase 4 | [reference/phase4-next-steps.md](reference/phase4-next-steps.md) | Configure for the use case (optional first project), add credit card / `qovery demo up`, invite teammates, hand a brief to qovery-onboard |

## Templates

| Template | Use |
|---|---|
| [templates/scripts/check-and-install-cli.sh](templates/scripts/check-and-install-cli.sh) | Detect whether the CLI is installed + its version; print the right install command per OS if missing |
| [templates/scripts/enrich-from-website.sh](templates/scripts/enrich-from-website.sh) | Derive candidate org profile (description, logo_url, icon_url) from a company website, with fallbacks |

## Quick reference

```bash
# 1. Install (macOS shown; see Phase 1 for Windows/Linux) and verify
brew install qovery-cli
qovery version

# 2. Sign up / log in (interactive — user completes the URL in a browser). In Claude Code:
#    ! qovery auth --headless
#    Verify it worked (should return JSON, not an auth error):
qovery api organization

# 3. (optional) Derive description/logo/icon from the company website, confirm with the user
bash templates/scripts/enrich-from-website.sh example.com

# 3b. Create an organization (uses the CLI's stored auth; no token handling)
qovery api organization --field name="My Org" --field plan=USER_2025
#    …or with the enriched profile via --input (see Phase 3.4)

# 4. Point the CLI at it, then hand off to qovery-onboard
qovery context set

# Optional: try Qovery locally with no credit card
qovery demo up
```

## Organization plans

Pass one of these as `plan` when creating (2025 plans are current; `FREE` / `PROFESSIONAL` / `BUSINESS` are deprecated):

| Plan | For |
|---|---|
| `USER_2025` | Individuals / getting started (default) |
| `TEAM_2025` | Small teams |
| `BUSINESS_2025` | Growing companies |
| `ENTERPRISE_2025` | Large orgs (SSO, advanced controls) |

> Always verify current plan names and pricing at <https://www.qovery.com/pricing> — plans change over time.

## Reference links

- **Create organization API**: <https://www.qovery.com/docs/api-reference/organization-main-calls/create-an-organization>
- **Qovery CLI**: <https://www.qovery.com/docs/cli/overview>
- **Qovery CLI (GitHub / install)**: <https://github.com/Qovery/qovery-cli>
- **Pricing & plans**: <https://www.qovery.com/pricing>
- **Qovery Console**: <https://console.qovery.com>
