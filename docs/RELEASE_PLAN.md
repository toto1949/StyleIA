# SceneMe 1.0 Release Plan

Plan date: 2026-10-12
Release owner: Zevynta Labs LLC
Engineering objective: produce a testable release candidate; public submission and launch remain owner-controlled.

## Release gates

A phase is complete only when its acceptance evidence exists. Source code presence, mock responses, or a passing unit test alone are not sufficient evidence of live behavior.

| Gate | Acceptance evidence |
| --- | --- |
| G0 Audit | Repository/API/journey map, prioritized findings, local command evidence, Apple policy comparison. |
| G1 Data foundation | PostgreSQL migrations and constraints pass; legacy import is tested; private object access/isolation and deletion tests pass; backup/restore drill documented. |
| G2 Durable generation | Restart recovery, idempotency, cancellation, retry/timeout, concurrency and budget tests pass; one authorized staging provider run is recorded. |
| G3 Entitlements | Verified JWS fixtures, notifications, reconciliation, quota and account-binding tests pass; StoreKit local + Apple Sandbox matrix passes. |
| G4 iOS quality | Release build passes; critical UI journeys pass; device/orientation/accessibility/memory/offline matrix has no launch-blocking defect. |
| G5 Compliance/metadata | Privacy implementation, manifest/archive report, legal links, rights review, content-safety controls and App Store worksheets are owner-approved. |
| G6 TestFlight RC | Signed archive validates, TestFlight installs on physical iPhone/iPad, production-like end-to-end checks pass, monitoring/rollback are ready. |
| G7 Submission | Owner approves exact build, metadata, products, pricing, review account/notes, and manually authorizes submission. |

## Dependency-ordered execution

### Phase 0 — Audit and baseline

Status: **complete for current working tree**

Completed evidence:

- `docs/RELEASE_AUDIT.md`
- Backend `npm test` passed in mock mode.
- iOS unit tests passed on iPhone 17 Pro simulator/Xcode 26.6.
- Four deterministic iOS UI smoke cases passed for authentication, catalog, support and companion consent.
- An unsigned generic-device arm64 Release build passed Xcode shallow store validation; signed archive validation awaits Apple configuration.
- Production health/legal/catalog reachability checked.
- Latest committed GitHub Actions status recorded.
- First launch authentication UI visually inspected.

Branch update:

- Work continues on `codex/release-1.0`. The inherited uncommitted changes were preserved rather than discarded. Before PR creation, the owner must confirm how those pre-existing changes should be grouped.

### Phase 1A — PostgreSQL foundation

Deliverables:

1. Add versioned SQL migrations for users, auth identities, sessions, uploads, generation jobs, job attempts/events, results, usage periods, subscription entitlements/transactions/notifications and idempotency keys.
2. Add foreign keys, unique constraints, least-privilege application role and indexes for account lookup, provider identity, job polling/history, usage enforcement and notification replay protection.
3. Add a PostgreSQL repository and transaction boundaries; production must refuse to boot without `DATABASE_URL`.
4. Add a one-time legacy JSON importer with dry-run, counts/checksums and conflict reporting.
5. Add migration up/down or forward-fix instructions, pre-migration backup and recovery steps.
6. Add integration tests using an isolated PostgreSQL service in CI.

Acceptance:

- Concurrent quota/job creation cannot exceed constraints.
- A service restart preserves users, jobs, usage and entitlements.
- Import fixtures preserve identifiers and timestamps.
- Backup restore recreates row counts and representative records.

### Phase 1B — Private object storage

Deliverables:

1. Add S3-compatible storage adapter for AWS S3 or Cloudflare R2 using private buckets and server-side encryption.
2. Return short-lived presigned PUT URLs; record object owner, purpose, expected type/size and expiry.
3. Validate completion with object HEAD plus full server-side image decode/pixel limits before generation.
4. Copy provider outputs into the private bucket before marking jobs complete.
5. Return short-lived signed GET URLs only after an authenticated ownership check or when serializing an owned job/history item.
6. Add lifecycle cleanup for abandoned uploads, expired temp objects, deleted results and accounts.
7. Add cross-user isolation/deletion/restart tests.

Acceptance:

