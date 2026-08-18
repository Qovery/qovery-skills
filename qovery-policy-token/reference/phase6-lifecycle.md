# Phase 6 — Deliver the Token and Manage its Lifecycle

The policy is verified and the token works. Hand it over correctly and make sure the user knows how to operate it — it can't be retrieved again, and its policy can't be edited.

## 6.1 Deliver the token once

The token value was shown only in the create response and can never be fetched again. Deliver it to the user through a channel the agent does not print into the conversation:

- Prefer having `create-policy-token.sh` write it to a user-controlled secure location (e.g. a gitignored `.env` the agent does not read back), and tell the user where it is.
- If you must reference it, use `***` — never the real value.
- Remind the user to store it in their secret manager / CI secret store immediately, and that Qovery cannot recover it if lost (they'd delete and recreate).

Give them the non-secret facts to keep:
- token `id` (UUID) — needed to revoke
- `name`, `description`, and `expires_at` (if set)
- how the token is used: `Authorization: Token <the-secret>`

## 6.2 Immutability — how to "change" a policy

There is **no update endpoint**. To change what the token can do, delete it and create a new one (rerun Phases 2–5). Set expectations: this means rotating the secret too, so anywhere the old token is configured must be updated.

## 6.3 List policy tokens

```bash
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-policy-token (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization/${QOVERY_ORG_ID}/policyApiToken" \
  | jq '.results[] | {id, name, description, expires_at}'
```

The list returns each token's `opa_policy` (so you can review what a token allows) but **never** the token value.

## 6.4 Revoke a policy token

Revocation is immediate (no caching) — the token stops working on the next request.

```bash
curl -s -X DELETE \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-policy-token (version:$(cat _version.txt 2>/dev/null || echo unknown); https://github.com/Qovery/qovery-skills)" \
  "https://api.qovery.com/organization/${QOVERY_ORG_ID}/policyApiToken/${POLICY_TOKEN_ID}"
```

Use this to: fix a policy (delete + recreate), retire an agent, or respond to a suspected leak. If you created a **test** token during verification, revoke it here as cleanup.

## 6.5 Audit trail

Actions taken with a policy token are attributed in the Qovery audit log as `policy:<token-id>:<token-name>`. Tell the user this so they can trace what the token did — and pick a descriptive `name` at creation time (Phase 4) precisely so the audit log is legible.

## 6.6 Wrap-up checklist to give the user

- [ ] Token stored in a secret manager (it can't be retrieved again)
- [ ] token `id` recorded (needed to revoke)
- [ ] Understands the policy is immutable — changes mean delete + recreate + re-store the secret
- [ ] Knows how to list (`GET .../policyApiToken`) and revoke (`DELETE .../policyApiToken/{id}`)
- [ ] Any test token created during verification has been revoked
- [ ] Expiry set if appropriate (agent tokens especially)
