# Lifecycle transport readiness

Inspected local q-core: `skilltracking/web/SkillTrackingApi.kt` declares only
`/api/organization/{organizationId}/skill-tracking`; `SkillTrackingUseCase.kt`
emits `skill-called` using authenticated userSub and organizationId.
AuditLogService classifies QoverySkill User-Agent as SKILL audit origin.
This inspection does not establish remote branch or deployment readiness.

Required before implementing a production adapter:
- Validated anonymous start and authenticated association routes, methods, DTOs,
  timestamps, accepted identifiers and response/error schemas.
- Anonymous identifier scope/lifetime, identity/alias mapping, authentication
  schemes, organization authorization, account-switch semantics.
- Idempotency/deduplication contract, order and handling of late/failed starts,
  reassociation across organizations/accounts and retryable responses.
- Compatibility/cutover strategy for skill-called and server consumers; no dual
  emission as two usages. Retention/cleanup policy and deployment availability.

`skill-run.py` is an offline prototype with fixture fields, not a wire contract.
It has no network implementation, does not read auth/cache, and permits only
explicit simulated file output. Tests inject transport functions with deterministic
outcomes. Three attempts with 50 ms gaps; simulated file I/O is local. A future
network adapter must enforce connect/request/overall deadlines and validated auth.
Private state contains only fixture events (directory 0700, file 0600), with locked
updates, symlink rejection, 24h expiration on resume and explicit cleanup. No
background janitor exists; abandoned state must be removed by the agent.
