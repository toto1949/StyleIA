# SceneMe 1.0 Release Audit

Audit date: 2026-10-12
Owner: Zevynta Labs LLC
Audited revision: `c0a445a` (`main`) plus the uncommitted working-tree changes present on the audit date
Bundle identifier: `com.sceneme.app`
Production API configured in the app: `https://styleia.onrender.com/v1`

## Executive decision

SceneMe is **not ready for App Store submission**. The product is a substantial working prototype: it builds, its existing unit and mock backend tests pass, the production service responds over HTTPS, the main UI launches, StoreKit 2 code and account deletion UI exist, and sensitive provider keys are kept on the backend. Those facts do not establish production readiness.

The release is blocked by four foundational issues:

1. Production state is still a single JSON document and private media is stored on the service filesystem (`Backend/src/store.mjs`, `Backend/src/routes/upload.mjs`, `render.yaml`). This is not a durable, horizontally safe database/object-storage design.
2. Generation work runs as untracked in-process promises (`Backend/src/routes/generate.mjs:388-398`). A restart can strand jobs, repeat paid provider work, or lose cancellation state.
3. Subscription authorization is not durable and App Store Server Notifications V2 are absent. The server grants access from a client-supplied transaction ID and decodes, but does not cryptographically verify, Apple's signed transaction payload (`Backend/src/services/app-store-service.mjs:16-50,86-106`).
4. Real production behavior has not been verified: no live fal.ai run, Apple Sandbox purchase lifecycle, TestFlight build, signed archive validation, real-device test, production deletion test, or backup/restore drill was performed during this audit.

No production deployment, paid provider call, App Store Connect change, pricing change, or public release was performed.

## Evidence collected

| Check | Result | Evidence |
| --- | --- | --- |
| Working tree | WARN | `main` matches `origin/main` at `c0a445a`, but 29 tracked files are modified and 5 files are untracked. Existing changes were preserved. |
| Backend suite | PASS (mock scope only) | `cd Backend && npm test` passed companion prompts, subscription gates, and mock smoke on 2026-10-12. |
| iOS unit suite | PASS | `xcodebuild test ... -only-testing:AuraTests` passed 11/11 tests, including the StoreKit product-contract check, on an iPhone 17 Pro iOS 26.5 simulator with Xcode 26.6. Result bundle: `/tmp/sceneme-derived-unit-final/Logs/Test/Test-Aura-2026.10.13_16-44-13--0400.xcresult`. |
| iOS UI suite | PASS (smoke scope) | The shared scheme ran 4/4 deterministic UI cases for auth validation at Accessibility XXXL, offline catalog naming, the Profile support link and friend-photo permission disclosure. Result bundle: `/tmp/sceneme-derived-ui/Logs/Test/Test-Aura-2026.10.13_16-34-21--0400.xcresult`. Paid/live end-to-end journeys remain untested. |
| Unsigned device Release build | PASS | A generic `iphoneos` arm64 Release build succeeded with `CODE_SIGNING_ALLOWED=NO` and Xcode shallow store validation. Signing and archive validation remain blocked on Apple configuration. |
| Simulator launch | PASS (first screen only) | Debug app installed and launched; authentication screen rendered with Apple and email options. No production account or provider was exercised. |
| GitHub Actions | PASS for committed baseline only | Latest run for `c0a445a` completed successfully on 2026-08-23: https://github.com/toto1949/StyleIA/actions/runs/32664399396. The current uncommitted iOS CI additions have not run on GitHub. |
| Production HTTP | PASS (reachability only) | `/health`, `/privacy`, `/terms`, and `/v1/scenes` returned HTTP 200 over HTTPS on 2026-10-12. |
| Production WebSocket | NOT TESTED | Requires an authenticated job. |
| Live fal.ai/OpenAI | NOT TESTED | No credentials or spending authorization used. |
| StoreKit local config | PARTIAL | An automated test verifies the four expected recurring products, durations and Swift mappings in `SceneMe.storekit`; no transaction lifecycle passed. |
| Apple Sandbox/TestFlight | BLOCKED | Owner will provide App Store Connect configuration later. |
| Signed Release archive | BLOCKED | Owner confirmed Team ID `3K82B6HTAT`, matching the project. The Mac has two development identities and one matching development profile (expires 2027-07-10), but no distribution identity; portal role and legal organization ownership remain unverified. |

