#!/usr/bin/env bash
#
# cross-env-secrets.sh — detect values shared between environments (VS-09).
#
# Reads a snapshot directory produced by collect-snapshot.sh and groups plain
# variables by a SHA-256 of their value. Two variables in different environments
# with the same hash hold the same value.
#
# NO VALUE IS EVER PRINTED. The hash is a grouping key and is truncated to 12 hex
# characters so it cannot be used to confirm a guessed value offline.
#
# Usage:  ./cross-env-secrets.sh <snapshotDir>
#
# Only plain variables can be compared. Qovery never returns a secret's value, so
# secrets are invisible to this method — say so in the report rather than implying
# the properly-stored secrets were checked and found clean.

set -uo pipefail
DIR="${1:-.}"
[ -d "$DIR/raw/env" ] || { echo "ERROR: $DIR/raw/env not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 required" >&2; exit 1; }

python3 - "$DIR" <<'ENDOFPY'
import json, glob, hashlib, collections, sys, os
root = sys.argv[1]

# Values that are shared legitimately: identifiers, endpoints, versions, region names.
# Sharing these across environments is correct, not a finding.
IDENTIFIER = (
    "_SID", "_ID", "_IDS", "_URL", "_URI", "_HOST", "_ENDPOINT", "_REGION",
    "_VERSION", "_NAME", "_POOL", "_RELEASE", "_PHONE", "_PHONE_NUMBER",
    "_BUCKET", "_ACCOUNT", "_PROJECT", "_DOMAIN", "_PORT", "_ARN", "_ZONE",
    "_TRUNK", "_ADDRESS", "_BUNDLE", "_VOICE", "_MODEL", "_TIMEOUT", "_LOCALE",
)
# Keys are often suffixed with a region or tier — LIVEKIT_URL_EU, TWILIO_TRUNK_SID_US.
# Strip those before testing the real suffix, or every one is misread as a credential.
TIER = ("_EU", "_US", "_FR", "_UK", "_DE", "_APAC", "_PROD", "_PRODUCTION",
        "_STAGING", "_STAGE", "_PREPROD", "_DEV", "_DEVELOPMENT", "_TEST", "_SANDBOX")

def canon(key):
    k = key.upper()
    changed = True
    while changed:                      # LIVEKIT_SIP_TRUNK_ID_EU -> ..._ID
        changed = False
        for t in TIER:
            if k.endswith(t) and len(k) > len(t):
                k = k[: -len(t)]; changed = True
        while k and k[-1].isdigit():
            k = k[:-1]; changed = True
        k = k.rstrip("_")
    return k
rows = []
for d in sorted(glob.glob(os.path.join(root, "raw/env/*/"))):
    try:
        env = json.load(open(d + "environment.json"))
        vs = json.load(open(d + "variables.json")).get("results", [])
    except Exception:
        continue
    for v in vs:
        val = v.get("value")
        if not val or v.get("variable_type") != "VALUE":
            continue
        if len(val) < 12:                      # placeholders, flags, short config
            continue
        if val.startswith(("http://", "https://")):   # URLs are not credentials
            continue
        if val.replace(".", "").replace("-", "").replace(" ", "").isdigit():
            continue
        rows.append((hashlib.sha256(val.encode()).hexdigest()[:12],
                     env["name"], env.get("mode", "?"), v["key"], len(val)))

groups = collections.defaultdict(list)
for h, n, m, k, l in rows:
    groups[h].append((n, m, k, l))

def looks_like_identifier(keys):
    return all(any(canon(k).endswith(sfx) for sfx in IDENTIFIER) for k in keys)

cred, ident = [], []
for h, items in groups.items():
    envs = {i[0] for i in items}
    if len(envs) < 2:
        continue
    keys = {i[2] for i in items}
    (ident if looks_like_identifier(keys) else cred).append((h, items, envs))

print("=== Shared across environments — CREDENTIAL-SHAPED (triage each) ===")
if not cred:
    print("  none")
for h, items, envs in sorted(cred, key=lambda x: -len(x[1])):
    modes = {i[1] for i in items}
    flag = "   *** PRODUCTION + NON-PRODUCTION ***" if "PRODUCTION" in modes and len(modes) > 1 else ""
    print(f"\n  value#{h}  len={items[0][3]}  envs={sorted(envs)}{flag}")
    for n, m, k, l in sorted(items):
        print(f"      {n:<20} {k}")

print("\n=== Shared across environments — identifier-shaped (usually correct) ===")
print(f"  {len(ident)} value(s): " + ", ".join(sorted({k for _, items, _ in ident for _, _, k, _ in items})))

print("\n=== Same value under different keys WITHIN one environment ===")
found = False
for h, items in groups.items():
    per = collections.defaultdict(set)
    for n, m, k, l in items:
        per[n].add(k)
    for n, keys in per.items():
        if len(keys) > 1:
            found = True
            print(f"  {n}: value#{h} used as {sorted(keys)}")
if not found:
    print("  none")
ENDOFPY
