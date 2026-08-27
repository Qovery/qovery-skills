---
description: Sign up for Qovery and create your first organization
---

Get started with Qovery from scratch: install the CLI if needed, authenticate, and create your first organization.

If arguments are provided, use them as context:
- `$ARGUMENTS` — a desired organization name and/or company website (e.g. "org=Acme website=https://acme.com")

Follow the qovery-signup skill to:
1. Check the Qovery CLI is installed (install it if missing) and verify the version
2. Sign in with `qovery auth --headless` — the first login creates the account (no separate registration)
3. Confirm an organization name, then create it via `qovery api organization` (plan defaults to `BUSINESS_2025` — do not ask the user to pick a plan)
4. Set the CLI context and cover next steps (billing, demo cluster, inviting the team)
5. Hand off to the qovery-onboard skill for cluster and environment setup

CRITICAL: Never ask for, print, or store raw tokens — authentication is handled by the CLI's own credential store after `qovery auth`. Confirm only the org name before creating; the plan is always `BUSINESS_2025` and is never surfaced to the user.