## Repository and architecture map

- iOS application: `Aura/`
- iOS unit tests: `AuraTests/`
- iOS UI tests: `AuraUITests/`
- Xcode project and shared scheme: `Aura.xcodeproj/`
- Local StoreKit configuration: `SceneMe.storekit`
- Node 20 backend: `Backend/`
- Render blueprint: `render.yaml`
- CI: `.github/workflows/ci.yml`

Current runtime path:

```text
SwiftUI app
  -> HTTPS REST + WebSocket
  -> single Node process on Render
  -> JSON file + local/persistent-disk uploads
  -> fal.ai image/video/TTS/lip-sync
  -> fal-hosted output URLs
  -> OpenAI moderation/template enhancement
  -> Apple App Store Server API (transaction lookup only)
```

Required production path is documented in `docs/ARCHITECTURE.md`; it must use PostgreSQL, private S3-compatible storage, durable entitlement records, and restart-safe job processing.

## Verified user journey

The following is a source-and-simulator map, not a claim that every step works against production.

1. `StyleAIApp` creates `SceneMeRootView`; `SceneMeViewModel` restores a Keychain session and account-scoped local history.
2. Unauthenticated users see `AuthView` with email sign-in/create-account and Sign in with Apple. Google is hidden while `GIDClientID` is empty.
3. A successful backend auth response is stored in Keychain by `SessionStore` and server history is fetched.
4. Home uses `PhotosPicker`, which avoids requesting broad photo-library read access. `VisionStyleIAImageAnalyzer` validates a selected image and `CoreImageStyleIAImageOptimizer` crops/compresses it.
5. The user chooses a scene in `ScenePickerView`, adjusts time/weather/pose, optionally chooses a custom scene or companion, and starts generation.
6. `AIProcessingConsentView` gates the first transfer to fal.ai/OpenAI. Consent is local, account-keyed `UserDefaults` state.
7. `ImageUploadService` requests a backend upload URL, uploads a JPEG, and sends the returned key in a scene-job request.
8. `GenerationService` polls job state; `GeneratingView` presents progress/cancel UI. The backend starts generation in the same web process.
9. `ResultView` downloads the provider result, supports filters, postcard rendering, sharing/saving, rerolls, and Pro Video Director.
10. Video generation creates another in-process job. Talking mode attempts TTS then lip-sync, silently falling back to a silent video if audio processing fails.
11. Completed image records are merged into local/server history. The iOS app may save original photos and history locally in Application Support.
12. `PaywallView` loads four StoreKit products, purchases with an account UUID as `appAccountToken`, listens for transactions, restores, and sends the latest transaction ID to protected backend routes.
13. Profile offers AI-consent review, subscription management/restore, sign-out, and account deletion. Backend deletion removes JSON records and local upload files; it cannot remove already-generated fal-hosted outputs.

## API route audit

