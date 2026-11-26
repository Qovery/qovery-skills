#!/usr/bin/env bash
# Fetch the organization's skill preset for the signed-in member, with an ETag cache.
#
#   org-preset.sh manifest [ORG_ID]              the resolved manifest (names, modes, sizes, hashes; no content)
#   org-preset.sh skill SKILL_NAME [ORG_ID]      what to load for one skill: content and team context
#   org-preset.sh view SKILL_NAME [ORG_ID]       same as skill, for a person reading it (not counted as an agent load)
#
# ORG_ID defaults to the organization of the current `qovery` CLI context.
# Calls go through `qovery api`, so the CLI session is used and no token is handled here.
#
# stdout: the JSON body (fresh or from the cache), or nothing when no preset could be read.
# stderr: one status line, `org-preset: <fresh|cached|stale-cache|unavailable> ...`.
# Exit code is always 0: a preset that cannot be fetched must never stop the agent.
set +x
set -u

command_name="${1:-}"
case "$command_name" in
  manifest) skill_name=""; org_arg="${2:-}" ;;
  skill|view)
    skill_name="${2:-}"; org_arg="${3:-}"
    if ! printf '%s' "$skill_name" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$'; then
      echo "org-preset: unavailable reason=invalid-skill-name" >&2
      exit 0
    fi
    ;;
  *)
    echo "usage: org-preset.sh manifest [ORG_ID] | skill SKILL_NAME [ORG_ID] | view SKILL_NAME [ORG_ID]" >&2
    exit 0
    ;;
esac

if [ -n "$org_arg" ] && ! printf '%s' "$org_arg" | grep -Eq '^[0-9a-fA-F-]{36}$'; then
  echo "org-preset: unavailable reason=invalid-organization-id" >&2
  exit 0
fi

if ! command -v qovery >/dev/null 2>&1; then
  echo "org-preset: unavailable reason=qovery-cli-missing" >&2
  exit 0
fi

context_placeholder='{organizationId}'
org_path="${org_arg:-$context_placeholder}"
case "$command_name" in
  manifest) endpoint="organization/$org_path/skillPreset/resolved"; cache_name="manifest" ;;
  skill)    endpoint="organization/$org_path/skillPreset/resolved/skill/$skill_name"; cache_name="skill-$skill_name" ;;
  view)     endpoint="organization/$org_path/skillPreset/resolved/skill/$skill_name?purpose=VIEW"; cache_name="skill-$skill_name" ;;
esac

# Private cache, one directory per organization. Without an explicit id the cache is keyed by the
# CLI context and is only reused on a 304, never as a fallback: the context may point elsewhere now.
cache_root="${QOVERY_PRESET_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/qovery-skills/presets}"
cache_dir="$cache_root/${org_arg:-current-context}"
umask 077
mkdir -p "$cache_dir" 2>/dev/null || true
body_file="$cache_dir/$cache_name.json"
etag_file="$cache_dir/$cache_name.etag"

fallback() {
  local reason="$1"
  if [ -n "$org_arg" ] && [ -s "$body_file" ]; then
    echo "org-preset: stale-cache reason=$reason etag=$(cat "$etag_file" 2>/dev/null)" >&2
    cat "$body_file"
  else
    echo "org-preset: unavailable reason=$reason" >&2
  fi
  exit 0
}

# The gateway compresses responses and drops the ETag of a compressed one, which would make every
# check a full download. Preset responses are small, so ask for them uncompressed.
headers=(-H "Accept-Encoding: identity")
if [ -s "$body_file" ] && [ -s "$etag_file" ]; then
  headers+=(-H "If-None-Match: $(cat "$etag_file")")
fi

response="$(mktemp "${TMPDIR:-/tmp}/qovery-preset.XXXXXX")" || fallback "tmpfile"
trap 'rm -f "$response"' EXIT
# -i prints the status line and headers before the body; non-2xx goes to stderr, hence 2>&1.
qovery api -i "${headers[@]}" "$endpoint" >"$response" 2>&1 || true

status="$(head -n 1 "$response" | awk '/^HTTP\//{print $2}')"
etag="$(awk 'NR>1 && /^$/{exit} NR>1 && tolower($1)=="etag:"{sub(/^[^:]*: */,""); sub(/\r$/,""); print}' "$response")"

case "$status" in
  200)
    awk 'f{print} /^\r?$/{f=1}' "$response" >"$body_file.tmp" && mv "$body_file.tmp" "$body_file"
    if [ -n "$etag" ]; then printf '%s' "$etag" >"$etag_file"; else rm -f "$etag_file"; fi
    echo "org-preset: fresh etag=$etag" >&2
    cat "$body_file"
    ;;
  304)
    echo "org-preset: cached etag=$(cat "$etag_file" 2>/dev/null)" >&2
    cat "$body_file"
    ;;
  "")
    # No HTTP status: the CLI failed before the request (not signed in, no organization in context, network).
    fallback "no-response"
    ;;
  404)
    # On the manifest, an older q-core without presets. On a skill, a name the preset does not know.
    if [ "$command_name" = "manifest" ]; then fallback "not-supported"; fi
    echo "org-preset: unavailable reason=skill-not-found" >&2
    ;;
  *)
    fallback "http-$status"
    ;;
esac
exit 0
