#!/usr/bin/env bash
# bulk-provision.sh — Provision multiple builder environments from CSV
# Usage: ./bulk-provision.sh builders.csv
#
# CSV format: name,email,team
# Example:
#   alice,alice@company.com,sales
#   bob,bob@company.com,finance
#   carol,carol@company.com,ops

set -euo pipefail

CSV_FILE="${1:?Usage: $0 <builders.csv>}"
SCRIPT_DIR="$(dirname "$0")"

echo "Bulk provisioning from: $CSV_FILE"
echo ""

count=0
while IFS=, read -r name email team; do
  # Skip header row if present
  [[ "$name" == "name" ]] && continue
  # Skip empty lines
  [[ -z "$name" ]] && continue

  count=$((count + 1))
  echo "--- Builder $count: $name ---"
  "$SCRIPT_DIR/provision-builder.sh" "$name" "$email" "$team"
  echo ""
done < "$CSV_FILE"

echo "========================================="
echo "Bulk provisioning complete: $count builders provisioned."
echo "========================================="
