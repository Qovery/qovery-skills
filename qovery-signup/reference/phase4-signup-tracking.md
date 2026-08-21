# Phase 4 — Record the Sign-up (tracking & lead qualification)

Mirror what `console.qovery.com` does on sign-up, so CLI/AI-agent sign-ups land in the same pipelines as web sign-ups — **clearly tagged as agent/CLI** so marketing and sales can segment them. The skill already collected the qualifying fields in Phase 3 (company/org, website, use case), so this is mostly plumbing.

## 4.1 What the console fires (and what we replicate)

On sign-up the console does two server-reachable things (plus browser-only GTM/HubSpot analytics we can't run in a terminal):

1. **`POST /admin/userSignUp`** — Qovery's own sign-up record (name, email, `type_of_use`, `qovery_usage`, `company_name`, `user_role`, `company_size`, …).
2. **Cargo lead ingest** → HubSpot/CRM — `{email, first_name, last_name, company, job_title, phone, website, signup_source}`. Cargo is the RevOps bridge that qualifies the lead in HubSpot.

We replicate both from the CLI, setting **`signup_source: "CLI"`** (or `"AI-Agent"`) instead of `"Console"`.

> **Cannot be replicated from a terminal:** GTM/HubSpot browser tracking (page analytics, the `hutk` cookie, HubSpot forms) and UTM attribution (the console reads UTMs from browser `localStorage`). That's expected — the meaningful signal here is the server-side sign-up + the `signup_source` tag.

## 4.2 Run it

Identity (first/last name, email) is read automatically from `qovery api account`; the qualification fields come from Phase 1/3 and are passed as env vars:

```bash
COMPANY="<org name>" \
USE_CASE="<the use case from Phase 3.1>" \
USER_ROLE="<their role, optional>" \
TYPE_OF_USE=WORK \                 # PERSONAL | SCHOOL | WORK
WEBSITE="<website_url, optional>" \
SIGNUP_SOURCE="CLI" \              # or "AI-Agent"
[ QOVERY_CARGO_INGEST_TOKEN="<token>" ] \
bash templates/scripts/record-signup.sh
```

Preview exactly what would be sent, without sending, with `--dry-run`.

The script:
1. Reads identity from `qovery api account` (uses the CLI's stored auth — no token handling).
2. `POST /admin/userSignUp` via `qovery api` — `qovery_usage` = the use case, `company_name` = the org, plus role / `type_of_use` / `company_size`. There is no `signup_source` field on this endpoint, so the source is recorded in the free-text `current_step` as `qovery-signup-skill:<SIGNUP_SOURCE>`.
3. If `QOVERY_CARGO_INGEST_TOKEN` is set, POSTs the lead to Cargo → HubSpot with `signup_source`. If it is **not** set, this step is **skipped** (non-fatal).

## 4.3 The Cargo / HubSpot token (do not commit)

The Cargo ingest endpoint uses a write token. **Never hardcode it in this repo or print it.** Provide it out-of-band via the `QOVERY_CARGO_INGEST_TOKEN` environment variable, or — cleaner — have Qovery's **backend forward `/admin/userSignUp` → Cargo/HubSpot server-side**, so the skill only needs the documented `userSignUp` call and no marketing secret ever touches the CLI. Treat this token with the same rules as any credential in [auth.md](auth.md).

## 4.4 Consent & tagging

- Only send data the user provided during the interview; don't invent a phone number or scrape extra PII.
- Always tag `signup_source` (`CLI` / `AI-Agent`) so these sign-ups are distinguishable from web sign-ups in HubSpot.
- This step is best-effort and non-blocking: if tracking fails, continue to Phase 5 — never let it break the sign-up.

Once recorded, continue to Phase 5 (next steps + hand-off).
