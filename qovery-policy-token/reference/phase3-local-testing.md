# Phase 3 — Local Pre-flight Testing with OPA

Prove the policy does exactly what the user expects **before** creating the token. Because policies are immutable, this is the cheapest place to catch a mistake — a wrong rule here costs one edit; a wrong rule after creation costs a delete + recreate.

Qovery has **no server-side simulate endpoint**, so local testing uses the same OPA engine Qovery runs (OPA 1.19), evaluating the policy against synthetic `input` documents that mirror real requests.

## 3.1 Check for OPA (best-effort)

```bash
opa version    # expect 1.19.x (the version Qovery runs)
```

If OPA is missing, offer to install it, or skip to Phase 5 live verification:

```bash
# macOS
brew install opa
# Linux (x86_64)
curl -L -o /usr/local/bin/opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64_static && chmod +x /usr/local/bin/opa
```

If the user declines to install OPA, note in the plan that the policy could not be statically verified and that Phase 5 (live) will do the DENY checks and safe ALLOW checks instead — but static verification of *destructive allowed* actions won't be possible, so extra care is warranted before granting them.

## 3.2 Build the allow/deny test matrix

The matrix is the Phase 1 allow-list + deny-list turned into concrete `input` documents, each with an expected boolean. Copy `templates/test-matrix.example.json` and edit it. Each case:

```json
{
  "name": "read staging env (allow)",
  "expect": true,
  "live": { "method": "GET", "path": "/environment/<ENV_UUID>/service", "destructive": false },
  "input": {
    "request": { "method": "GET", "path": ["api", "environment", "<ENV_UUID>", "service"], "body": null },
    "qovery_metadata": {
      "organization_id": "<ORG_UUID>", "environment_id": "<ENV_UUID>",
      "project_id": "<PROJ_UUID>", "service_id": null, "service_type": null, "cluster_id": "<CLUSTER_UUID>"
    },
    "token": { "id": "00000000-0000-0000-0000-000000000000", "name": "preflight" }
  }
}
```

Cover, at minimum:
- **One allow case per rule** the user asked for (expect `true`).
- **One deny case per item on the deny-list** — e.g. a `DELETE` on the allowed service, a write to another environment, a read of a different env (expect `false`).
- **Boundary cases** the user cares about — the exact thing that must never happen. If the user said "never delete", include a `DELETE` that targets the *allowed* service and assert it's denied.

A policy that passes its allow cases but has no deny cases is not verified — the deny cases are what prove it isn't over-broad.

## 3.3 Run the pre-flight

```bash
bash templates/scripts/opa-preflight.sh policy.rego test-matrix.json
```

The script (`templates/scripts/opa-preflight.sh`):
1. Runs `opa check` on the policy (syntax/compile — the same class of error the API returns as `400`).
2. Prepends a temporary `package qovery.policy` to a scratch copy so `opa eval` can address the rule (the submitted `opa_policy` must NOT contain a package line — the create step uses the original file).
3. For each matrix case, runs `opa eval -d <scratch> -i <case-input> --format raw 'data.qovery.policy.allow'` and compares the boolean to `expect`.
4. Prints a pass/fail table and exits non-zero if any case fails.

Example output:

```
CASE                                  EXPECT  ACTUAL  RESULT
read staging env (allow)              true    true    PASS
deploy api service (allow)            true    true    PASS
delete api service (deny)             false   false   PASS
write to production (deny)            false   false   PASS
read other environment (deny)        false   false   PASS

5/5 passed
```

## 3.4 Iterate until green

If any case fails, the policy is wrong — fix the Rego (Phase 2) and re-run. Do **not** proceed to Phase 4 with a red matrix. Common fixes:
- Allow case failing → the rule's condition is too strict or references a wrong UUID.
- Deny case passing as allow → a rule is broader than intended (e.g. an unscoped `GET`); tighten it.

Once the matrix is fully green and the user has confirmed the policy (Phase 2.5), continue to Phase 4. Keep `policy.rego` and `test-matrix.json` — Phase 5 reuses the same matrix for live verification.
