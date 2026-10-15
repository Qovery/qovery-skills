#!/usr/bin/env bash
# Offline installer checks: no tracking endpoint or release downloads are contacted.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/assets"
cat > "$TEST_ROOT/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$TEST_CURL_LOG"
[ "$1" = --disable ] || exit 91
out= url=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; https:*) url=$1 ;; esac
  shift
done
[ -n "$out" ] && [ -n "$url" ] || exit 92
cp "$TEST_ASSETS/${url##*/}" "$out"
CURL
chmod +x "$TEST_ROOT/bin/curl"
export TEST_CURL_LOG="$TEST_ROOT/curl.log" TEST_ASSETS="$TEST_ROOT/assets"
export PATH="$TEST_ROOT/bin:$PATH"
cd "$ROOT"
case "$(uname -s):$(uname -m)" in
 Linux:x86_64) platform=x86_64-unknown-linux-musl ;;
 Linux:aarch64|Linux:arm64) platform=aarch64-unknown-linux-musl ;;
 Darwin:x86_64) platform=x86_64-apple-darwin ;;
 Darwin:arm64) platform=aarch64-apple-darwin ;;
 *) echo 'Unsupported native smoke platform'; exit 1 ;;
esac
asset="$TEST_ASSETS/skill-run-$platform"
printf '#!/usr/bin/env bash\n[ "$1" = --version ] || exit 99\necho "skill-run 0.1.0"\n' > "$asset"
chmod +x "$asset"
shasum -a 256 "$asset" > "$asset.sha256"
run_install() {
  env HOME="$TEST_ROOT/$1" bash ./install.sh --global > "$TEST_ROOT/$1.log"
}
run_install download
[ "$(wc -l < "$TEST_CURL_LOG" | tr -d ' ')" = 2 ]
for base in .claude/skills .agents/skills .config/opencode/skills; do
  for skill in qovery qovery-*/; do
    skill=${skill%/}
    cmp "$asset" "$TEST_ROOT/download/$base/$skill/scripts/skill-run"
  done
done
QOVERY_SKILLS_NO_TRACKING=true run_install optout
[ ! -e "$TEST_ROOT/optout/.claude/skills/qovery-deploy/scripts/skill-run" ]
[ "$(wc -l < "$TEST_CURL_LOG" | tr -d ' ')" = 2 ]
printf '%064d\n' 0 > "$asset.sha256"
run_install corrupt
[ ! -e "$TEST_ROOT/corrupt/.claude/skills/qovery-deploy/scripts/skill-run" ]
grep -q 'checksum mismatch' "$TEST_ROOT/corrupt.log"
rm "$asset"
run_install missing
[ ! -e "$TEST_ROOT/missing/.claude/skills/qovery-deploy/scripts/skill-run" ]
QOVERY_SKILLS_TRACKING_BINARY=relative run_install invalid
[ ! -e "$TEST_ROOT/invalid/.claude/skills/qovery-deploy/scripts/skill-run" ]
cat > "$TEST_ROOT/bin/uname" <<'UNAME'
#!/usr/bin/env bash
case "$1" in -s) echo UnsupportedOS ;; -m) echo unsupported ;; esac
UNAME
chmod +x "$TEST_ROOT/bin/uname"
run_install unsupported
[ ! -e "$TEST_ROOT/unsupported/.claude/skills/qovery-deploy/scripts/skill-run" ]
grep -q 'unsupported platform' "$TEST_ROOT/unsupported.log"
rm "$TEST_ROOT/bin/uname"
real_binary="$ROOT/tracking/target/debug/skill-run"
if [ -x "$real_binary" ]; then
  QOVERY_SKILLS_TRACKING_BINARY="$real_binary" run_install native
  cmp "$real_binary" "$TEST_ROOT/native/.claude/skills/qovery-deploy/scripts/skill-run"
else
  echo 'Native binary smoke skipped: cargo build --manifest-path tracking/Cargo.toml first.'
fi
echo 'Offline installer checks passed.'