| Route | Auth | Persistence/side effect | Audit result |
| --- | --- | --- | --- |
| `GET /health` | No | None | Reachable, but only liveness; no database/storage/provider readiness or build version. |
| `GET /privacy`, `/terms` | No | None | Reachable. Legal copy needs owner/counsel review and implementation alignment. |
| `POST /v1/auth/email` | No | Creates/reads user | Rate-limited by IP in memory. No email verification, password reset, session revocation, or durable audit trail. |
| `POST /v1/auth/apple` | No | Creates/links user, stores encrypted refresh token | Signature/audience checks exist. Account linking ignores `emailVerified`; nonce/algorithm checks are absent. |
| `POST /v1/auth/google` | No | Creates/links user | Hidden in current build. Redirect URL type is absent from `Info.plist`; account linking ignores `emailVerified`. |
| `POST /v1/upload/presign` | Yes | Creates pending upload | URL points back to the same Node process, not S3/R2. Pending records have no expiry cleanup. |
| `PUT /v1/upload/:id` | Signed upload token | Writes local file | Checks JPEG magic bytes only; no full decode, dimensions, decompression-bomb defense, malware workflow, or object storage. |
| `GET /v1/scenes` | No | Reads bundled JSON | Works. Thumbnails are `picsum.photos` placeholders and are a release/metadata/licensing risk. |
| `POST /v1/templates/improve` | Yes + Creator transaction header | Calls moderation/OpenAI | No durable entitlement; no idempotency or per-user cost budget. |
| `POST /v1/scene-jobs` | Yes | Upload lookup, usage increment, job insert, fal call | Server quota exists, but durability, concurrency limits, idempotency, restart recovery, output ownership, and daily budget are missing. |
| `GET /v1/scene-jobs/:id` | Yes, owner scoped | Reads job | Cross-user filter exists. Provider URLs may be public/expiring. |
| `DELETE /v1/scene-jobs/:id` | Yes, owner scoped | Deletes job/refunds pending still quota | Does not cancel fal request or delete inputs/outputs; cancellation set is process-local. |
| `POST /v1/scene-jobs/:id/reroll` | Yes + Creator | Creates job, consumes quota | Same durability/idempotency gaps. |
| `POST /v1/scene-jobs/:id/video` | Yes + Pro | Creates video job | Historical audit found no video quota; the release branch now debits 6 or 23 credits and applies dollar caps. |
| `GET /v1/history` | Yes, owner scoped | Reads completed jobs | Pagination is in-memory after loading all records. Returned provider URLs are not controlled private media. |
| `DELETE /v1/account` | Yes | Deletes user/upload/job/usage records and local input files | Does not delete fal-hosted generated media. Apple revocation failure is logged and deletion continues, consistent with Apple's deletion guidance, but retry evidence is not durable. |
| `WS /ws/:jobId` | Access token + job ownership | Progress stream | Ownership is checked, but state and clients are process-local. No authenticated production connectivity test was run. |

## Findings

### Critical — must be fixed before TestFlight release-candidate approval

#### C-01 — JSON persistence is not production safe

- Location: `Backend/src/store.mjs`, `Backend/src/services/store-instance.mjs`, `render.yaml`
- Evidence: every mutation reads and rewrites one JSON document; locking exists only inside one Node process.
- Impact: corruption/races with multiple instances, slow growth, no database constraints/indexes, weak backup/restore story, and unsafe migrations.
- Required action: PostgreSQL schema, migrations, transactional repository, constraints/indexes, encrypted backups, point-in-time recovery, migration/import and rollback runbook.

#### C-02 — private and generated media is not under durable private storage control

- Location: `Backend/src/routes/upload.mjs:9-68`, `Backend/src/routes/generate.mjs:303-337,423-450`, `Backend/src/services/fal-service.mjs`
- Evidence: originals are filesystem JPEGs; outputs remain fal CDN URLs; account/result deletion cannot delete provider-hosted results.
- Impact: loss on disk failure/deploy, privacy/access risk, broken history when URLs expire, inability to prove deletion.
- Required action: private S3/R2 bucket, direct presigned PUT, MIME/decode/dimension validation, encrypted objects, signed GET URLs, copied/owned result objects, lifecycle and deletion jobs.

#### C-03 — jobs are not durable across restart and paid work is not idempotent

- Location: `Backend/src/routes/generate.mjs:37,40-59,388-398,400-553`
- Evidence: `startGeneration()` and `startVideoGeneration()` fire promises in the web process; cancellation is a `Set`; provider request IDs are not persisted.
- Impact: stranded jobs, duplicate charges after retries/restarts, cancellation not honored, no bounded retry/dead-letter behavior.
- Required action: database-backed queue/leases, idempotency keys and unique constraints, persisted provider request IDs, retry/timeout policy, startup recovery, cancellation propagation, dead-letter/admin recovery.

