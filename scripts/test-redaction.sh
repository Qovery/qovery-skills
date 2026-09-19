#!/usr/bin/env bash
#
# test-redaction.sh — regression test for the qovery-assess log/event redaction filter.
#
# It sources redact_log() and redact_events() out of the collector itself rather than
# copying them, so the test cannot drift from the thing it guards.
#
# Usage: ./scripts/test-redaction.sh
#
set -uo pipefail

SRC="$(dirname "$0")/../qovery-assess/templates/scripts/collect-snapshot.sh"
[ -f "$SRC" ] || { echo "ERROR: cannot find $SRC" >&2; exit 1; }

eval "$(awk '/^redact_log\(\)/,/^}/'    "$SRC")"
eval "$(awk '/^redact_events\(\)/,/^}/' "$SRC")"

fail=0

# leaks <name> <input> <string-that-must-not-survive> [filter]
leaks() {
  local out; out=$(printf '%s\n' "$2" | "${4:-redact_log}")
  if printf '%s' "$out" | grep -qF -- "$3"; then
    printf 'FAIL  %s\n      leaked: %s\n' "$1" "$out"; fail=1
  else
    printf 'ok    %s\n' "$1"
  fi
}

# keeps <name> <input> <string-that-must-survive> [filter]
keeps() {
  local out; out=$(printf '%s\n' "$2" | "${4:-redact_log}")
  if printf '%s' "$out" | grep -qF -- "$3"; then
    printf 'ok    %s (preserved)\n' "$1"
  else
    printf 'FAIL  %s\n      over-redacted: %s\n' "$1" "$out"; fail=1
  fi
}

echo "Credential classes — none of these may survive the filter:"
leaks "AWS access key id"      'key=AKIAIOSFODNN7EXAMPLE'                              'AKIAIOSFODNN7EXAMPLE'
leaks "JWT"                    'tok eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghij'   'eyJzdWIiOiIxIn0'
leaks "GitHub token"           'ghp_abcdefghijklmnopqrstuvwxyz0123'                    'ghp_abcdefghijklmnopqrstuvwxyz0123'
leaks "DSN password"           'postgres://user:s3cretpw@db:5432/x'                    's3cretpw'
leaks "bearer header"          'Authorization: Bearer abcdefghijklmnopqrst'            'abcdefghijklmnopqrst'
leaks "Slack token"            'xoxb-1234567890-abcdefghij'                            'xoxb-1234567890-abcdefghij'
leaks "PEM private key"        '-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAsecret
-----END RSA PRIVATE KEY-----'                                                          'MIIEowIBAAKCAQEAsecret'
leaks "unquoted password"      'password=hunter2hunter2'                               'hunter2hunter2'

echo
echo "JSON forms — every payload this filter guards is JSON, so these are the ones that matter:"
leaks "JSON password field"    '{"password": "hunter2hunter2"}'                        'hunter2hunter2'
leaks "JSON api key field"     '{"Api_Key":"abcdef1234567890"}'                        'abcdef1234567890'
leaks "escaped JSON password"  '{"change":"{\"password\":\"hunter2hunter2\"}"}'        'hunter2hunter2'
leaks "event change value"     '{"key":"DB_PASSWORD","value":"sup3rS3cretValue"}'      'sup3rS3cretValue' redact_events

echo
echo "Negative cases — these must survive, or findings lose their evidence:"
keeps "Secrets Manager ARN is a reference, not a credential" \
      'arn:aws:secretsmanager:eu-west-3:1:secret:prod/db'    'ARN:secretsmanager'
keeps "ordinary log line"      'service billing-api status DEPLOYED region eu-west-3'  'eu-west-3'
keeps "value below the length floor" '{"api_key":"short"}'                             'short'

echo
if [ "$fail" -eq 0 ]; then echo "All redaction cases pass."; else echo "REDACTION TEST FAILED."; fi
exit "$fail"
