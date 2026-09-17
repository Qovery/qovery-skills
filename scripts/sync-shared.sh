#!/usr/bin/env bash
set -euo pipefail

# Sync files from _shared/ into each skill's reference/ directory.
# Run this from the repo root after editing anything under _shared/.
# The runtime installer never reads _shared/ — each skill ships its own copy.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Mapping: <source-under-_shared> | <destination-under-each-skill> | <skill1> <skill2> ...
# Markdown goes to reference/, executables to scripts/ — the destination column
# says which, so a new shared file only needs one line here.
SYNC_MAP=$(cat <<'EOF'
console-url-detection.md      | reference/console-url-detection.md | qovery qovery-deploy qovery-troubleshoot qovery-onboard qovery-optimize qovery-speedup qovery-preview qovery-terraform qovery-policy-token
auth.md                       | reference/auth.md                  | qovery qovery-deploy qovery-troubleshoot qovery-onboard qovery-optimize qovery-speedup qovery-preview qovery-terraform qovery-policy-token qovery-signup
scripts/track-skill-usage.sh  | scripts/track-skill-usage.sh       | qovery qovery-deploy qovery-troubleshoot qovery-onboard qovery-optimize qovery-speedup qovery-preview qovery-terraform qovery-policy-token qovery-signup
pricing/aws.md                | reference/pricing/aws.md           | qovery-optimize
pricing/gcp.md                | reference/pricing/gcp.md           | qovery-optimize
pricing/azure.md              | reference/pricing/azure.md         | qovery-optimize
pricing/scaleway.md           | reference/pricing/scaleway.md      | qovery-optimize
EOF
)

count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  src="$(echo "$line" | awk -F'|' '{print $1}' | xargs)"
  dest_rel="$(echo "$line" | awk -F'|' '{print $2}' | xargs)"
  skills="$(echo "$line" | awk -F'|' '{print $3}' | xargs)"
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
    dest="$skill/$dest_rel"
    mkdir -p "$(dirname "$dest")"
    cp "$src_path" "$dest"
    echo "  $src_path -> $dest"
    count=$((count + 1))
  done
done <<<"$SYNC_MAP"

echo ""
echo "Synced $count files."
