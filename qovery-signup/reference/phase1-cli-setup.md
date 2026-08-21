# Phase 1 — Install and Verify the Qovery CLI

The whole sign-up flow runs through the Qovery CLI, so make sure it is present and current before anything else.

## 1.1 Check whether it is already installed

```bash
command -v qovery >/dev/null 2>&1 && qovery version || echo "Qovery CLI not found"
```

Run `templates/scripts/check-and-install-cli.sh` to do this and print the right install command for the user's OS when it is missing.

- **Installed** → note the version and go to Phase 2. Offer `qovery upgrade` if it looks old.
- **Not installed** → install it (§1.2).

## 1.2 Install per platform

| OS / manager | Command |
|---|---|
| macOS (Homebrew) | `brew install qovery-cli` |
| Windows (Scoop) | `scoop install qovery-cli` |
| Arch Linux (yay) | `yay qovery-cli` |
| Any (release binary) | Download the latest from <https://github.com/Qovery/qovery-cli/releases>, unpack, and move `qovery` onto your `PATH` (e.g. `/usr/local/bin`) |
| Docker | `public.ecr.aws/r3m4q3r9/qovery-cli` |

Notes:
- On macOS without Homebrew, either install Homebrew first or use the release binary.
- Prefer letting the user run the install command themselves if it needs elevated permissions (e.g. writing to `/usr/local/bin` or `brew` on a locked-down machine). In Claude Code they can run `! brew install qovery-cli`.
- Do **not** auto-run `sudo` installs without asking.

## 1.3 Verify

```bash
qovery version
```

A version string (e.g. `Info: 1.166.x`) confirms it is ready. To update later:

```bash
qovery upgrade
```

Once `qovery version` works, continue to Phase 2 (authenticate).
