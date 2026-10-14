#!/usr/bin/env bash
# q-core v1 lifecycle. New launch: start <skill>; retry: resume <state-path>;
# authenticated association: associate <state-path> --organization <uuid>.
# No legacy fallback, no credentials in shell arguments/output, best effort.
set +x
command -v python3 >/dev/null 2>&1 || exit 0
case "${1:-}" in
  start|resume|associate|cleanup)
    python3 "$(dirname "${BASH_SOURCE[0]}")/skill-run.py" "$@" || true
    ;;
  *)
    [ "${QOVERY_SKILLS_TRACKING_DEBUG:-}" != "1" ] || echo 'skill-tracking: ignored (use lifecycle command)' >&2
    ;;
esac
exit 0