#### C-04 — subscription authorization is incomplete

- Location: `Backend/src/services/app-store-service.mjs`; no notifications route exists.
- Evidence: entitlement is recalculated from `X-SceneMe-App-Store-Transaction-ID`; cache is memory-only; `signedTransactionInfo` is decoded without JWS signature verification; original transaction ownership and lifecycle events are not stored; Notifications V2 are absent.
- Impact: stale access, incorrect handling of refund/revocation/expiration/grace/billing retry, fragile account switching, and audit/compliance risk.
- Required action: verified JWS library/Apple root certificates, durable subscriptions/transactions, original-transaction-to-user binding, Server Notifications V2 endpoint with replay protection, periodic reconciliation, grace/refund/revocation tests.

#### C-05 — uncapped Pro was financially unsafe

- Location: `Aura/Models/SubscriptionTier.swift:34-40`, `Aura/Views/PaywallView.swift`, `SceneMe.storekit`, `Backend/src/services/app-store-service.mjs:61-73`
- Evidence: Pro has infinite image allowance and no server video allowance. Current public fal pricing is about $0.04 per Kontext Pro image and $0.225 per five-second 720p PixVerse clip before TTS/lip-sync and infrastructure. A $14.99 monthly subscriber can exceed gross revenue with roughly 67 base video clips, before Apple's commission and all other costs.
- Impact: trivial intentional or accidental unbounded loss.
- Required action: owner-approved transparent monthly image/video limits or credits, per-user concurrency and daily spend caps, global budget kill switch and alerts. Commercial copy must change only after owner approval.

#### C-06 — account linking can trust an unverified provider email

- Location: `Backend/src/server.mjs:278-373`, `Backend/src/auth.mjs:117-249`
- Evidence: verification helpers return `emailVerified`, but linking by email does not require it.
- Impact: provider-token edge cases can link to an existing email account incorrectly.
- Required action: only link verified provider emails; otherwise create a distinct identity or require an authenticated explicit link flow. Add regression tests.

### High — release blockers

#### H-01 — production upload validation is shallow

- Location: `Backend/src/routes/upload.mjs:39-64`
- JPEG magic bytes are not proof of a safe, decodable image. Validate complete decode, dimensions/pixel count, content type, metadata stripping, and upload completion. Enforce user/object ownership in storage policies and tests.

#### H-02 — rate limits and budgets are process-local and IP-only

- Location: `Backend/src/server.mjs:41,101-103,452-476`
- A restart resets limits; scaling creates independent limits; trusted proxy handling is not explicit; paid endpoints have no per-user concurrency/daily budget. Move enforcement to PostgreSQL/Redis and key authenticated limits by user.

#### H-03 — deletion does not cover all user data

- Location: `Backend/src/server.mjs:388-415`, `Backend/src/routes/generate.mjs:211-230`
- Result deletion removes a job record only. Account deletion cannot remove fal-hosted outputs and has no durable provider-deletion/retry ledger. Privacy copy currently promises deletion from systems under SceneMe control, but the storage design does not yet make that verifiable.

#### H-04 — authentication/session controls need hardening

- Location: `Backend/src/auth.mjs`, `Backend/src/server.mjs:228-376`
- Access tokens last 30 days, have no issuer/audience/jti/token-version checks, and cannot be revoked except by deleting the user. Apple/Google verification lacks explicit algorithm and nonce checks and remote key requests lack timeouts. Email accounts have no verification/reset or breach controls. Add short-lived access + rotating refresh sessions, token version/revocation, strict JOSE validation, request timeouts, verified email and recovery.
- Remediation status (2026-10-12): short-lived issuer/audience/JTI/token-version access tokens, hashed 30-day rotating refresh sessions, logout/account-deletion revocation, JOSE algorithm checks and remote-key timeouts are implemented. PostgreSQL smoke verified issuance, rotation, old-token replay rejection, logout revocation and account-deletion invalidation. Email verification/reset, breached-password screening, provider nonce coverage, refresh-family reuse response and user-facing all-device revocation remain open.

