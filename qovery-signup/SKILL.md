---
name: qovery-signup
description: Takes a brand-new user from nothing to a working Qovery account and first organization — checks the Qovery CLI is installed (installs it if missing), signs them in with `qovery auth --headless` (which creates the account on first OAuth login), then creates an organization via the API, enriches it from the company website, records the sign-up for tracking and lead qualification (tagged as a CLI/agent sign-up), and sets the CLI context. Relies entirely on the CLI's own credential store, never handling raw tokens. Use when someone has no Qovery account yet, wants to sign up, log in, or create a new Qovery organization from scratch — then hands off to qovery-onboard for cluster and environment setup.
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

At each new launch, start one anonymous run before authentication or other work,
even when the user is already signed in:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-signup
```

Retain the returned absolute **state-file path** in the journey context across
shell calls, steps and resumptions. The file holds the run/anonymous UUIDs,
original timestamp and private correlation proof; never read it into the prompt,
print its contents, or retain tokens, AI responses or CLI cache contents.
The helper requires macOS, Linux or WSL with Bash and curl. The installer supplies a verified native Rust binary;
neither Rust nor Python needs to be installed. Native Windows is unsupported.
No path is returned for opt-out, development installs, an unavailable tracking binary or an
unsupported skill: continue normally. The root router `qovery` is excluded by the
backend name contract; downstream `qovery-*` skills track their own executions.

For a retry or resumed journey, use `resume STATE_PATH` to retry the anonymous
start only, never `start` again. To retry association, call `associate` again with
the retained state path and the explicitly selected organization UUID.
After login and **explicit organization selection/creation**, run:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' associate 'STATE_PATH' --organization 'ORGANIZATION_UUID'
```

Replace those placeholders with the retained path and selected UUID. Already
signed-in users follow the same start → associate order. Do not guess the first
organization returned by an API. The helper obtains a Bearer session internally;
API/policy/machine tokens cannot associate a run with a person. Association means
identity and organization are known, not that deployment succeeded.
One run has one immutable account/organization association. On an account or
organization change, end the old journey and start a **new execution**; never
reattach the old run or change IDs to bypass a conflict.

Requests run in the background with bounded deadlines. Network failures remain
queued with backoff; `resume` retries anonymous starts, while `associate` also
rechecks the current account and selected organization before retrying association.
Keep the path on interruption. At journey completion, use `cleanup STATE_PATH`
only after queued requests are no longer needed; explicit cleanup discards pending
requests too. State is private, limited to 100 runs and pruned after 30 days on
subsequent launches. Set `QOVERY_SKILLS_NO_TRACKING=1` before any command to prevent
helper state creation and sends, including pending retries. It does not remove
User-Agent headers from other API calls or disable server audit logs.
`cleanup` still removes state.
`QOVERY_SKILLS_TRACKING_DEBUG=1` prints safe statuses without request data or secrets.
Never call the legacy tracking endpoint as a fallback.

> **API rule:** send this exact `User-Agent` header on **every** `curl` call to `api.qovery.com`, spelled out in full each time — a shell variable set in one command is gone by the next one:
>
> ```
> -H "User-Agent: QoverySkill/qovery-signup (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
> ```

## CRITICAL RULES

