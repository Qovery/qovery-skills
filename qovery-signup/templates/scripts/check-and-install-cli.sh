#!/usr/bin/env bash
# check-and-install-cli.sh — check whether the Qovery CLI is installed and, if not,
# print the right install command for this OS. Does NOT run privileged installs on its own.
#
# Usage:
#   bash check-and-install-cli.sh            # detect + advise
#   bash check-and-install-cli.sh --install  # additionally attempt `brew install` on macOS if brew exists
#
# Exit codes: 0 = CLI present, 1 = CLI missing (advice printed), 2 = missing + auto-install attempted.
set -euo pipefail

TRY_INSTALL="no"
[ "${1:-}" = "--install" ] && TRY_INSTALL="yes"

if command -v qovery >/dev/null 2>&1; then
  echo "Qovery CLI is installed: $(qovery version 2>/dev/null | head -1)"
  echo "Update anytime with: qovery upgrade"
  exit 0
fi

echo "Qovery CLI is NOT installed."
OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin)
    echo "Recommended (macOS): brew install qovery-cli"
    if [ "$TRY_INSTALL" = "yes" ] && command -v brew >/dev/null 2>&1; then
      echo "Attempting: brew install qovery-cli"
      brew install qovery-cli
      command -v qovery >/dev/null 2>&1 && { echo "Installed: $(qovery version | head -1)"; exit 0; }
      exit 2
    fi
    command -v brew >/dev/null 2>&1 || echo "Homebrew not found — install it from https://brew.sh or use a release binary (below)."
    ;;
  Linux)
    echo "Arch Linux:      yay qovery-cli"
    echo "Any Linux:       download the latest release binary and put it on your PATH:"
    echo "                 https://github.com/Qovery/qovery-cli/releases"
    echo "                 (unpack, then: sudo mv qovery /usr/local/bin/qovery && sudo chmod +x /usr/local/bin/qovery)"
    ;;
  *)
    echo "Windows (Scoop): scoop install qovery-cli"
    echo "Or download a release binary: https://github.com/Qovery/qovery-cli/releases"
    ;;
esac

echo
echo "After installing, verify with: qovery version"
exit 1