#### H-05 — content safety does not cover image inputs or provider output status

- Location: `Backend/src/services/content-safety-service.mjs`, `Backend/src/services/fal-service.mjs`
- Baseline: user text was moderated, but uploaded faces/images were not classified and `has_nsfw_concepts` was not enforced. Provider output flags are now rejected, and finalized subject/companion uploads receive fail-closed OpenAI image moderation before paid generation. The moderation decision is persisted per upload without storing scores or logging signed photo URLs. A friend-photo permission attestation is visible in iOS and mandatory at the API, including rerolls. Policy enforcement for impersonation, NCII, minors, CSAM escalation, and prohibited content remains open. OpenAI documents that `sexual/minors` is text-only, so this control must not be described as dedicated CSAM detection. Private-only output reduces but does not eliminate abuse risk.

#### H-06 — result and video feature behavior can be misleading

- Location: `Backend/src/services/fal-service.mjs:178-210`
- Talking audio/lip-sync failures return the silent base video as success. The UI can say a talking clip is ready when speech failed. Surface a degraded result explicitly or fail with a retryable error.

#### H-07 — App Store purchase lifecycle is untested and local client state can disagree with server state

- Location: `Aura/Services/SubscriptionService.swift:149-177`, `Aura/Models/SubscriptionTier.swift:146-195`, `Aura/Services/SceneMeViewModel.swift:117-123,563-568`
- The client UI uses `UserDefaults` for remaining quota, while the server separately counts usage. Legacy transactions without an `appAccountToken` are accepted by the client but rejected by the server's account-token check. Replace billable usage display/source with a backend entitlement/usage endpoint and define a secure legacy migration path.

#### H-08 — Google Sign-In is incomplete if enabled

- Location: `Aura/Resources/Info.plist`, `Aura/Core/StyleIA/StyleIASecrets.swift:59-84`, `Aura/Views/AuthView.swift:28-29,143-151`
- `GIDClientID` is empty, so Google is hidden. No matching callback URL type is present in `Info.plist`. This is acceptable only if Google is intentionally excluded from 1.0; otherwise configure and test end-to-end.

#### H-09 — release CI is insufficient

- Location: `.github/workflows/ci.yml`, `AuraUITests/AuraUITests.swift`
- Current uncommitted CI adds unit tests but no Release build/archive validation, UI journey, migration test, dependency audit, secret scan, database integration, object-storage isolation, notification/JWS fixtures, or production configuration validation.

#### H-10 — placeholder scene assets create accuracy/licensing risk

- Location: `Backend/data/scenes.json`, `Aura/Resources/scenes.json`
- All thumbnails use `picsum.photos`; several templates reference Formula 1, NBA, Coachella, and branded-event contexts. Confirm rights, remove placeholder/random imagery, and avoid implying endorsement. Apple requires accurate metadata and rights to displayed material.

### Medium

- **M-01 Accessibility is largely unverified.** Most UI uses fixed point sizes and very few explicit accessibility labels/values. Run Accessibility Inspector, VoiceOver, Dynamic Type through accessibility sizes, contrast, Reduce Motion, and touch-target checks.
- **M-02 Device/layout matrix is unverified.** The target supports iPhone and iPad plus landscape, but only one iPhone simulator was launched. Test smallest supported iPhone, large iPhone, iPad split view, all declared orientations and safe areas.
- **M-03 Large-media memory behavior is unmeasured.** `PhotosPickerItem` loads full `Data`/`UIImage`, filters render full images, and video watermarking/export can be expensive. Profile on low-memory real devices.
- **M-04 Notifications are requested when animation starts.** This is contextual, which is good, but denial/background/cold-launch/deep-link behavior is untested.
- **M-05 Launch presentation is minimal.** `UILaunchScreen` is empty. Verify visual continuity and avoid a prolonged black screen.
- **M-06 Localization is not implemented.** The English strings file is a placeholder and UI copy is inline. English-only 1.0 is viable if metadata declares only English, but pseudo-localization and truncation still need testing.
- **M-07 Health and observability are minimal.** No build SHA, dependency readiness, metrics, tracing, SLO, crash service, provider cost dashboard or alert wiring is present.
- **M-08 CORS is wildcard.** Mobile API traffic does not require browser CORS. Restrict allowed origins for any browser clients and minimize headers/methods.
- **M-09 Retention is not operationalized.** Policies mention retention, but there are no cleanup jobs for pending uploads, abandoned originals, expired signed URLs, failed jobs, or account-deletion retries.
- **M-10 Generated output provenance is absent.** Consider visible/metadata disclosure that exports are AI-generated where appropriate; do not claim outputs are unaltered photographs.

