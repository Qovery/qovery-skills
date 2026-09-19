## Phase 5b: Variables, Secrets & Interpolation (VS checks)

Configuration is where reliability and security meet. A credential in the wrong field is a
breach waiting for an audience; a hardcoded hostname is an environment clone that silently
talks to production.

Data sources: `env/<envId>/variables.json`, `env/<envId>/secret-keys.json`,
`env/<envId>/services.json`, `service/<id>/service.json`.

> **The hard rule, again.** `GET /environment/{envId}/environmentVariable` returns the
> `value` field. You need it for `VS-01`, `VS-03` and `VS-05`. **Never print a value, never
> quote one in the report, never paste one into the conversation.** Report the KEY, the
> SCOPE, and the CLASS of problem. Where a finding needs proof, give a fingerprint —
> "the same 44-character value appears under 3 keys" — never the value itself.

### Variable types

`variable_type` tells you how a variable is defined. The distribution is itself a finding:

| Type | Meaning | What you want to see |
|---|---|---|
| `VALUE` | A literal | Fine for genuine config; a problem when it duplicates another value |
| `ALIAS` | Points at another variable | Used for service-to-service wiring |
| `OVERRIDE` | Redefines an inherited variable at a narrower scope | Used sparingly, for real per-service differences |
| `BUILT_IN` | Qovery-provided (host, port, credentials of a Qovery database) | Should be the source of every internal connection detail |
| `FILE` | Mounted as a file | Check `mount_path` and `enable_interpolation_in_file` |
| `EXTERNAL_SECRET` / `FILE_EXTERNAL_SECRET` | Resolved from an external secret manager | The strongest posture — the value never lives in Qovery |

```bash
for d in raw/env/*/; do
  jq -r --arg m "$(jq -r .mode "$d/environment.json")" \
    '.results[]? | [$m, .variable_type, .scope] | @tsv' "$d/variables.json"
done | sort | uniq -c | sort -rn
```

---

### VS-01 — No credential-shaped **value** sits in a plain variable

**Severity:** Critical

`SC-08` catches credential-shaped *keys*. This catches the ones whose key looks innocent.
Match on the value, report only the key:

```bash
for d in raw/env/*/; do
  M=$(jq -r .mode "$d/environment.json")
  jq -r --arg m "$M" '.results[]? | select(.variable_type=="VALUE")
    | select(.value != null)
    | select(
        (.value|test("^(AKIA|ASIA)[0-9A-Z]{16}$"))                              # AWS key id
        or (.value|test("^eyJ[A-Za-z0-9_-]{8,}\\."))                            # JWT
        or (.value|test("-----BEGIN [A-Z ]*PRIVATE KEY-----"))                  # PEM
        or (.value|test("^(postgres|postgresql|mysql|mongodb|redis|amqp)s?://[^:@/]+:[^@]+@"))  # DSN with password
        or (.value|test("^gh[pousr]_[A-Za-z0-9]{20,}$"))                        # GitHub token
        or (.value|test("^xox[abprs]-"))                                        # Slack token
        or (.value|test("^sk-[A-Za-z0-9]{20,}$"))                               # API key
      )
    | [$m, .key, .scope, (.value|length|tostring) + "chars"] | @tsv' "$d/variables.json"
done | column -t
```

**Why it matters:** variables are readable by anyone with read access to the environment
and are shown in plain text in the Console. Secrets are write-only and masked. A live
credential in the variable list is disclosed to every viewer, every export, and every
screen-share.

**Recommendation:** move to a secret. Where an external secret manager is already in use,
prefer `EXTERNAL_SECRET` so the value never lives in Qovery at all.

---

### VS-02 — No secret material in Helm values, job arguments, or entrypoints

**Severity:** Critical

Secrets hide outside the variable list too:

```bash
jq -r '.results[]? | select(.service_type=="HELM")
  | [.name, (.values_override | tostring | .[0:160])] | @tsv' raw/env/<envId>/services.json

jq -r '.results[]? | select(.service_type=="JOB" or .service_type=="CONTAINER")
  | select((.arguments|length) > 0 or (.entrypoint // "") != "")
  | [.name, ((.arguments // []) | join(" ")), (.entrypoint // "")] | @tsv' raw/env/<envId>/services.json
```

Scan the output for the same value patterns as `VS-01`. Helm `values_override` in
particular is a common place for a database password to be pasted "just to get it working".

---

### VS-03 — The same value is not duplicated across keys or services

**Severity:** High

Compare values by **hash**, never by content:

```bash
for d in raw/env/*/; do
  N=$(jq -r .name "$d/environment.json")
  jq -r --arg n "$N" '.results[]? | select(.variable_type=="VALUE") | select(.value != null)
    | select((.value|length) > 8)
    | [$n, .key, .scope, (.service_name // "-"), (.value|@base64)] | @tsv' "$d/variables.json"
done | awk -F'\t' '{h[$5]=h[$5]" "$2"@"$4; c[$5]++} END {for(k in c) if(c[k]>1) print c[k]" occurrences:"h[k]}' \
  | sort -rn | head -20
```

The base64 is a grouping key only — **do not print column 5**, and do not decode it.

This groups by key and service and **drops the environment**, so it finds duplication
*within* a tier and misses the case that matters most — the same credential in production
and in staging. That is `VS-09`, in **Phase 5c**; run both.

**Why it matters:** a value defined in eleven places is rotated in nine of them. The other
two break at 3am, and the failure looks like an application bug.

**Recommendation:** define once at the highest scope that fits, then reference it with an
`ALIAS`.

---

### VS-04 — Overrides are used instead of re-declaring

**Severity:** Medium

