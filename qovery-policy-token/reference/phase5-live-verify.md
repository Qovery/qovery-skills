# Phase 5 — Live Verification

Prove the freshly-created token behaves against the real API exactly as the local matrix predicted. This closes the loop on "verify the policy does exactly what the user expects" — the local OPA pass (Phase 3) checks the policy logic; this checks that Qovery evaluates it the same way end-to-end.

## 5.1 Why deny-testing is safe and allow-destructive-testing is not

Qovery evaluates the policy **at authentication time, before the request reaches its endpoint.** A denied request returns `401` and **never executes** — so it is completely safe to fire a real `DELETE`, `POST`, or any mutating request that the policy should block: the resource is never touched. This lets us live-verify the entire deny-list for real.

The opposite is not safe. An *allowed* mutating request (deploy, delete, scale, update) **will execute** if the policy permits it. So the live test:

- **Runs every DENY case live** — expect HTTP `401`.
- **Runs non-destructive ALLOW cases live** — `GET`/`HEAD` reads the policy should permit; expect `2xx`.
- **Does NOT auto-run destructive ALLOW cases** — a `POST deploy`, `DELETE`, `PUT`, etc. that the policy allows. These were already verified statically in Phase 3. The harness lists them as "verified statically; run manually to confirm end-to-end" and only executes one if the user explicitly opts in for that specific action.

## 5.2 Run the live verification

`live-verify.sh` reads the same `test-matrix.json` from Phase 3 (the `live` block on each case) and the token from an env var (never a CLI arg, so it doesn't land in shell history):

```bash
# Capture the token inline into an env var the agent does not print (set by create-policy-token.sh,
# or sourced from the user's secure env file). Then:
bash templates/scripts/live-verify.sh test-matrix.json
```

For each case the script:
1. Builds the request from the `live` block: `{method, path, body?, destructive}`.
2. **Deny case** (`expect: false`): sends it, asserts HTTP `401` (blocked at auth, never executed). PASS if `401`.
3. **Allow + non-destructive** (`expect: true`, `destructive: false`): sends it, asserts `2xx`. PASS if `2xx`.
4. **Allow + destructive** (`expect: true`, `destructive: true`): **skips execution**, marks `SKIPPED (static-only)`, and reminds that Phase 3 already proved the allow decision. Runs it only if the user passed `--run-destructive` and confirmed that specific action.

It uses `Authorization: Token $POLICY_TOKEN` (the policy token, not the admin token) plus the standard `User-Agent` header, and prints a report table.

Example:

```
CASE                              KIND              EXPECT  STATUS  RESULT
read staging env                  allow/read        2xx     200     PASS
deploy api service                allow/destructive  —       —      SKIPPED (verified statically)
delete api service                deny              401     401     PASS
write to production               deny              401     401     PASS
read other environment            deny              401     401     PASS

4/4 executable checks passed, 1 skipped (destructive allow)
```

## 5.3 Interpreting results

- **A deny case returns something other than `401`** (e.g. `200`, `403`, `404`) → the policy is NOT blocking it the way the user wants. This is a real failure: the policy is too permissive (or the request didn't resolve the metadata you assumed). Revisit Phase 2, delete this token (Phase 6), fix, and recreate. Do **not** hand over a token that failed a deny check.
- **An allow/read case returns `401`** → the policy is too restrictive; the token can't do what the user needs. Same remediation: fix and recreate.
- **A `404` on an allow case** usually means a wrong path/UUID in the matrix, not a policy problem — fix the matrix and re-run.
- **Destructive allow cases** remain SKIPPED unless the user opts in. If they want full end-to-end proof of, say, a deploy, run that one action with their confirmation and confirm the deploy started.

## 5.4 Report

Summarize for the user: the token allows exactly the confirmed allow-list (reads verified live, destructive actions verified statically) and denies the confirmed deny-list (verified live at `401`). Only after this passes, proceed to Phase 6 to hand over the token. If anything failed, treat the token as unusable — revoke it and iterate.