## StoreKit and commercial audit

The four required identifiers match between Swift and `SceneMe.storekit`:

- `com.sceneme.creator.monthly`
- `com.sceneme.creator.yearly`
- `com.sceneme.pro.monthly`
- `com.sceneme.pro.yearly`

Local price placeholders are Creator $6.99/month or $54.99/year and Pro $14.99/month or $119.99/year. Actual App Store Connect pricing is unknown and must not be inferred from the local file.

Cost observations using provider pages checked on the audit date:

- Kontext Pro image: about $0.04/output.
- Kontext Pro multi image: about $0.04/output, but the endpoint is labeled experimental.
- PixVerse V6 720p video: about $0.045/second without generated audio; a five-second base clip is about $0.225.
- Talking adds separate TTS and lip-sync/mux calls whose exact cost must be measured from provider billing.
- Apple commission, retries, failed-but-billed jobs, storage, egress, database, Render, OpenAI moderation/enhancement and support are additional.

The owner has now approved a capped 100-credit Pro model for engineering. Measured production COGS and final financial approval remain launch blockers.

## Apple policy comparison

Official sources checked on 2026-10-12:

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Account deletion guidance: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion
- App privacy management: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- App Store Server Notifications V2: https://developer.apple.com/documentation/AppStoreServerNotifications/receiving-app-store-server-notifications
- Subscription metadata: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-information/

Key conclusions:

- Guideline 1.6 requires appropriate security controls; the current storage/job/subscription design is insufficient for sensitive face photos.
- Guidelines 2.1 and 2.3 require a complete, accurate, reviewer-accessible app. Placeholder assets, untested purchases and unavailable live generation are not acceptable.
- Guideline 3.1.2 requires ongoing value, clear subscription information, cross-device access, and seamless upgrades/downgrades. The entitlement backend must be completed.
- Guideline 4.8 is addressed by offering Sign in with Apple when Google is offered; Apple sign-in still requires real credential/config testing.
- Guideline 5.1.1 requires accurate data collection, sharing, retention/deletion and consent disclosures. The app has an explicit AI-processing disclosure and in-app deletion UI, but implementation and policy are not yet fully aligned.
- The bundled privacy manifest is syntactically valid and declares UserDefaults plus linked name, email, user ID, photos/videos, other user content, product interaction and purchase history. App Store Connect answers and assembled third-party SDK manifests still require archive inspection.

This is an engineering compliance review, not legal advice. Owner/counsel must approve final policy and terms.

## Release priorities

1. Freeze a reviewable release branch after owner confirms how to handle the existing dirty working tree.
2. Add PostgreSQL migrations/repository and private S3-compatible storage; import legacy JSON/files and prove rollback.
3. Replace in-process jobs with durable processing, idempotency, per-user/global cost controls and restart recovery.
4. Implement durable Apple entitlements, JWS verification, Notifications V2 and usage API.
5. Align iOS quota/error/recovery behavior to the server and remove the local counter as authority.
6. Add security/authorization/deletion/job/subscription integration tests and meaningful iOS UI tests.
7. Replace placeholder/licensing-risk assets and complete accessibility/device/memory QA.
8. After owner supplies Apple configuration, run StoreKit local scenarios, Sandbox, signed archive, TestFlight and real-device end-to-end testing.

