#!/usr/bin/env bash
# One q-core v1 lifecycle implementation, shipped as a native Rust binary.
# No legacy fallback; no credentials in shell arguments/output; best effort.
set +x
skill_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  start|resume|associate|cleanup|worker)
    if [ -x "$skill_scripts/skill-run" ]; then
      "$skill_scripts/skill-run" "$@" || true
    elif [ "${QOVERY_SKILLS_TRACKING_DEBUG:-}" = "1" ]; then
      echo 'skill-tracking: ignored (native helper unavailable; reinstall skills)' >&2
    fi
    ;;
  *)
    [ "${QOVERY_SKILLS_TRACKING_DEBUG:-}" != "1" ] || echo 'skill-tracking: ignored (use lifecycle command)' >&2
    ;;
esac
exit 0