```bash
jq -r '.results[]? | select(.variable_type=="OVERRIDE")
  | [.key, .scope, (.service_name // "-"),
     (.overridden_variable.scope // "?")] | @tsv' raw/env/<envId>/variables.json
```

**Fails when:** a service redefines an inherited key as a fresh `VALUE` rather than an
`OVERRIDE`. Both work; only the override records that it is a deliberate deviation and keeps
the link to the parent. A plain redeclaration is indistinguishable from a copy-paste
mistake, and it silently stops tracking the parent when that changes.

---

### VS-05 — Service-to-service wiring uses built-ins and interpolation, not literals

**Severity:** High

This is the check that decides whether cloning an environment actually works.

```bash
# Candidate literals — print the value, the environment and its mode:
for d in raw/env/*/; do
  M=$(jq -r .mode "$d/environment.json"); E=$(jq -r .name "$d/environment.json" | cut -c1-28)
  jq -r --arg m "$M" --arg e "$E" '.results[]? | select(.variable_type=="VALUE")
    | select(.value != null)
    | select(.value | test("\\.svc\\.cluster\\.local|\\.qovery\\.io|:[0-9]{2,5}/|^https?://"))
    | [$m, $e, .key, .scope, (.service_name // "-"), (.value|.[0:60])] | @tsv' "$d/variables.json"
done | column -t -s$'\t'

# Clone-safety mechanisms already in use:
for d in raw/env/*/; do jq -r '.results[]? | select(.variable_type=="ALIAS") | .key' "$d/variables.json"; done | wc -l
for d in raw/env/*/; do jq -r '.results[]? | select(.value != null) | select(.value|test("\\{\\{")) | .key' "$d/variables.json"; done | wc -l
```

**The regex produces candidates, not findings — always print the value and classify it.**
`^https?://` matches every absolute URL, and most organizations legitimately hold third-party
endpoints (payment, telephony, object storage) as literals. A literal is only a finding when
the host belongs to *this* organization — another of its own services, a cluster-internal
name, or a Qovery-generated domain. Compare each host against the service and custom-domain
inventory from Phase 1 before reporting it; an unclassified dump of URL-shaped values is a
false finding waiting to happen.

**Zero interpolation is not by itself a failure.** `ALIAS` and `{{interpolation}}` are two
mechanisms for the same guarantee, and `ALIAS` alone is clone-safe — it is the more common
choice. Read the two counts together: many aliases and no interpolation is a healthy
organization that simply never needed to compose a value. Only a low alias count *alongside*
org-owned literals indicates wiring that will not survive a clone.

**Fails when:** a literal naming an org-owned host or database is set as `VALUE` where
Qovery exposes it as a `BUILT_IN`.

**Weight `PREVIEW` and cloned environments highest.** A literal defined at `ENVIRONMENT`
scope in a blueprint is copied into every environment cloned from it, so one variable can
appear in every open pull request — each preview silently addressing the shared parent
instead of its own clone. Count the environments a single literal reaches and report that
number; it is what turns a one-line variable into the finding's real severity.

**Why it matters:** a hardcoded host survives a clone and points the new environment at the
old one. In the best case the preview environment reads production's database; in the worst
case it writes to it. It is also why `TP-06` staging parity drifts — the literals get
updated in one environment and not the other.

**Grade the blast radius, do not flatten it.** A frontend URL pointing previews at the shared
development API is a correctness and confidence problem; a database host or credential
pointing them at production is a data-integrity one. Both are `VS-05`, and saying which is
which is what makes the finding actionable.

**Recommendation:** `ALIAS` the built-in (`QOVERY_...HOST`, `..._PORT`, `..._USERNAME`) and,
where a full URL must be assembled, compose it with `{{interpolation}}` so every clone
rewires itself.

---

### VS-06 — Variables sit at the highest scope that fits

**Severity:** Medium

```bash
jq -r '.results[]? | [.key, .scope] | @tsv' raw/env/<envId>/variables.json \
  | sort | awk -F'\t' '{k[$1]=k[$1]" "$2; c[$1]++} END{for(x in c) if(c[x]>1) print c[x], x, k[x]}' \
  | sort -rn | head -15
```

**Fails when:** the same key is declared separately on many services instead of once at
`ENVIRONMENT` or `PROJECT` scope. Pairs with `VS-03`; report them together.

---

### VS-07 — An external secret manager is used where the obligation requires it

**Severity:** Medium (High under a compliance obligation)

```bash
jq -r '.results[]? | select(.variable_type=="EXTERNAL_SECRET" or .variable_type=="FILE_EXTERNAL_SECRET")
  | [.key, .scope, (.owned_by // "-")] | @tsv' raw/env/<envId>/variables.json raw/env/<envId>/secret-keys.json
jq -r '.results[]? | .owned_by' raw/env/<envId>/secret-keys.json 2>/dev/null | sort | uniq -c
```

**Why it matters:** `owned_by` names the system of record — `Qovery`, `Doppler`, a vault. An
organization under SOC 2 or financial-services supervision is usually expected to hold
secrets in one auditable place with rotation and access logging. Storing them in Qovery is
supported and safe; storing them in *two* places without a system of record is the finding.

---

### VS-08 — File-mounted variables are deliberate

**Severity:** Medium

```bash
jq -r '.results[]? | select(.variable_type=="FILE" or .variable_type=="FILE_EXTERNAL_SECRET")
  | [.key, .mount_path, (.enable_interpolation_in_file|tostring), .scope] | @tsv' \
  raw/env/<envId>/variables.json | column -t
```

**Check:** that `mount_path` does not land inside a directory the application also writes,
and that `enable_interpolation_in_file` is on where the file contains `{{...}}` — a template
mounted without interpolation ships the literal braces to the application, which usually
fails in a confusing way at runtime rather than at deploy time.
