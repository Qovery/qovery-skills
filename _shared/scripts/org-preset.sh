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

if [ -n "$org_arg" ] && ! printf '%s' "$org_arg" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
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

# Private cache, one directory per organization; one file per response, holding the ETag on its
# first line and the body after it, so the pair is always replaced together (write, then rename).
# A 304 only answers when the caller's own preset still has that ETag, which names the source, preset
# and revision, so it never replays another member's preset. The stale fallback is the only case that
# skips the server: it is limited to an explicit organization id and to outages, never to an
# authentication or permission failure.
cache_root="${QOVERY_PRESET_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/qovery-skills/presets}"
cache_dir="$cache_root/${org_arg:-current-context}"
umask 077
cache_ok=1
mkdir -p "$cache_dir" 2>/dev/null || cache_ok=0
cache_file="$cache_dir/$cache_name.cache"

cached_etag() { head -n 1 "$cache_file" 2>/dev/null; }
cached_body() { tail -n +2 "$cache_file"; }

unavailable() {
  echo "org-preset: unavailable reason=$1" >&2
  exit 0
}

stale_or_unavailable() {
  if [ -n "$org_arg" ] && [ -s "$cache_file" ]; then
    echo "org-preset: stale-cache reason=$1 etag=$(cached_etag)" >&2
    cached_body
    exit 0
  fi
  unavailable "$1"
}

# The gateway compresses responses and drops the ETag of a compressed one, which would make every
# check a full download. Preset responses are small, so ask for them uncompressed.
headers=(-H "Accept-Encoding: identity")
if [ -s "$cache_file" ] && [ -n "$(cached_etag)" ]; then
  headers+=(-H "If-None-Match: $(cached_etag)")
fi

response="$(mktemp "${TMPDIR:-/tmp}/qovery-preset.XXXXXX")" || unavailable "tmpfile"
body="$(mktemp "${TMPDIR:-/tmp}/qovery-preset-body.XXXXXX")" || { rm -f "$response"; unavailable "tmpfile"; }
trap 'rm -f "$response" "$body"' EXIT
# -i prints the status line and headers before the body; non-2xx goes to stderr, hence 2>&1.
qovery api -i "${headers[@]}" "$endpoint" >"$response" 2>&1 || true

status="$(head -n 1 "$response" | awk '/^HTTP\//{print $2}')"
etag="$(awk 'NR>1 && /^\r?$/{exit} NR>1 && tolower($1)=="etag:"{sub(/^[^:]*: */,""); sub(/\r$/,""); print}' "$response")"

case "$status" in
  200)
    awk 'f{print} /^\r?$/{f=1}' "$response" >"$body"
    # The answer is the response itself; the cache is best effort and never stands in for it.
    if [ "$cache_ok" = 1 ] && [ -n "$etag" ]; then
      staged="$(mktemp "$cache_dir/.$cache_name.XXXXXX" 2>/dev/null)" \
        && { printf '%s\n' "$etag"; cat "$body"; } >"$staged" \
        && mv -f "$staged" "$cache_file" \
        || rm -f "${staged:-}"
    fi
    echo "org-preset: fresh etag=$etag" >&2
    cat "$body"
    ;;
  304)
    echo "org-preset: cached etag=$(cached_etag)" >&2
    cached_body
    ;;
  401|403)
    # No longer allowed to read this organization's presets: never replay what was allowed before.
    unavailable "http-$status"
    ;;
  404)
    # On the manifest, an older q-core without presets. On a skill, a name the preset does not know.
    if [ "$command_name" = "manifest" ]; then unavailable "not-supported"; fi
    unavailable "skill-not-found"
    ;;
  "")
    # No HTTP status: the CLI stopped before or during the request. Signed out is not an outage.
    if grep -Eqi 'log ?in|logged|auth|token|credential' "$response"; then
      unavailable "signed-out"
    fi
    stale_or_unavailable "no-response"
    ;;
  *)
    stale_or_unavailable "http-$status"
    ;;
esac
exit 0
