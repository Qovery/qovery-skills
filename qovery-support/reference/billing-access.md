# Billing, plans and team access

Covers deployments refused for billing reasons, plan-gated features, cloud cost questions, roles and custom roles, invitations, changing login provider and SSO. Billing changes and plan unlocks always go through Qovery; the skill explains and routes, it does not change billing.

## Contents

- Deployment or cluster creation refused for billing
- Plan-gated features
- "Why did my cloud bill go up?"
- Roles: who can do what
- Custom roles, shell and port-forward permissions
- Inviting a teammate, and invitations that land on the wrong account
- Switching login provider (for example GitLab to GitHub)
- SSO (SAML or OIDC)
- Tokens for CI and agents
- Known limits

## Deployment or cluster creation refused for billing

**Symptom.** Deployments or cluster creation are refused with a payment or subscription message, sometimes although the invoice is marked as paid.

**How to check.** Read the organization: `qovery api "organization/<organizationId>"` and look at `billing_deployment_restriction`.
- `null`: no billing restriction; the cause is elsewhere.
- `NO_CREDIT_CARD`: the organization is on a trial without a payment method. Managed cluster creation and deployments on managed clusters are blocked; the demo cluster still works. Add a payment method in the organization billing settings; if the restriction stays, contact Qovery support.
- Any other value blocks all deployments. This is an account state, not a technical failure.

**Fix.** For anything other than `NO_CREDIT_CARD`, the user contacts Qovery support with the invoice reference or payment confirmation; support lifts the restriction once payment is confirmed. Only an Owner, Admin or Billing Manager can manage billing.

## Plan-gated features

Some features depend on the plan or need Qovery to enable them, for example: log history and metrics beyond 24 hours (Qovery Observe), SSO, some build settings customization, the number of members, and the number of concurrent deployments. When a user cannot find a setting that the docs describe, check the plan before assuming a bug, and point them to <https://www.qovery.com/pricing> or their Qovery contact. Do not quote prices from memory.

## "Why did my cloud bill go up?"

Qovery runs in the user's cloud account; the cloud bill is AWS's (or another provider's), separate from the Qovery subscription. Usual causes of a jump:
- More or bigger nodes: higher requests, more instances, autoscaling maximums, node pool instance types.
- NAT gateway and data transfer: image pulls and traffic through NAT, sometimes from an HPA that scales up and down continuously (see `reference/kubernetes-basics.md`).
- Resources left after deleting a cluster or environment (load balancers, databases, volumes, snapshots).
- Preview environments that never get deleted.

For a full cost review and right-sizing, hand off to `qovery-optimize`.

## Roles: who can do what

| Role | Summary |
|---|---|
| Owner | Everything, including deleting the organization and transferring ownership. One per organization |
| Admin | Like Owner, without deleting the organization or transferring ownership |
| DevOps | Clusters, registries, webhooks, API tokens, and full access to every project; no members, roles or billing |
| Billing Manager | Billing only, plus read-only cluster info; no project access |
| Viewer | Read-only on everything |

Docs: <https://www.qovery.com/docs/configuration/organization/members-rbac>.

## Custom roles, shell and port-forward permissions

- Custom roles scope access per cluster (Read-Only, Create Environment, Full Access) and per project and environment type (Development, Preview, Staging, Production).
- **Shell** and **Port-forward** are separate permissions per project and environment type. "Connection refused" on `qovery shell` or `qovery port-forward` for a user with deploy rights usually means the role lacks that permission. A user can be allowed to port-forward to a database without being able to deploy.
- Custom roles cannot generate API tokens, manage organization settings, manage members or manage billing.

## Inviting a teammate, and invitations that land on the wrong account

- Invite from **Organization settings > Members > Invite Member** with an email and a role. The CLI and API equivalent is `POST /organization/{organizationId}/inviteMember`.
- An invitation is accepted by whichever Qovery account is signed in when the link is opened. If the person is already signed in with another account (another email or another login provider), the invitation lands on that account. Ask them to open the invitation link in a private browser window and sign in with the intended identity.

## Switching login provider (for example GitLab to GitHub)

A different login provider is a different Qovery user, even with the same email. To switch:
1. An Admin invites the new identity's email from **Members**.
2. The person opens the invitation in a private window, signs in with the new provider and accepts.
3. They skip the onboarding form if it appears (the organization already exists).
4. Once the new account works, the Admin removes the old member. If the old account is the Owner, transfer ownership first.

## SSO (SAML or OIDC)

SSO with an identity provider (for example Okta or Google Workspace) is enabled by Qovery for the organization: the user contacts their Qovery contact or support, receives a connection name to configure in the identity provider, and Qovery validates the flow with them. Group synchronization and a default role can be configured. Docs: <https://www.qovery.com/docs/configuration/organization/sso>.

## Tokens for CI and agents

- People use `qovery auth` sessions; avoid long-lived personal tokens.
- For CI or an AI agent, use an API token with the smallest role, or an **API policy token** limited to exact actions. Hand off to `qovery-policy-token` to create one. Docs: <https://www.qovery.com/docs/configuration/organization/api-token>.

## Known limits

- Billing restrictions other than `NO_CREDIT_CARD` are lifted by Qovery, not by the user.
- Members, roles and billing cannot be delegated through a custom role.