- Direct unauthenticated object GET fails.
- User A cannot sign/read/delete User B's object.
- Outputs remain available after app/backend restart.
- Result/account deletion removes owned objects and records a verifiable outcome.

### Phase 1C — Durable generation and operations

Implementation status (2026-10-13): the backend now uses fal's queued request lifecycle, persists request/model/phase and intermediate video/audio state, resumes submitted work after restart without a second submission, propagates cancellation, and ingests provider results under deterministic object keys. No-spend provider-contract and PostgreSQL round-trip tests pass. The acceptance gate remains open until an authorized staging kill/restart/cancel run proves the behavior against real paid requests.

Deliverables:

1. Database-backed job claiming with leases and startup recovery.
2. Persist provider request IDs and attempt states; resume/poll queued work after restart where provider supports it.
3. Require `Idempotency-Key` for paid creation/reroll/video operations and enforce uniqueness per user/operation.
4. Add bounded exponential retries with jitter, timeouts, failure classes and dead-letter/manual retry state.
5. Add cancellation flags and provider cancellation when supported.
6. Add per-user concurrency, endpoint/user/IP rate limits, daily user cost ceilings, global daily budget and emergency provider kill switch.
7. Add structured redacted logs, request IDs, build SHA, readiness checks, metrics and alerts.
8. Create staging/production configuration and fail-closed production validation. Mock/fallback modes must be impossible in production.

Acceptance:

- Kill/restart tests complete or safely retry queued jobs without duplicate charged output.
- Simultaneous identical idempotency keys produce one billable job.
- Limits reject before provider submission.
- Logs contain no tokens, email/password bodies, photo URLs with credentials, private prompts or raw provider payloads.

### Phase 2 — iOS release hardening

Deliverables:

1. Add backend `/me` or entitlement/usage endpoint and remove `UserDefaults` quota as billable authority.
2. Restore active jobs/history on cold launch; represent queued/processing/failed/cancelled states consistently.
3. Map structured backend error codes to actionable retry, subscription, connectivity and support states.
4. Add bounded image/video download/upload configuration, offline/slow-network handling and safe background behavior.
5. Add accessibility labels/values, Dynamic Type-safe layout, contrast/Reduce Motion support and minimum touch targets.
6. Test and fix iPhone/iPad/orientation/safe-area behavior.
7. Profile image filters, photo loading, download, playback and watermark export on real lower-memory devices.
8. Confirm notifications are contextual and cold-launch deep links restore the correct result.
9. Confirm release configuration contains no debug controls/mock endpoints and archive privacy report is accurate.
10. Decide whether Google ships in 1.0. If yes, add URL scheme/config and test; if no, document it as intentionally unavailable.

Acceptance:

- Critical UI tests pass against deterministic staging fixtures.
- Airplane-mode/packet-loss/background/termination recovery has explicit expected behavior.
- Accessibility/device/memory checklist is signed off with device/OS evidence.

### Phase 3 — production subscriptions

Commercial identifiers remain unchanged unless the owner explicitly approves otherwise.

Deliverables:

1. Store durable original transactions, transactions, renewal status and account mapping.
2. Verify Apple JWS signatures using trusted Apple roots and validate bundle/environment/product/time claims.
3. Implement App Store Server Notifications V2 with signature validation, notification UUID replay protection and idempotent state transitions.
4. Add App Store Server API reconciliation and scheduled repair for missed notifications.
5. Handle purchase, pending, restore, upgrade, downgrade, renewal, expiration, refund, revocation, billing retry and optional grace period.
6. Bind new purchases to the authenticated UUID with `appAccountToken`; define owner-approved handling for legacy untagged transactions.
7. Enforce non-expiring credit grants and atomic job debits/refunds on the server; expose the balance read-only to iOS.
8. Validate the approved model with measured COGS from real staging invoices.

Owner decisions and gates:

- Approved for engineering: 3/30/100 grants, 1/2/6/23 operation costs and target prices.
- Still required: financial validation and explicit live-price/storefront activation approval.
- Approve whether billing grace period is enabled after Sandbox validation.

Acceptance:

- StoreKit configuration tests pass for all four products.
- Apple Sandbox tests pass for every lifecycle state.
- A refunded/revoked/expired transaction removes access within the defined SLA.
- Switching SceneMe accounts cannot transfer a tagged entitlement.
- Backend rejects forged, cross-account and replayed transaction data.

