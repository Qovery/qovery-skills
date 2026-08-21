# Phase 2 — Authenticate (sign up = first login)

A brand-new user does not register separately. The **first successful login creates the account** through Qovery's OAuth flow (GitHub, GitLab, Google, or email). There is no API to create an account — authentication is always done through the CLI (or Console).

## 2.1 Run the headless login

```bash
qovery auth --headless
```

`--headless` prints a **URL** and waits. The user opens that URL in a browser, signs in / signs up with their provider, and the CLI stores the credentials locally. (Plain `qovery auth`, without the flag, opens a browser automatically when the machine has one — use `--headless` for remote shells, containers, or anywhere the agent is driving a non-GUI terminal.)

**This step is interactive and needs the user's browser — you cannot complete it for them.** In Claude Code, ask the user to run it so the URL lands in the session and they can act on it:

```
! qovery auth --headless
```

Then wait for the user to confirm they finished the browser step before continuing. Do not try to scrape or submit the OAuth flow yourself.

## 2.2 Verify authentication

Confirm the stored credentials work with any authenticated read — `qovery api organization` returns JSON when signed in:

```bash
qovery api organization
```

- **JSON (a `results` array, possibly empty)** → authenticated. Continue to Phase 3.
- **`access token is invalid or expired. Sign in using 'qovery auth' or 'qovery auth --headless' command.`** → not signed in (or the session lapsed). Re-run §2.1.

## 2.3 How authentication is managed from here on

- After login, **every** `qovery` command and `qovery api …` call uses the locally stored credentials. You never handle, print, or paste a token. This is the safe path and it satisfies the token-secrecy rules in [auth.md](auth.md).
- If you ever need the token inline (rare), use `qovery auth token --print` **inside** a command — never as a standalone that echoes it (see [auth.md](auth.md)).
- **CI / non-interactive environments**: instead of interactive login, the user can set `QOVERY_CLI_ACCESS_TOKEN` (or `Q_CLI_ACCESS_TOKEN`) in their environment. Generate a token with `qovery token` and store it in their secret manager — do not print it.

Once `qovery api organization` returns JSON, continue to Phase 3.
