#!/usr/bin/env bash
#
# service-graph.sh — derive the service graph of one environment from the snapshot.
#
# Usage:  ./service-graph.sh <snapshotDir> [environmentName]
#
# Qovery encodes wiring in two places:
#   * BUILT_IN variables — QOVERY_<TYPE>_<ID>_HOST[_INTERNAL|_EXTERNAL] — name the TARGET
#     service, and carry .service_name, so an ID resolves to a real name.
#   * ALIAS variables — an alias whose .aliased_variable.key is one of those built-ins is a
#     caller-side reference to that target. RAW_API_URL -> QOVERY_APPLICATION_Zxxx_HOST_EXTERNAL
#     means "something here calls vocca-api".
#
# HONEST LIMIT, and it must survive into the diagram caption: aliases declared at ENVIRONMENT
# or PROJECT scope are visible to every service in the environment, so they prove that
# something in the environment calls the target — not which caller. Only a SERVICE-scoped
# variable attributes an edge to one service. The script says which kind it found.

set -uo pipefail
DIR="${1:-.}"; WANT="${2:-}"
[ -d "$DIR/raw/env" ] || { echo "ERROR: $DIR/raw/env not found" >&2; exit 1; }

# The collector stores a failed endpoint as {"_unreadable":true,"_status":<code>}. Its
# missing `.results` reads as an empty list in every jq filter below, which would draw a
# confident, empty graph and report "0 SERVICE-scoped variables" — a stated fact where
# there is no data. Nothing here may run against an unreadable file.
unreadable() { [ ! -f "$1" ] || jq -e '._unreadable // false' "$1" >/dev/null 2>&1; }

for d in "$DIR"/raw/env/*/; do
  [ -f "$d/environment.json" ] || continue
  E=$(jq -r '.name // "?"' "$d/environment.json")
  [ -n "$WANT" ] && [ "$E" != "$WANT" ] && continue
  M=$(jq -r '.mode // "?"' "$d/environment.json")
  echo "=============================================================="
  echo "ENVIRONMENT  $E  ($M)"
  echo "=============================================================="

  if unreadable "$d/services.json"; then
    echo "   UNKNOWN — services.json is unreadable for this environment (HTTP $(jq -r '._status // "?"' "$d/services.json" 2>/dev/null))."
    echo "   No graph is drawn: an empty one would read as \"no services\" rather than \"not read\"."
    echo ""
    continue
  fi

  echo "-- entry points (publicly routed) --"
  jq -r '.results[]? | . as $s | ($s.ports[]? | select(.publicly_accessible==true))
    | "   PUBLIC  \($s.name)  :\(.internal_port)->\(.external_port // 443)"' "$d/services.json" | sort -u

  echo "-- datastores --"
  jq -r '.results[]? | select(.service_type=="DATABASE")
    | "   \(.mode)  \(.name)  \(.type) \(.version // "")  accessibility=\(.accessibility)  encrypted=\(if has("disk_encrypted") then (.disk_encrypted|tostring) else "?" end)"' \
    "$d/services.json" | sort

  if unreadable "$d/variables.json"; then
    echo "-- targets referenced by an alias --"
    echo "   UNKNOWN — variables.json is unreadable, so no edge can be derived or"
    echo "   attributed. Mark the diagram's edges as unverified rather than absent."
    echo ""
    continue
  fi

  echo "-- targets referenced by an alias (something in this env calls these) --"
  jq -r --slurpfile v "$d/variables.json" '
    ($v[0].results // []) as $all
    | ($all | map(select(.variable_type=="BUILT_IN" and (.key|test("_HOST(_INTERNAL|_EXTERNAL)?$"))))
            | map({key:.key, svc:(.service_name // "?"), typ:(.service_type // "?")})) as $builtins
    | ($all | map(select(.variable_type=="ALIAS" and (.aliased_variable.key // "" | test("^QOVERY_"))))) as $aliases
    | $aliases[]
    | . as $a
    | ($builtins[] | select(.key == $a.aliased_variable.key)) as $t
    | "   \(if $a.scope == "SERVICE" then "\($a.service_name // "?") " else "\($a.scope)-scope " end)  \($a.key)  ->  \($t.svc)  [\($t.typ)]  via \(if ($a.aliased_variable.key|test("_EXTERNAL$")) then "public URL" else "cluster-internal DNS" end)"
    ' "$d/variables.json" 2>/dev/null | sort -u

  echo "-- edge attribution --"
  # Only a SERVICE-scoped ALIAS that resolves to a QOVERY_*_HOST built-in attributes an edge
  # to one caller. A SERVICE-scoped VALUE or BUILT_IN is just a per-service setting and says
  # nothing about who calls whom, so counting those claimed attribution that does not exist.
  n=$(jq -r '[.results[]? | select(.scope=="SERVICE")
              | select(.variable_type=="ALIAS")
              | select((.aliased_variable.key // "") | test("^QOVERY_.*_HOST(_INTERNAL|_EXTERNAL)?$"))]
             | length' "$d/variables.json")
  if [ "${n:-0}" -gt 0 ]; then
    echo "   $n SERVICE-scoped host aliases — per-service edges ARE derivable; attribute them."
  else
    echo "   0 SERVICE-scoped host aliases — edges are environment-wide."
    echo "   Draw the shape, and caption it: these prove that something in the environment"
    echo "   calls each target, NOT which caller. Do not present an arrow as a proven call."
  fi

  echo "-- third-party processors referenced (from key names) --"
  jq -r '.results[]?.key' "$d/variables.json" "$d/secret-keys.json" 2>/dev/null \
    | sed -E 's/^(VITE|NEXT_PUBLIC)_//' | sed -E 's/_.*$//' \
    | grep -vE '^(QOVERY|API|RAW|ADMIN|INTERNAL|DASHBOARD|PATIENT|STAGING|DATABASE|DB|REDIS|SECRET|JWT|AGENT|MCP|TS|ENVIRONMENT|NODE|PORT|LOG|NEXT|VITE)$' \
    | sort -u | tr '\n' ' ' | sed 's/^/   /'
  echo; echo
done
