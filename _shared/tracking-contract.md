# Skill run v1 integration

Source: q-core main commit `39d547123f0bc16264e974ddbadbf0f9fb3afbdf`,
[validated contract](https://gitlab.com/qovery/backend/q-core/-/blob/main/doc-features/skill-tracking/contract.md).

The helper sends exactly run_id, anonymous_id, skill_name, skill_version and
started_at to `/v1/skillRuns/start` (anonymous) and
`/v1/organization/{organization_id}/skillRuns/associate` (human Bearer session).
The private 32-byte hex correlation secret is supplied in
X-Qovery-Skill-Run-Secret, never in payloads, URLs, process arguments or analytics.
q-core generates and deduplicates event UUIDs. The client retains metadata and
proof unchanged; a 202 persists the returned event ID/status and stops client
retries. Accepted analytics failures are handled by the backend outbox.

No client identity field or alias is sent. JWT claims are read in memory only to
hash a local account-switch guard; this is not signature verification or trusted
identity mapping. q-core verifies issuer/signature, human user and organization
permission. Each run binds one immutable account/organization; changing either
requires a new execution. The root `qovery` skill is excluded rather than renamed
because the backend allows only `qovery-*`.

Client behavior: opt-out before state or sends; 100 private run directories;
atomic state updates and per-run file locks; 30-day expiration and pruning on
launch. Start state is persisted before launching a detached worker. Each worker
attempts start, then explicit association, with no sleeps or inline network waits.
Explicit association workers wait for an active sender to release the run lock;
anonymous queue drains skip busy runs. The agent command remains nonblocking.
An absent auth session leaves the anonymous run intact. Resume retries start only;
association retries require explicit org and current matching session. Each worker
also retries at most two other due anonymous starts, never old associations.

curl ignores default configuration with --disable as its first option and sends
the versioned QoverySkill User-Agent. It uses config stdin for credentials/proof, connection deadline 3s, request 8s,
subprocess deadline 9s, bounded response body, no redirects and no body/error logs.
CLI auth has a 3s subprocess deadline. Backoff starts at 5s with jitter, capped
at one hour; 429/503 use at least 60s and respect numeric Retry-After. Permanent
400/403/404/409/410/413 stop retries; 401 remains pending for explicit reauthentication.
Retries are opportunistic for up to 30 days, not an always-running daemon.
Cleanup explicitly discards queued requests as well as completed state.

Legacy skill-called is removed from helper sends with no fallback or dual emission.
User-Agent SKILL audit attribution and skill-api-call remain separate signals;
report starts as uses, associations as enrichment, never add legacy/API events.

Contract publication dependency: the canonical schemas are in the q-core contract
linked above. Publishing these operations in qovery-openapi-spec is a separate
backend/spec follow-up; the helper does not infer routes from the legacy OpenAPI.

Remaining operational checks (not performed by these tests):
- Gateway forwarding of both versioned routes and secret/header/body redaction.
- Backend collection enabled, proxy-aware rate limits and delivery metrics/alerts.
- Event UUID deduplication and run joins in a non-production PostHog project.
- Production ingestion and receiving-project retention policy.

Tests cover shared/distributed implementations, installations and injected HTTP
responses without production events. Release/merge is not proof of the above.

## Native helper distribution

The runtime is the Rust `tracking/` crate (`skill-run 0.1.0`), distributed as
`skill-tracking-v0.1.0` GitHub release assets with individual SHA-256 files for
x86_64/aarch64 Linux musl and x86_64/ARM64 macOS. WSL uses Linux assets. No Rust
or Python installation is needed at runtime; Bash and curl remain required.
The JSON state format and existing run/anonymous IDs remain compatible.

The installer downloads and verifies one binary, checks its version, and copies
it into each skill's `scripts/skill-run`. It never sends analytics. Opt-out still
installs the binary so cleanup remains available, while preventing state creation
and event sends. Unsupported platforms, missing assets, or checksum failures leave
tracking unavailable without blocking skill installation. An absolute executable
`QOVERY_SKILLS_TRACKING_BINARY` override supports local pre-release smoke tests.
Development symlink installs remain tracking-disabled. If no installed helper is
available, a verified standalone binary can still run `cleanup STATE_PATH` with
tracking disabled; cleanup does not require an installation version or auth.

The CI workflow builds/tests on PRs and uploads binary/checksum artifacts. Only
an explicit workflow dispatch with `publish_draft` creates a draft release; a
maintainer must publish that release before installer downloads are available.
This change does not publish or dispatch a release.

Local validation: `cargo test --manifest-path tracking/Cargo.toml --locked` covers
contract, old Python state compatibility, concurrency, retries and an installed
journey whose PATH contains no Python. `cargo build --manifest-path tracking/Cargo.toml
--locked` followed by `bash scripts/test-tracking-install.sh` verifies distribution
with mock downloads and the native binary. No production events are sent.
