#!/usr/bin/env bash
# Tests for _shared/scripts/org-preset.sh against a fake `qovery` CLI.
# Run from the repo root: bash scripts/test-org-preset.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/_shared/scripts/org-preset.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ORG="0193f1c2-0000-4000-8000-000000000001"
export QOVERY_PRESET_CACHE_DIR="$WORK/cache"
mkdir -p "$WORK/bin"

# The fake CLI answers according to $FAKE_MODE and records its arguments.
cat >"$WORK/bin/qovery" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
sent_etag=""
for arg in "$@"; do
  case "$arg" in "If-None-Match: "*) sent_etag="${arg#If-None-Match: }" ;; esac
done
case "$FAKE_MODE" in
  ok)
    if [ -n "$sent_etag" ] && [ "$sent_etag" = '"role-abc-3"' ]; then
      printf 'HTTP/1.1 304 Not Modified\nEtag: "role-abc-3"\n\n' >&2; exit 1
    fi
    printf 'HTTP/1.1 200 OK\nContent-Type: application/json\nEtag: "role-abc-3"\n\n{"source":"ROLE","skill_preset":{"name":"backend","revision":3}}'
    ;;
  changed)
    printf 'HTTP/1.1 200 OK\nEtag: "role-abc-4"\n\n{"source":"ROLE","skill_preset":{"name":"backend","revision":4}}'
    ;;
  signed-out) echo "Error: you are not logged in, run qovery auth" >&2; exit 1 ;;
  offline)    echo "Error: Get https://api.qovery.com: dial tcp: lookup api.qovery.com: no such host" >&2; exit 1 ;;
  outage)     printf 'HTTP/1.1 502 Bad Gateway\n\n' >&2; exit 1 ;;
  old-core)   printf 'HTTP/1.1 404 Not Found\n\n{"message":"not found"}' >&2; exit 1 ;;
  forbidden)  printf 'HTTP/1.1 403 Forbidden\n\n{"message":"forbidden"}' >&2; exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/qovery"
export PATH="$WORK/bin:$PATH"
export FAKE_LOG="$WORK/calls.log"

fail=0
check() {
  local name="$1" expected_status="$2" expected_body="$3"; shift 3
  local out err
  out="$(bash "$SCRIPT" "$@" 2>"$WORK/err")"
  err="$(cat "$WORK/err")"
  if [[ "$err" != "org-preset: $expected_status"* ]]; then
    echo "FAIL $name: status '$err', expected '$expected_status'"; fail=1; return
  fi
  if [[ "$out" != *"$expected_body"* ]]; then
    echo "FAIL $name: body '$out', expected to contain '$expected_body'"; fail=1; return
  fi
  echo "ok   $name"
}

: >"$FAKE_LOG"
FAKE_MODE=ok         check "first fetch is fresh"             fresh       '"revision":3' manifest "$ORG"
FAKE_MODE=ok         check "second fetch is a 304"            cached      '"revision":3' manifest "$ORG"
grep -q 'If-None-Match: "role-abc-3"' "$FAKE_LOG" || { echo "FAIL etag not sent"; fail=1; }
grep -qv 'Accept-Encoding: identity' "$FAKE_LOG" && { echo "FAIL a call asked for a compressed response"; fail=1; }
FAKE_MODE=changed    check "new revision replaces the cache"  fresh       '"revision":4' manifest "$ORG"
[ "$(head -n 1 "$QOVERY_PRESET_CACHE_DIR/$ORG/manifest.cache")" = '"role-abc-4"' ] || { echo "FAIL etag and body not stored together"; fail=1; }
FAKE_MODE=offline    check "offline falls back to cache"      stale-cache '"revision":4' manifest "$ORG"
FAKE_MODE=outage     check "5xx falls back to cache"          stale-cache '"revision":4' manifest "$ORG"
FAKE_MODE=signed-out check "signed out never replays"         unavailable ''             manifest "$ORG"
FAKE_MODE=forbidden  check "403 never replays"                unavailable ''             manifest "$ORG"
FAKE_MODE=old-core   check "older q-core without presets"     unavailable ''             manifest "0193f1c2-0000-4000-8000-000000000002"
FAKE_MODE=ok         check "context org uses the placeholder" fresh       '"revision":3' manifest
grep -q 'organization/{organizationId}/skillPreset/resolved$' "$FAKE_LOG" || { echo "FAIL placeholder path"; fail=1; }
[ -s "$QOVERY_PRESET_CACHE_DIR/current-context/manifest.cache" ] || { echo "FAIL context cache not seeded"; fail=1; }
FAKE_MODE=offline    check "no explicit org: no fallback"     unavailable ''             manifest
FAKE_MODE=ok         check "skill fetch"                      fresh       '"revision":3' skill qovery-deploy "$ORG"
grep -q "skillPreset/resolved/skill/qovery-deploy$" "$FAKE_LOG" || { echo "FAIL skill path"; fail=1; }
FAKE_MODE=ok         check "view is not an agent load"        cached      '"revision":3' view qovery-deploy "$ORG"
grep -q "skill/qovery-deploy?purpose=VIEW" "$FAKE_LOG" || { echo "FAIL view purpose"; fail=1; }
FAKE_MODE=old-core   check "unknown skill"                    unavailable ''             skill release-checklist "$ORG"
FAKE_MODE=ok         check "skill name injection refused"     unavailable ''             skill '../../organization' "$ORG"
FAKE_MODE=ok         check "bad organization id refused"      unavailable ''             manifest 'abc;rm'
FAKE_MODE=ok         check "non-canonical UUID refused"       unavailable ''             manifest '------------------------------------'

perm="$(ls -ld "$QOVERY_PRESET_CACHE_DIR/$ORG" | cut -c1-10)"
[ "$perm" = "drwx------" ] || { echo "FAIL cache dir permissions $perm"; fail=1; }

# A cache that cannot be written never hides a fresh answer.
QOVERY_PRESET_CACHE_DIR="$WORK/readonly/cache" ; mkdir -p "$WORK/readonly"; chmod 500 "$WORK/readonly"
FAKE_MODE=ok QOVERY_PRESET_CACHE_DIR="$QOVERY_PRESET_CACHE_DIR" check "unwritable cache still answers" fresh '"revision":3' manifest "$ORG"
chmod 700 "$WORK/readonly"; export QOVERY_PRESET_CACHE_DIR="$WORK/cache"

PATH="/usr/bin:/bin" check "no CLI installed" unavailable '' manifest "$ORG"

[ "$fail" = 0 ] && echo "All org-preset tests passed." || { echo "org-preset tests failed."; exit 1; }
