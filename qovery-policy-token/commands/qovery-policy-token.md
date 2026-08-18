---
description: Create and verify a scoped Qovery API Policy Token from your intent
---

Create a least-privilege Qovery API Policy Token (OPA/Rego) that allows exactly what you want and denies everything else.

If arguments are provided, use them as context:
- `$ARGUMENTS` — a plain-English intent ("read-only on staging, can deploy the api service, never delete"), a Qovery Console URL, or environment/service names to scope the policy to

Follow the qovery-policy-token skill to:
1. Capture the intent as an explicit allow-list + deny-list and resolve the real resource UUIDs
2. Author a least-privilege Rego policy and explain each rule
3. Test the policy locally with OPA against an allow/deny matrix until it is green
4. Create the token via the API (only after you confirm the policy — policies are immutable)
5. Verify the live token allows the intended actions and denies everything else, then hand it over once

CRITICAL: Confirm the policy before creating the token (policies cannot be edited), and never echo, print, or store the returned token value.
