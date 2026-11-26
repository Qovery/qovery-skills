#!/usr/bin/env bash
# Prints every field that a source switch must keep but that differs between two GET responses.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: [AUTO_DEPLOY=true|false] [AUTO_PREVIEW=true|false] check-kept-fields.sh BEFORE_JSON AFTER_JSON" >&2
  echo "  two GET /container/{containerId} responses; pass the same AUTO_DEPLOY and AUTO_PREVIEW as build-switch-body.sh" >&2
  exit 2
fi
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

# Build settings exist only on a Git source. The auto-deploy and preview flags must match what the body sent:
# the value the user chose, else the stored one when the source kind stays, else false.
after_is_git="$(jq -r '.source | has("git_repository")' "$2")"
before_is_git="$(jq -r '.source | has("git_repository")' "$1")"
flag_json() {
  case "${1:-}" in
    '') echo null ;;
    true|false) echo "$1" ;;
    *) echo "$2 must be true or false" >&2; exit 2 ;;
  esac
}
expected_flags="$(jq -c --argjson d "$(flag_json "${AUTO_DEPLOY:-}" AUTO_DEPLOY)" \
  --argjson p "$(flag_json "${AUTO_PREVIEW:-}" AUTO_PREVIEW)" --argjson same "$([ "$before_is_git" = "$after_is_git" ] && echo true || echo false)" '
  {auto_deploy: (if $d == null then (if $same then (.auto_deploy // false) else false end) else $d end),
   auto_preview: (if $p == null then (if $same then (.auto_preview // false) else false end) else $p end)}' "$1")"

kept='{id, name, description, icon_uri, environment: .environment.id, cpu, memory, gpu,
       min_running_instances, max_running_instances, ephemeral_storage_in_gib, cpu_architecture,
       arguments, entrypoint, healthchecks, autoscaling,
       ports: ((.ports // []) | map(with_entries(select(.value != null))) | sort_by(.id)),
       storage: ((.storage // []) | sort_by(.id)),
       annotations_groups: ((.annotations_groups // []) | map(.id) | sort),
       labels_groups: ((.labels_groups // []) | map(.id) | sort)}'
if [ "$before_is_git" = true ] && [ "$after_is_git" = true ]; then
  kept="$kept + {build_settings}"
fi
kept="$kept + {auto_deploy: (.auto_deploy // false), auto_preview: (.auto_preview // false)}"

diff_out="$(diff <(jq -S --argjson f "$expected_flags" "$kept + \$f" "$1") <(jq -S "$kept" "$2") || true)"
if [ -z "$diff_out" ]; then
  echo "kept: id, name, environment, resources, instances, arguments, entrypoint, health checks, autoscaling, ports, volumes, groups$([ "$before_is_git$after_is_git" = truetrue ] && echo ', build settings'); auto-deploy and preview flags as chosen"
  exit 0
fi
echo "changed fields (< before, > after):"
echo "$diff_out"
exit 1
