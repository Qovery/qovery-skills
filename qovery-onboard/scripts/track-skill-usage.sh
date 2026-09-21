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

# The payload is built by hand rather than with jq, so a machine without jq — a stock
# macOS, for one — still reports usage as long as it knows the organization. jq is needed
# only to read an organization id out of the API response, and that is checked where it is
# used. The skill name goes into JSON, so refuse anything that is not a plain identifier
# rather than trust it to be quote-free.
case "$SKILL_NAME" in
  *[!a-zA-Z0-9._-]*) exit 0 ;;
esac

# Resolve the Authorization header. Scheme matters: an API token needs `Token`, a JWT
# needs `Bearer`, and both can arrive through the same channel.
#
# `qovery auth token --print` hands back whatever GetAccessToken() resolved, including an
# opaque API token taken from QOVERY_CLI_ACCESS_TOKEN, so labelling its output `Bearer`
# would reject exactly the CI setup the docs recommend. `--authorization-header` returns
# the CLI's own verdict instead, which is the one source that cannot be wrong.
is_jwt_shaped() {
  case "$1" in
    *.*.*.*) return 1 ;;   # four segments or more is not a JWT
    ?*.?*.?*) return 0 ;;  # exactly three, none of them empty
    *) return 1 ;;
  esac
}

CLI_ENV_TOKEN="${QOVERY_CLI_ACCESS_TOKEN:-${Q_CLI_ACCESS_TOKEN:-}}"

if [ -n "${QOVERY_API_TOKEN:-}" ]; then
  AUTHORIZATION="Token $QOVERY_API_TOKEN"
elif command -v qovery >/dev/null 2>&1 &&
  CLI_HEADER="$(qovery auth token --print --authorization-header 2>/dev/null)" &&
  [ -n "$CLI_HEADER" ]; then
  AUTHORIZATION="$CLI_HEADER"
elif command -v qovery >/dev/null 2>&1 && CLI_TOKEN="$(qovery auth token --print 2>/dev/null)" && [ -n "$CLI_TOKEN" ]; then
  # An older CLI without --authorization-header: fall back to reading the shape.
  if is_jwt_shaped "$CLI_TOKEN"; then AUTHORIZATION="Bearer $CLI_TOKEN"; else AUTHORIZATION="Token $CLI_TOKEN"; fi
elif [ -n "$CLI_ENV_TOKEN" ]; then
  # No CLI installed at all, which is normal in CI.
  if is_jwt_shaped "$CLI_ENV_TOKEN"; then AUTHORIZATION="Bearer $CLI_ENV_TOKEN"; else AUTHORIZATION="Token $CLI_ENV_TOKEN"; fi
else
  exit 0
fi

# Deadlines matter more here than anywhere else in the skill: this runs before the skill
# does anything else, so an API that accepts the connection and then goes quiet would hang
# the whole session. Give up quickly and let the session get on with its work.
qovery_api() {
  curl -s --connect-timeout 3 --max-time 8 \
    -H "Authorization: $AUTHORIZATION" -H "User-Agent: $USER_AGENT" "$@"
}

# Resolve the organization the caller is actually working in. Never guess: taking
# results[0] files the event under whichever organization the API happened to list first,
# which for anyone belonging to several is a phantom event in the wrong one — and the
# skill's real work then lands in another, so the session is counted twice. Where the
# organization is genuinely ambiguous, send nothing and let the server attribute the
# session from the User-Agent on the first real API call.
[ -n "$ORG_ID" ] || ORG_ID="${QOVERY_ORGANIZATION_ID:-}"
if [ -z "$ORG_ID" ] && command -v jq >/dev/null 2>&1; then
  ORGANIZATIONS="$(qovery_api "https://api.qovery.com/organization" 2>/dev/null)"
  if [ "$(printf '%s' "$ORGANIZATIONS" | jq -r '.results | length' 2>/dev/null)" = "1" ]; then
    ORG_ID="$(printf '%s' "$ORGANIZATIONS" | jq -r '.results[0].id // empty' 2>/dev/null)"
  fi
fi
[ -n "$ORG_ID" ] || exit 0

# The endpoint declares organizationId as a UUID, so check the whole 8-4-4-4-12 shape
# rather than just the alphabet: a value like `deadbeef` is hex throughout and would
# otherwise be POSTed to a path that can only 404, losing the event without a trace.
case "$ORG_ID" in
  [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
  *) exit 0 ;;
esac

qovery_api -o /dev/null -X POST "https://api.qovery.com/organization/${ORG_ID}/skill-tracking" \
  -H "Content-Type: application/json" \
  -d "{\"skill_name\":\"${SKILL_NAME}\"}" \
  >/dev/null 2>&1

exit 0
