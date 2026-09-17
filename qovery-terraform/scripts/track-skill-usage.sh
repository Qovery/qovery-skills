#!/usr/bin/env bash
# track-skill-usage.sh — report that a Qovery skill was invoked.
#
# Usage:
#   bash <skill-dir>/scripts/track-skill-usage.sh <skill-name> [organization-id]
#
# Call it with the absolute path of the installed skill directory. The agent's working
# directory is the user's project, so a relative path exits 127 and nothing is recorded.
#
# It echoes the User-Agent it used, for debugging. Do not capture that into a variable to
# reuse later: each agent shell invocation is a separate process, so the variable would be
# gone by the next command. SKILL.md and reference files carry the header spelled out in
# full, with the version already substituted at install time.
#
# Best-effort throughout: no credential is ever printed, and it exits 0 even when the API
# call fails, so it can never break the skill that called it.
#
# Set QOVERY_SKILLS_NO_TRACKING=1 to skip the tracking call.

set -u

SKILL_NAME="${1:-}"
ORG_ID="${2:-}"

if [ -z "$SKILL_NAME" ]; then
  echo "usage: track-skill-usage.sh <skill-name> [organization-id]" >&2
  exit 2
fi

# install.sh replaces the placeholder at install time. The _version.txt fallback
# covers skill directories copied by hand, and resolves from the script's own
# location: the working directory is the user's project, not the skill.
VERSION="__QOVERY_SKILLS_VERSION__"
if [ "$VERSION" = "__QOVERY_SKILLS_VERSION__" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  VERSION="$(cat "$SCRIPT_DIR/../_version.txt" 2>/dev/null || echo unknown)"
fi

USER_AGENT="QoverySkill/${SKILL_NAME} (version:${VERSION}; https://github.com/Qovery/qovery-skills)"
echo "$USER_AGENT"

[ -z "${QOVERY_SKILLS_NO_TRACKING:-}" ] || exit 0
command -v curl >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# An explicit API token wins; otherwise fall back to the CLI's stored session.
if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  AUTHORIZATION="Token $QOVERY_API_TOKEN"
elif command -v qovery >/dev/null 2>&1 && CLI_TOKEN="$(qovery auth token --print 2>/dev/null)" && [ -n "$CLI_TOKEN" ]; then
  AUTHORIZATION="Bearer $CLI_TOKEN"
else
  exit 0
fi

qovery_api() {
  curl -s -H "Authorization: $AUTHORIZATION" -H "User-Agent: $USER_AGENT" "$@"
}

# Resolve the organization the caller is actually working in, best source first.
# Picking results[0] blindly mis-attributes every event for anyone who belongs to
# more than one organization, so it is only ever the last resort.
[ -n "$ORG_ID" ] || ORG_ID="${QOVERY_ORGANIZATION_ID:-}"
if [ -z "$ORG_ID" ]; then
  ORGANIZATIONS="$(qovery_api "https://api.qovery.com/organization" 2>/dev/null)"
  ORG_ID="$(printf '%s' "$ORGANIZATIONS" | jq -r '.results[0].id // empty' 2>/dev/null)"
fi
[ -n "$ORG_ID" ] || exit 0

qovery_api -o /dev/null -X POST "https://api.qovery.com/organization/${ORG_ID}/skill-tracking" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg skill_name "$SKILL_NAME" '{skill_name: $skill_name}')" \
  >/dev/null 2>&1

exit 0
