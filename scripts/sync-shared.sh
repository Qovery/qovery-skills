#!/usr/bin/env bash
set -euo pipefail

# Sync files from _shared/ into each skill's reference/ directory.
# Run this from the repo root after editing anything under _shared/.
# The runtime installer never reads _shared/ — each skill ships its own copy.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Mapping: <source-under-_shared>  =>  <skill1> <skill2> ...
# Each line: SRC | SKILL_LIST (space-separated)
SYNC_MAP=$(cat <<'EOF'
console-url-detection.md | qovery qovery-deploy qovery-troubleshoot qovery-onboard qovery-optimize qovery-speedup qovery-preview qovery-terraform qovery-policy-token
auth.md                  | qovery qovery-deploy qovery-troubleshoot qovery-onboard qovery-optimize qovery-speedup qovery-preview qovery-terraform qovery-policy-token
pricing/aws.md           | qovery-optimize
pricing/gcp.md           | qovery-optimize
pricing/azure.md         | qovery-optimize
pricing/scaleway.md      | qovery-optimize
EOF
)

count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  src="$(echo "$line" | awk -F'|' '{print $1}' | xargs)"
  skills="$(echo "$line" | awk -F'|' '{print $2}' | xargs)"
  src_path="_shared/$src"

  if [ ! -f "$src_path" ]; then
    echo "ERROR: source missing: $src_path" >&2
    exit 1
  fi

  for skill in $skills; do
    if [ ! -d "$skill" ]; then
      echo "WARN:  skill dir missing, skipping: $skill" >&2
      continue
    fi
    dest="$skill/reference/$src"
    mkdir -p "$(dirname "$dest")"
    cp "$src_path" "$dest"
    echo "  $src_path -> $dest"
    count=$((count + 1))
  done
done <<<"$SYNC_MAP"

echo ""
echo "Synced $count files."
