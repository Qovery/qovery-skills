#!/usr/bin/env bash
# A container update replaces the whole service: a port or volume left out of the body is removed.
# Start from the current GET response so the only change in the body is the new source.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: build-switch-body.sh CONTAINER_JSON SOURCE_JSON [BUILD_SETTINGS_JSON]
  CONTAINER_JSON       file holding the GET /container/{containerId} response
  SOURCE_JSON          file holding {"git_repository": {...}} or {"image": {...}}
  BUILD_SETTINGS_JSON  optional file holding build settings (Git source only);
                       without it, a Git container keeps its current build settings
Prints the PUT /container/{containerId} request body on stdout.
EOF
  exit 2
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

container="$1"
source_file="$2"
build_settings='null'
[ -n "${3:-}" ] && build_settings="$(cat "$3")"

jq --slurpfile src "$source_file" --argjson bs "$build_settings" '
  ($src[0]) as $source
  | ($source | has("git_repository")) as $to_git
  | if ($to_git == ($source | has("image")))
    then error("SOURCE_JSON must hold exactly one of git_repository or image") else . end
  | if ($to_git | not) and ($source.image.registry_id // "") == ""
    then error("SOURCE_JSON image must hold registry_id: pick one from organization/{organizationId}/containerRegistry") else . end
  | ({
      name, description, arguments, entrypoint, cpu, memory, gpu,
      min_running_instances, max_running_instances, ephemeral_storage_in_gib,
      cpu_architecture, icon_uri, autoscaling,
      ports: [(.ports // [])[] | {id, name, internal_port, external_port, publicly_accessible,
                                  is_default, protocol, public_path, public_path_rewrite}
                               | with_entries(select(.value != null))],
      storage: [(.storage // [])[] | {id, type, size, mount_point}],
      annotations_groups: [(.annotations_groups // [])[] | {id}],
      labels_groups: [(.labels_groups // [])[] | {id}],
      auto_deploy: (if $to_git then false else (.auto_deploy // false) end),
      auto_preview: (if $to_git then false else (.auto_preview // false) end),
      build_settings: (if $to_git then ($bs // .build_settings) else null end),
      source: $source
    } | with_entries(select(.value != null)))
  + {healthchecks: (.healthchecks // {})}
' "$container"
