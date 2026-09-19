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
import json, glob, hashlib, collections, sys, os, re
root = sys.argv[1]

# Values that are shared legitimately: identifiers, endpoints, versions, region names.
# Sharing these across environments is correct, not a finding.
IDENTIFIER = (
    "_SID", "_ID", "_IDS", "_URL", "_URI", "_HOST", "_ENDPOINT", "_REGION",
    "_VERSION", "_NAME", "_POOL", "_RELEASE", "_PHONE", "_PHONE_NUMBER",
    "_BUCKET", "_ACCOUNT", "_PROJECT", "_DOMAIN", "_PORT", "_ARN", "_ZONE",
    "_TRUNK", "_ADDRESS", "_ADDRESSES", "_BUNDLE", "_VOICE", "_MODEL", "_TIMEOUT",
    "_LOCALE", "_SELECTOR", "_CLASS_ID", "_INVESTOR_ID", "_CHAIN", "_NETWORK", "_USERNAME",
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
PUBLIC_KEY_NAME = re.compile(
    r"ADDRESS|CONTRACT|SELECTOR|CHAIN_?ID|BLOCK|TX_?HASH|ACCOUNT_?ID|PROJECT_?ID|TENANT_?ID",
    re.I)


def is_public_identifier(val, key=""):
    """Values that are public by construction — but only where the KEY agrees.

    On-chain addresses are the common false positive in fintech estates: an ERC-20
    contract address is 0x + 40 hex, it is published on a block explorer, and keys like
    LINK_TOKEN_ADDRESS or CHAINLINK_TOKEN_POOL_ADDRESSES read as credentials to a
    name-based filter. Reporting them as shared secrets destroys trust in the real ones.

    The shapes below are ambiguous in both directions, which is why the key name has to
    agree before anything is dropped:

      * 0x + 64 hex is a transaction hash. It is ALSO the exact shape of an EVM private
        key, a 32-byte HMAC secret, and a hex-encoded signing key. Dropping it on shape
        alone is a silent blind spot in exactly the estates this script was written for.
      * a 15-25 digit run is a chain selector or a numeric account id. It is ALSO the
        shape of a numeric API token or a PIN.

    A 40-hex EVM address is the one case narrow enough to drop on shape alone: it is too
    short to be a modern key and it is derived from a public key by construction.
    """
    v = val.strip()
    if re.fullmatch(r"0x[0-9a-fA-F]{40}", v):          # EVM address — public by construction
        return True
    if re.fullmatch(r"0x[0-9a-fA-F]{64}", v):          # tx hash OR 32-byte key
        return bool(PUBLIC_KEY_NAME.search(key))
    if re.fullmatch(r"[0-9]{15,25}", v):               # chain selector OR numeric token
        return bool(PUBLIC_KEY_NAME.search(key))
    return False


def url_carries_a_secret(val):
    """A URL is not a credential — unless it embeds one."""
    return bool(re.search(r"://[^/@\s]*:[^/@\s]*@", val)      # user:pass@host
                or re.search(r"[?&](token|key|secret|sig|signature|password|access_token)=", val, re.I))

rows, unreadable = [], []
for d in sorted(glob.glob(os.path.join(root, "raw/env/*/"))):
    env_id = os.path.basename(d.rstrip("/"))       # the directory name IS the environment id
    try:
        env = json.load(open(d + "environment.json"))
        varsdoc = json.load(open(d + "variables.json"))
    except Exception:
        unreadable.append(env_id); continue
    if varsdoc.get("_unreadable") or env.get("_unreadable"):
        unreadable.append(env.get("name", env_id)); continue
    vs = varsdoc.get("results", [])
    for v in vs:
        val = v.get("value")
        if not val or v.get("variable_type") != "VALUE":
            continue
        if len(val) < 12:                      # placeholders, flags, short config
            continue
        if val.startswith(("http://", "https://")) and not url_carries_a_secret(val):
            continue
        # Numeric-only values are usually ports, sizes or timeouts — but a long digit string
        # can be a PIN or numeric token, so only skip the short ones.
        if val.replace(".", "").replace("-", "").replace(" ", "").isdigit() and len(val) < 15:
            continue
        if is_public_identifier(val, v.get("key", "")):
            continue
        # Group by environment ID, not display name: two projects can hold environments with
        # the same name, and keying on the name would silently merge or hide their credentials.
        rows.append((hashlib.sha256(val.encode()).hexdigest()[:12],
                     env_id, env.get("name", env_id), env.get("mode", "?"), v["key"], len(val)))

groups = collections.defaultdict(list)
for h, eid, name, m, k, l in rows:
    groups[h].append((eid, name, m, k, l))

def looks_like_identifier(keys):
    return all(any(canon(k).endswith(sfx) for sfx in IDENTIFIER) for k in keys)

cred, ident = [], []
for h, items in groups.items():
    envs = {i[0] for i in items}          # environment IDs, not display names
    if len(envs) < 2:
        continue
    keys = {i[3] for i in items}
    (ident if looks_like_identifier(keys) else cred).append((h, items, envs))

if unreadable:
    print("!!! UNREADABLE — these environments were NOT compared, so a shared credential")
    print("!!! in them would not appear below. Do not read this output as clean:")
    for u in unreadable:
        print(f"      {u}")
    print()

print("=== Shared across environments — CREDENTIAL-SHAPED (triage each) ===")
if not cred:
    print("  none")
for h, items, envs in sorted(cred, key=lambda x: -len(x[1])):
    modes = {i[2] for i in items}
    flag = "   *** PRODUCTION + NON-PRODUCTION ***" if "PRODUCTION" in modes and len(modes) > 1 else ""
    print(f"\n  value#{h}  len={items[0][4]}  {len(envs)} environments{flag}")
    for eid, name, m, k, l in sorted(items, key=lambda i: (i[1], i[3])):
        print(f"      {name:<24} [{m:<11}] {k}")

print("\n=== Shared across environments — identifier-shaped (usually correct) ===")
print(f"  {len(ident)} value(s): " + ", ".join(sorted({k for _, items, _ in ident for _, _, _, k, _ in items})))

print("\n=== Same value under different keys WITHIN one environment ===")
found = False
for h, items in groups.items():
    per = collections.defaultdict(set)
    for eid, name, m, k, l in items:
        per[name].add(k)
    for name, keys in per.items():
        if len(keys) > 1:
            found = True
            print(f"  {name}: value#{h} used as {sorted(keys)}")
if not found:
    print("  none")
ENDOFPY