Detailed sequencing and acceptance gates are in `docs/RELEASE_PLAN.md`.

## Remediation update after the baseline audit

The findings above describe the repository as first inspected. Work completed through 2026-10-13:

| Finding | Updated state | Evidence |
| --- | --- | --- |
| C-01 JSON persistence | Implemented, external verification pending | PostgreSQL migration/repository/import added. Fresh PG migration, idempotent rerun, legacy import (24/78/139) and full PostgreSQL smoke passed. Managed backup/restore is not tested. |
| C-02 private media | Implemented, external verification pending | S3-compatible private signed PUT/GET, decode/pixel validation, provider-result ingestion and deletion paths added. No real bucket test. |
| C-03 job durability/idempotency | Implemented, external verification pending | Required UUID idempotency and concurrency gate pass. fal queue request ID/model/phase and video intermediate state persist; a PostgreSQL round-trip test verifies that state; startup resumes status/result; user/account deletion propagates cancellation; deterministic object keys make ingestion replay idempotent. An injected no-spend queue test covers submit/resume/video-stage resume/timeout/cancel. Real paid kill/restart/cancel remains NOT TESTED. |
| C-04 subscriptions | Implemented, Apple verification pending | Official Apple JWS verifier, durable transactions/entitlements, Notifications V2 replay protection, `/subscriptions/sync` and `/me` added. No Apple roots/config/Sandbox test yet. |
| C-05 uncapped Pro | PARTIALLY RESOLVED | Owner approved 3/30/100 grants with 1/2/6/23 weights; ledger, paywall and draft metadata were updated. Real COGS validation and live-price authorization remain blocked. |
| C-06 provider email linking | Fixed in code | Implicit Apple/Google link now requires verified provider email. Fixture regression test remains. |
| H-01 upload validation | Fixed and locally tested | Sharp full decode, byte/pixel ceilings, reorientation and metadata stripping are implemented. Automated checks pass for valid JPEG decode/hash, metadata removal, PNG/truncated/prefix-spoof rejection and pixel ceiling. HTTP byte-limit, broader fuzz corpus and real object-store testing remain. |
| H-02 rate limits | Fixed and tested locally | Migration `002` adds atomic PostgreSQL user/IP windows with HMAC subjects and expiry cleanup. A 12-way race, HTTP `429`/`Retry-After`, and migration rollback/reapply passed on disposable PostgreSQL 16. Production alerting remains. |
| H-05 provider input/output safety | Partial | fal `has_nsfw_concepts` results are rejected by the durable queue contract test. Finalized subject and companion uploads receive fail-closed OpenAI image moderation, with no-network allow/block/provider-failure, persistence-cache, and ingress/final-key separation checks passing. iOS and API require friend-photo permission attestation, including rerolls. Current fal schemas were rechecked and model-specific inputs are used. Real OpenAI screening plus minor/NCII/CSAM and human escalation policy remain NOT TESTED/BLOCKED. |
| H-06 silent talking result | Fixed in code | Talking audio failure now fails clearly instead of returning a silent success. |
| H-07 client quota authority | Fixed in code | UserDefaults usage counter removed; UI reads server `/me`; backend remains enforcement authority. |
| H-09 CI | Improved | PostgreSQL service/migrations, audit, full backend suite, iOS unit/Release build, and a 4-case UI smoke covering authentication, catalog, support and friend-photo permission at Accessibility XXXL are wired. Branch workflow execution and critical end-to-end UI journeys remain. |
| H-10 placeholder/licensing-risk catalog | Fixed in code | All `picsum.photos` URLs were removed. Scene cards now render deterministic offline artwork from app-native gradients and SF Symbols. Formula 1, NBA and Coachella names/prompts plus logo-bearing red-carpet wording were replaced with unbranded generic contexts while retaining stable template IDs for compatibility. Final archive/marketing-rights review remains. |

Canonical current status is `release/RELEASE_READINESS.md`.
