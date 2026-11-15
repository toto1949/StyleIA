# SceneMe 1.0 — App Review Preparation Changelog

## 2026-11-15

### Release candidate and production hardening

- Fast-forwarded `codex/release-1.0` to `origin/main`, restored the release work and resolved three iOS/test conflicts without discarding the safety stash.
- Removed forced development-signing settings and the StoreKit test configuration from app resources; incremented build to 1.0 (2).
- Updated the support email to `contact@zevyntalabs.com` across app, backend, tests and release copy.
- Added and rehearsed migrations 005/006 on disposable PostgreSQL, then applied them to production: RLS is enabled on all 16 SceneMe tables with no client policies, `anon`/`authenticated` retain zero table privileges, and `citext` moved outside `public`.
- Verified Render after the database changes: `/health` and `/v1/scenes` returned HTTP 200.
- Ran `npm test` successfully and `npm audit --omit=dev` with zero known vulnerabilities.
- Ran Xcode 26.6 tests on iPhone 17 Pro / iOS 26.5: 14/14 unit tests and 5/5 UI tests passed.
- Built Release for simulator and attached iPhone, archived for generic iOS, and exported an Apple Distribution-signed IPA for Team `3K82B6HTAT`, bundle `com.sceneme.app`, version `1.0 (2)`.
- Verified `get-task-allow=false`, Sign in with Apple entitlement, privacy manifest presence, StoreKit fixture absence and no release-test bypass markers in the exported binary.
- Revalidated all 15 final screenshots for exact dimensions, RGB/no-alpha properties and visible content.
- Verified App Store Connect: Free Apps Agreement is active; Paid Apps Agreement remains new; Pro yearly is already priced at $119.99; App Privacy, app price/availability, category, review details, subscription ordering/localization/review images and notification URLs still require completion.
- Identified that the entered support URL returns HTTP 404; the verified temporary release URL is `https://styleia.onrender.com/support`.
- No paid provider call, hosting-plan purchase, Paid Apps Agreement acceptance, subscription activation, build upload or App Review submission was performed.

## 2026-11-11

### Live dashboard audit

- Inspected Render and App Store Connect without exporting secrets or changing submission/commercial settings; the existing inactive Supabase project was later resumed for outage recovery as recorded below.
- Confirmed the Render service is live on commit `cb2dfc8`, free plan, one instance, auto-deploy off, with 35 production configuration keys including PostgreSQL, private storage, AI providers, Apple verification and budget controls.
- Recorded that Render logs were unavailable and metrics were empty during the audit.
- Reclassified production availability as blocked after `/health` timed out after 90 seconds and again after 35 seconds with no response.
- Diagnosed the outage read-only: Supabase reports the SceneMe project `INACTIVE`; Render crash-loops at PostgreSQL initialization with tenant/user not found. Render platform status and the service TLS endpoint are healthy.
- Resumed the existing Supabase project on its current plan; it reached `ACTIVE_HEALTHY`, Render recovered, and health/privacy/terms/support/catalog returned HTTP 200.
- Verified the private storage bucket remains non-public and production retained one user, nine uploads, eleven jobs, one credit account, four migration records and eighteen objects.
- Verified migration 004's privilege lockdown: Supabase `anon` and `authenticated` can read/write zero SceneMe tables. Recorded the remaining RLS-disabled defense-in-depth advisory without applying unreviewed policies.
- Verified and re-masked Render's safe runtime values: production mode, mock generation disabled, billing fallback false by blank/default, and App Store online checks enabled.
- Verified both production daily spending caps are configured as positive numeric values without recording or exporting their amounts.
- Looked up current official always-on base pricing for owner review: approximately $25/month Supabase Pro plus $7/month Render 512 MB compute, before bandwidth/overages. No purchase was made.
- Verified App Store Connect build 1 is Validated with correct distribution entitlements, but it predates the current release patches and has no TestFlight assignments/results.
- Audited App Privacy, agreements, app price/availability, review information, subscriptions, Notifications V2 and release behavior; recorded all incomplete fields in the release checklist and readiness report.
- Made no code deployment, plan purchase, agreement acceptance, price/product activation, build upload, TestFlight assignment or App Review submission. The only production-state action was resuming the existing Supabase project on its current plan.

## 2026-10-23

### Safety and recovery

- Created a pre-edit backup at `/Users/Apple/Documents/SceneMe-Production-Audit-Backups/StyleIA-20261020-130612-EDT` with permissions `0700`; verified `.git` and `Aura.xcodeproj` are present.
- Made no production deployment, database mutation, paid provider call, live price activation, App Store upload, or submission.

### iOS changes

- Updated `SceneMeViewModel` so email, Apple, and Google sign-in await the authenticated `/v1/me` state.
- Routed reviewer-state refresh through serialized access-token refresh, preventing an expired stored token from incorrectly showing Free/paywall state after cold launch.
- Preserved a valid Keychain session during temporary backend unavailability; invalid/unauthorized refresh still signs out safely.
- Added account-scoping/expiration regression coverage for temporary review access.
- Added **Profile → Report a Safety Issue** using `contact@zevyntalabs.com` without embedded credentials.
- Added a unit check that the safety-report route is public and credential-free.

### Backend/legal source changes

- Updated terms/support source copy to the owner-approved capped model: Free 3 starter credits; Creator 30 monthly; Pro 100 monthly; annual grants monthly; stored credits do not expire; operations cost 1/2/6/23 credits; failed generations refund credits.
- Added explicit safety-report instructions. These source changes have **not** been deployed.

### Verification performed

- `git diff --check`: PASS.
- Local branch backend `npm test`: PASS; mock/local automation only.
- Isolated `origin/main` backend `npm test`: PASS, including companions, subscriptions, durable credit storage, rate limits, provider state, content safety, uploads, fal queue, smoke, reviewer provisioning/access, S3 compatibility, import guard, and private video-source signing.
- `npm audit --omit=dev`: PASS with zero known vulnerabilities.
- iOS unit tests on iPhone 17 Pro / iOS 26.5 simulator / Xcode 26.6: PASS, 14 tests including StoreKit product contract, reviewer scope/expiration, safety route, media renderers, catalog, and credit constants.
- Post-patch isolated Release simulator build with Xcode 26.6 and `CODE_SIGNING_ALLOWED=NO`: PASS.
- Deterministic iOS UI smoke: PASS, 4/4 tests for auth/validation, Accessibility XXXL, catalog/support, and companion permission attestation.
- Production read-only checks: `/health`, `/privacy`, `/terms`, `/support`, and `/v1/scenes` returned HTTP 200; health reported PostgreSQL.
- Screenshot builder regenerated 15 final PNGs and validation confirmed RGB, no alpha, and exact 1320×2868, 1206×2622, and 2064×2752 dimensions.

### Documentation added

- `docs/APP_STORE_REVIEW_AUDIT.md`
- `docs/APP_REVIEW_TEST_MATRIX.md`
- `docs/APP_REVIEW_NOTES_DRAFT.md`
- `docs/RELEASE_CHECKLIST.md`
- `docs/KNOWN_ISSUES_AND_BLOCKERS.md`
- `docs/CHANGELOG_APP_REVIEW_PREPARATION.md`

### Remaining release gates

- Reconcile and commit the release source in reviewable PRs.
- Obtain/verify App Store distribution signing and validate the exact archive.
- Verify production reviewer access and Render settings read-only.
- Complete App Store Connect product/forms review.
- Complete Sandbox and TestFlight purchase lifecycle tests.
- Complete owner-approved live AI generation/video and real-device QA.
- Obtain financial, metadata, legal/privacy, and final submission approvals.