### Phase 4 — privacy, legal and safety

Deliverables:

1. Align privacy policy/terms with actual PostgreSQL, object storage, fal.ai, OpenAI and Apple processing/retention/deletion behavior.
2. Add explicit companion-photo rights/consent acknowledgment and prohibited-use language in product flow.
3. Add input/output safety checks appropriate for realistic faces, impersonation, NCII, minors and CSAM escalation.
4. Document whether outputs are private-only; if sharing/public hosting is ever added, implement Guideline 1.2 reporting/blocking/moderation first.
5. Complete template/thumbnail/trademark/license inventory and replace unlicensed/placeholders.
6. Validate app privacy manifest plus the assembled archive's third-party manifests and App Store privacy answers.
7. Prepare export compliance, age rating, support, privacy and marketing URL recommendations.

Acceptance:

- Engineering-to-policy data map has no unexplained processor, category or retention mismatch.
- Owner and qualified counsel review suggested legal changes.
- Support/privacy/terms URLs are public, stable and monitored.

### Phase 5 — automated and manual QA

Deliverables:

- Backend authorization, cross-user isolation, deletion, job lifecycle/restart, quota/rate limits, JWS/notifications and API-contract suites.
- iOS unit tests for error mapping/persistence/entitlement view state and UI tests for auth, photo validation, generation states, paywall/restore, export and deletion.
- GitHub Actions for syntax/lint, unit/integration tests, migrations, Release simulator build, UI smoke, dependency audit and secret scan.
- Executable `docs/QA_CHECKLIST.md` and `release/RELEASE_READINESS.md` with PASS/BLOCKED/NOT TESTED evidence.

External evidence required:

- Physical iPhone and iPad.
- Apple Sandbox and TestFlight.
- Authorized staging fal.ai/OpenAI calls.
- Production-like PostgreSQL/object storage.

### Phase 6 — App Store assets and Connect worksheets

Deliverables under `release/app-store/`:

- Metadata, keywords, promotional text, What's New and review notes.
- App privacy, subscription, age-rating and export-compliance worksheets.
- Final icon validation.
- Screenshots captured from the actual release candidate at Apple's current required sizes.
- Optional app preview made only from captured application footage.

Acceptance:

- No placeholder, fabricated, private or non-shipping UI appears in assets.
- Owner approves copy and rights.

### Phases 7–8 — deployment, TestFlight and launch

Blocked pending owner authorization and credentials.

Sequence:

1. Owner approves infrastructure provider/costs and supplies secrets through provider secret stores.
2. Deploy staging; migrate/import; run end-to-end and recovery drills.
3. Owner approves production change window; back up; migrate; deploy; verify; retain rollback checkpoint.
4. Verify Apple team/signing, archive Release, validate and upload an owner-approved build.
5. Run TestFlight matrix with owner; fix defects and cut a new immutable build.
6. Owner approves App Store Connect metadata, subscriptions, pricing and submission.
7. Owner initiates submission/public release.
8. Monitor crashes, latency, job failures, purchase errors, costs and support; execute rollback if thresholds are crossed.

## Pull request strategy

The release branch exists, but no commit or pull request was created because the inherited dirty worktree has not been attributed. Proposed review units:

1. `foundation/docs-audit`
2. `backend/postgres-migrations`
3. `backend/private-object-storage`
4. `backend/durable-jobs-cost-controls`
5. `backend/apple-entitlements`
6. `ios/server-usage-and-recovery`
7. `ios/accessibility-release-hardening`
8. `qa/integration-ui-ci`
9. `release/app-store-assets-runbooks`

Each PR must include migration/rollback notes, tests run, risk, monitoring and unresolved external checks. Use the `codex/` branch prefix unless the owner requests another name.

## Owner inputs intentionally deferred

- App Store Connect organization/team confirmation and product configuration.
- App Store Server API key and Sign in with Apple key, delivered through secret storage only.
- Production database/object storage vendor and budget approval.
- fal.ai/OpenAI staging and production spending limits.
- Pro commercial-limit/pricing decision.
- Rights confirmation for template names, prompts, thumbnails and marketing assets.
- Qualified legal review.
- Final submission and launch authorization.