> **Authentication is the CLI's job — not yours.** Never ask for, print, store, or paste raw tokens. The user signs in once with `qovery auth --headless`; after that, `qovery api …` and every `qovery` command use the locally stored credentials. See [reference/auth.md](reference/auth.md).
>
> **`qovery auth --headless` is interactive and needs the user's browser.** It prints a URL the user must open and complete (GitHub / GitLab / Google / email). You cannot do the browser step for them. In Claude Code, have the user run `! qovery auth --headless` so the URL appears in-session; then wait for them to confirm they finished.
>
> **First login = sign-up.** A brand-new user does not "register" separately — the account is created automatically on the first successful OAuth login. There is no API to create an account.
>
> **Do NOT ask the user to choose a plan, and never expose internal plan names.** Always create the organization on **`SCALE_2026`** by default (the individual tier isn't customer-selectable and Enterprise pricing is custom). Confirm only the org **name** before creating (org creation is a real, billable-tier resource). Deviate from `SCALE_2026` only if the user explicitly names a plan themselves.
>
> **There is no `qovery organization` CLI command.** Manage organizations through `qovery api organization …` (which uses the CLI's auth) or the REST API — not a CLI noun.
>
> **Set expectations about billing.** A new organization has no credit card, so managed clusters and deployments are blocked (`billing_deployment_restriction: NO_CREDIT_CARD`) until one is added. A local demo cluster (`qovery demo up`) works with no card.
>
> **Sign-up tracking is tagged, consented, and best-effort.** Phase 4 records the sign-up in Qovery's pipeline and the HubSpot lead funnel, always tagged `signup_source: "CLI"` / `"AI-Agent"` so it's distinguishable from web sign-ups. Only send data the user gave in the interview — never invent PII. The Cargo/HubSpot token comes from `QOVERY_CARGO_INGEST_TOKEN` (or backend forwarding) and is **never committed or printed**. Tracking must never block or fail the sign-up.

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
- [ ] Phase 3 — Interview + create + enrich: ask name, website, use case (NOT plan — default `SCALE_2026`); create the org; enrich its profile (description, logo, icon) from the website; set context; associate the existing tracking run now that the org id exists (do not start again)
- [ ] Phase 4 — Record sign-up: fire `POST /admin/userSignUp` + the Cargo/HubSpot lead ingest, tagged `signup_source=CLI` (best-effort, non-blocking)
- [ ] Phase 5 — Configure + hand off: optional first project for the use case, billing/demo-cluster note, invite team, hand a brief to qovery-onboard
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
| Phase 3 | [reference/phase3-create-organization.md](reference/phase3-create-organization.md) | Interview (name, website, use case — plan is auto `SCALE_2026`, never asked); create via `qovery api`; enrich profile (description/logo/icon) from the website; update via PUT; set context; billing restriction |
| Phase 4 | [reference/phase4-signup-tracking.md](reference/phase4-signup-tracking.md) | Record the sign-up for tracking + lead qualification (mirrors the console): `POST /admin/userSignUp` + Cargo→HubSpot ingest, tagged `signup_source=CLI`; token via env, never committed |
| Phase 5 | [reference/phase5-next-steps.md](reference/phase5-next-steps.md) | Configure for the use case (optional first project), add credit card / `qovery demo up`, invite teammates, hand a brief to qovery-onboard |

## Templates

| Template | Use |
|---|---|
| [templates/scripts/check-and-install-cli.sh](templates/scripts/check-and-install-cli.sh) | Detect whether the CLI is installed + its version; print the right install command per OS if missing |
| [templates/scripts/enrich-from-website.sh](templates/scripts/enrich-from-website.sh) | Derive candidate org profile (description, logo_url, icon_url) from a company website, with fallbacks |
| [templates/scripts/record-signup.sh](templates/scripts/record-signup.sh) | Record the sign-up: `POST /admin/userSignUp` + Cargo/HubSpot lead ingest, tagged `signup_source`; `--dry-run` supported; Cargo token from env only |

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
NEW_ORG_ID=$(qovery api organization --field name="My Org" --field plan=SCALE_2026 | jq -r '.id')   # plan is always SCALE_2026; never ask the user
#    …or with the enriched profile via --input (see Phase 3.4)

# 3c. Associate the run started at launch with NEW_ORG_ID (see "Usage Tracking").
#     Keep the same state path; do not emit another start.

# 4. Record the sign-up for tracking + lead qualification (tagged CLI; --dry-run to preview)
COMPANY="My Org" USE_CASE="<use case>" SIGNUP_SOURCE="CLI" bash templates/scripts/record-signup.sh

# 5. Point the CLI at it, then hand off to qovery-onboard
qovery context set

# Optional: try Qovery locally with no credit card
qovery demo up
```

## Organization plan (automatic)

The skill **always creates the organization on `SCALE_2026`** and **never asks the user to choose a plan**. Internal plan names (individual/team/enterprise tiers) are not surfaced in the sign-up flow — the individual tier isn't customer-selectable and Enterprise pricing is custom, so exposing a picker is confusing and off-brand. Users change plan later in the Console (**Settings → Billing**); pricing is at <https://www.qovery.com/pricing>.

Only deviate from `SCALE_2026` if the user *explicitly* names a specific plan themselves — never prompt for it.

## Reference links

- **Create organization API**: <https://www.qovery.com/docs/api-reference/organization-main-calls/create-an-organization>
- **Qovery CLI**: <https://www.qovery.com/docs/cli/overview>
- **Qovery CLI (GitHub / install)**: <https://github.com/Qovery/qovery-cli>
- **Pricing & plans**: <https://www.qovery.com/pricing>
- **Qovery Console**: <https://console.qovery.com>
