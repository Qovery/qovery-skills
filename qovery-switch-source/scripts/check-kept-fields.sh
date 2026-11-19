#!/usr/bin/env bash
# Prints every field that a source switch must keep but that differs between two GET responses.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: check-kept-fields.sh BEFORE_JSON AFTER_JSON  (two GET /container/{containerId} responses)" >&2
  exit 2
fi
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

# Build settings exist only on a Git source, and a switch to Git turns auto-deploy off on purpose.
after_is_git="$(jq -r '.source | has("git_repository")' "$2")"
before_is_git="$(jq -r '.source | has("git_repository")' "$1")"

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
if [ "$after_is_git" = false ]; then
  kept="$kept + {auto_deploy, auto_preview}"
fi

diff_out="$(diff <(jq -S "$kept" "$1") <(jq -S "$kept" "$2") || true)"
if [ -z "$diff_out" ]; then
  echo "kept: id, name, environment, resources, instances, arguments, entrypoint, health checks, autoscaling, ports, volumes, groups$([ "$before_is_git$after_is_git" = truetrue ] && echo ', build settings')$([ "$after_is_git" = false ] && echo ', auto-deploy and preview flags')"
  exit 0
fi
echo "changed fields (< before, > after):"
echo "$diff_out"
exit 1
