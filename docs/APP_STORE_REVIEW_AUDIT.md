# SceneMe 1.0 — App Store Review Audit

Last updated: 2026-11-11 (America/New_York)
Audit branch: `codex/release-1.0`
Repository: `toto1949/StyleIA`

## Audit status

This is an evidence log, not a declaration that the app is ready. `PASS` means the stated check was actually performed. `BLOCKED` or `NOT TESTED` is used where live credentials, a real purchase, a paid AI call, App Store Connect action, or owner approval is required.

## Safety baseline and backup

Before any file was changed, the repository was copied outside the working tree to:

`/Users/Apple/Documents/SceneMe-Production-Audit-Backups/StyleIA-20261020-130612-EDT`

The backup directory permissions are `0700`. The copy includes `.git`, the Xcode project, source, local backend data, uploaded media, assets, tests, and documentation. Only dependency/build outputs (`Backend/node_modules`, DerivedData, `build`, and `.build`) and the transient Git fsmonitor socket were excluded. The resulting backup was approximately 441 MB and was checked for both `.git` and `Aura.xcodeproj`.

No branch switch, reset, clean, broad merge, code deployment, paid AI generation, App Store submission, pricing change, or credential export has been performed. On 2026-11-11 the existing inactive Supabase project was resumed on its current plan to recover the production API; no schema/data edit or new resource was created.

## Initial repository state

| Item | Verified state |
|---|---|
| Working directory | `/Users/Apple/Documents/GitHub/StyleIA` |
| Current branch | `codex/release-1.0` |
| Local HEAD | `d3d9274d3a5ebe47748ac9169ecbef9075e572fe` — “Migrate recoverable legacy media privately” |
| Upstream | `origin/codex/release-1.0` |
| `origin/main` | `cb2dfc8a1929750ba74cb34902f24fd4241245cb` — “Re-sign private SceneMe images before video animation” |
| GitHub Actions | Latest `main` CI run `39454279680` completed successfully on 2026-10-20 |
| Xcode | 26.6 (build 17F113), selected with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` |
| Bundle / team | `com.sceneme.app` / `3K82B6HTAT` |
| Version / build | `1.0` / `1` |
| Deployment target | iOS 17.0 |
| Signing | Automatic; Apple Development identity available locally; Apple Distribution identity not found locally |
| Physical device | iPhone connected as `00008150-000C09081152401C` |

`git diff --check` passed at the start of the audit. The working tree was intentionally dirty: 31 tracked paths were modified or deleted, with 1,334 insertions and 424 deletions, plus untracked release assets, tests, documents, and an AI-processing consent screen.

### Modified tracked paths present before this audit

- `Aura.xcodeproj/project.pbxproj`
- `Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme`
- `Aura/App/SceneMeAppDelegate.swift`
- `Aura/App/SceneMeRootView.swift`
- `Aura/Components/CompanionUploadView.swift`
- `Aura/Components/CustomSceneComposerView.swift`
- `Aura/Components/SceneCardView.swift`
- `Aura/Components/ZoomableScrollView.swift`
- `Aura/Core/StyleIA/StyleIASecrets.swift`
- `Aura/Models/GenerationRequest.swift`
- `Aura/Models/SceneMeLegal.swift`
- `Aura/Models/SubscriptionTier.swift`
- `Aura/Resources/Info.plist`
- `Aura/Resources/PrivacyInfo.xcprivacy`
- `Aura/Resources/scenes.json`
- `Aura/Services/APIService.swift`
- `Aura/Services/GenerationService.swift`
- `Aura/Services/SceneMeNotifications.swift`
- `Aura/Services/SceneMeViewModel.swift`
- `Aura/Services/SessionStore.swift`
- `Aura/Services/SocialAuthService.swift`
- `Aura/Services/SubscriptionService.swift`
- `Aura/Utilities/SceneMeVideoWatermark.swift`
- `Aura/Views/AuthView.swift`
- `Aura/Views/PaywallView.swift`
- `Aura/Views/ScenePickerView.swift`
- `AuraTests/AuraTests.swift`
- `AuraUITests/AuraUITests.swift`
- `AuraUITests/AuraUITestsLaunchTests.swift` (deleted locally before audit)
- `README.md`
- `SceneMe.storekit`

### Untracked paths present before this audit

- `APP_STORE_SUBMISSION.md`
- `Aura/Views/AIProcessingConsentView.swift`
- `AuraTests/StoreKitConfigurationTests.swift`
- `docs/QA_CHECKLIST.md`
- `docs/RELEASE_AUDIT.md`
- `docs/RELEASE_PLAN.md`
- `release/`
- Twelve new Scene asset image sets: Art Gallery, Dubai Rooftop, Grand Prix Paddock, Hotel Lobby, Maldives Villa, Northern Lights, Paris Cafe, Sahara Desert, Santorini, Times Square, Tokyo Shibuya, and Mediterranean Yacht.

## Architecture verified from source

- SwiftUI iOS app with an observable `SceneMeViewModel` coordinating authentication, generation, gallery persistence, StoreKit entitlements, exports, and deletion.
- Keychain-backed access and rotating refresh tokens; account-scoped local history, favorites, custom scenes, and source photo.
- Node.js API on Render with PostgreSQL persistence, private S3-compatible Supabase Storage, signed URLs, durable credit ledger, rate limits, idempotency keys, provider-state recovery, and background generation recovery.
- fal.ai image/video/TTS/lip-sync providers and OpenAI-backed template improvement/moderation are server-side only.
- StoreKit 2 client and server-side App Store transaction verification/notifications.
- Four preserved product IDs: Creator monthly/yearly and Pro monthly/yearly.

## Production observations (read-only)

| Check | Result | Evidence |
|---|---|---|
| API health | PASS / RELIABILITY BLOCKED | After the Supabase restore, `/health` returned HTTP 200 and `{"ok":true,"database":"postgresql"}` in 0.40–0.85 seconds; the free plans can repeat the outage/cold start |
| Public privacy page | PASS | `/privacy` returned HTTP 200 after recovery |
| Public terms page | PASS | `/terms` returned HTTP 200 after recovery |
| Public support page | PASS | `/support` returned HTTP 200 after recovery |
| Scene catalog | PASS | `/v1/scenes` returned HTTP 200 after recovery |
| Render deployment | PARTIAL | Dashboard confirms `srv-d98llertqb8s7399g35g`, live commit `cb2dfc8`, `/health`, one free Virginia instance and auto-deploy off; dashboard warns free instances may take 50+ seconds to wake |
| Production configuration | PARTIAL | Thirty-five variable names include every strict production PostgreSQL, private-storage, AI-provider, Apple-verification, encryption and budget key. `NODE_ENV=production`, mock generation false, billing fallback blank/false by default, App Store online checks true and positive user/global caps were verified and re-masked. Cap amounts, lifecycle, backups and alerts remain unverified |
| Private storage configured | PARTIAL | Required S3-compatible variable names are present and source is owner-scoped/signed; bucket policy, lifecycle, deletion and restore still require live verification |
| Production observability | BLOCKED | The connector log API returned a platform 503 and metrics were empty, but the signed-in dashboard exposed the crash loop. Render platform status reported all systems operational |
| Database recovery | PASS / RELIABILITY BLOCKED | SceneMe was resumed from `INACTIVE` to `ACTIVE_HEALTHY`. Production retained one user, nine uploads, eleven generation jobs, one credit account, four migration records and eighteen private storage objects |
| Data API isolation | PARTIAL | Migration 004 revokes all access from `anon`/`authenticated`; live privilege checks confirm 0 readable/writable tables. Supabase still flags all 16 `public` tables because RLS is disabled |

## App Store Connect observations (read-only, 2026-11-11)

- SceneMe AI Photo Studio, Apple ID `6822467260`, version 1.0 is in **Prepare for Submission** under Zevynta Labs LLC.
- Build 1 is **Validated** and **Ready to Submit** with the correct bundle/team, Sign in with Apple, arm64, `get-task-allow=false`, symbols, iPhone/iPad support and non-exempt encryption set to No. It predates the current reviewer/safety patches and has no assigned TestFlight groups/testers, installs or completed test results.
- App Privacy is not started; Privacy Policy URL and User Privacy Choices URL are blank.
- App Review sign-in, contact and notes are blank. Automatic release is selected instead of owner-controlled manual release.
- App price schedule and storefront availability are unset. Primary category appears unset. Content Rights says no third-party content, age rating is 4+, and DSA status is non-trader; each needs owner/counsel review against actual AI/photo/subscription behavior.
- The updated Apple Developer Program License Agreement awaits Account Holder acceptance. Only the Free Apps Agreement is visible; Paid Apps Agreement/tax/banking readiness is not established.
- All four preserved subscription IDs exist in SceneMe Membership and are Prepare for Submission. Creator monthly/yearly and Pro monthly show the approved US prices; Pro yearly has no price configured. Pro is incorrectly below Creator in service-level order, monthly/yearly variants are split across levels, group localization is missing, Creator monthly copy is inaccurate, and every product lacks its review screenshot.
- Production and sandbox App Store Server Notification URLs are unset. The first subscriptions are not attached to version 1.0, and billing grace period is not configured.

## Branch reconciliation

The local working branch and production backend must not be merged or deployed wholesale:

- `origin/main` contains newer backend production fixes absent from local HEAD: private-source URL re-signing before video, reviewer provisioning/access, Supabase pooler TLS, Apple root certificate provisioning, S3 compatibility, and database privilege hardening.
- The current working tree contains substantial newer/unpublished iOS work absent from `origin/main`: server credit display, AI-processing consent, subscription price handling, StoreKit tests, screenshot mode, refreshed history triggers, account/session rotation changes, new assets, and UI polish.
- Deploying the backend from the current local HEAD would regress production. Replacing the local iOS files with `origin/main` would discard unpublished release work.

## Findings

### P0 — Submission/security blockers

#### P0-01 — Release candidate is not represented by a clean, reviewable commit

**Evidence:** The working tree contains extensive modified and untracked iOS release work, while `origin/main` contains newer backend fixes. There is no single commit that can currently be archived, reproduced by CI, and reviewed as the intended SceneMe 1.0 source.

**Risk:** An archive may omit untracked source/assets or include a different backend contract than the tested commit.

**Required action:** Integrate the verified iOS patches and the already-tested backend fixes into a dedicated release branch in small commits, then run CI and archive that exact commit. Do not perform a broad merge.

#### P0-02 — Live IAP lifecycle and first-subscription submission remain unverified

**Evidence:** StoreKit source and a local `.storekit` configuration exist, but Apple Sandbox/TestFlight purchase, pending, renewal, upgrade/downgrade, refund/revocation, grace period, restore, and server notification flows have not been executed in this audit. Apple requires first IAPs/subscriptions to be submitted with a new app version when applicable.

**Risk:** Purchase failure or incomplete subscription review metadata can cause rejection under Guidelines 2.1, 3.1.1, or 3.1.2.

**Required action:** Complete StoreKit local testing, Sandbox testing, and TestFlight testing; verify all four products are Ready to Submit or otherwise eligible and attach each first subscription to version 1.0 before submission.

#### P0-03 — Real-device end-to-end release test is outstanding

**Evidence:** A physical iPhone is connected, but no paid production AI call or live purchase was authorized. The full reviewer journey has not been executed from an archived/TestFlight build.

**Risk:** Simulator/unit success cannot prove Sign in with Apple, StoreKit storefront behavior, photo permissions, backgrounding, video playback, export, or reviewer access in the submitted binary.

**Required action:** Run the test matrix on TestFlight with approved test budget and Sandbox accounts before submission.

#### P0-04 — App Store submission forms and paid-commerce agreements are incomplete

**Evidence:** App Privacy is not started; app pricing/availability and primary category are unset; review credentials/contact/notes are blank; subscriptions are misordered/incomplete; the Developer Program agreement is pending and no Paid Apps Agreement is visible.

**Risk:** The version and first subscriptions cannot be submitted successfully, and incomplete or inaccurate privacy/rights/rating information creates rejection and legal risk.

**Required action:** The Account Holder completes agreements/tax/banking. Engineering prepares audited form answers and review materials; owner/counsel approves commercial, privacy, rights, age-rating and DSA answers before entry.

#### P0-05 — Production backend is not reliably reachable

**Evidence:** Supabase reports the SceneMe project as `INACTIVE`. Render repeatedly restarts after `PostgresStore.init` receives `ENOTFOUND tenant/user postgres.rviuuhzckyzpunuzvntw not found`. Two independent `/health` requests received no bytes and timed out after 90 and 35 seconds. DNS/TLS succeeded and Render's public status reported all systems operational, isolating the failure to the application/database path.

**Risk:** App Review may see broken authentication, catalog, generation, purchases or deletion even if the binary is correct.

**Recovery performed:** The existing project was resumed on its current plan without changing prices or resources. Supabase reached `ACTIVE_HEALTHY`; the private bucket remained non-public; database/object counts survived; Render stopped crash-looping; and all five public endpoints returned HTTP 200.

**Required action:** Move Supabase and Render to owner-approved always-on plans so the database cannot auto-pause and the API cannot cold-start. Verify sustained availability, cold/warm latency, logs, alerts and rollback before TestFlight approval.

### P1 — Critical functional issues

#### P1-01 — Reviewer grant refresh race and expired-token path — RESOLVED IN WORKING TREE

**Affected file:** `Aura/Services/SceneMeViewModel.swift`

**Original evidence:** The local `signIn`, `signUp`, Apple, and Google methods adopted the session but did not await `refreshAccountAccess()`. `adopt(auth:)` launched an unstructured task, and `/v1/me` could receive an expired stored access token.

**User impact:** The designated reviewer can see Free/paywall state immediately after login, or after restoring an expired access token on cold launch, even though the server grant is valid.

**Resolution implemented:** All authentication paths now await account refresh. The refresh uses the serialized token-refresh path before `/v1/me`, preserves the Keychain session during temporary backend unavailability, and signs out on invalid authorization. `serverReviewGrantIsAccountScopedAndExpiring` passed and covers account mismatch, ordinary production entitlements, expiration, and sign-out clearing. TestFlight verification remains required; there is no email-only or global bypass.

#### P1-02 — Release archive signing is blocked locally

**Evidence:** Only Apple Development identities were found; no Apple Distribution identity was available to the local keychain during the audit.

**Impact:** A locally signed App Store archive cannot yet be proven. Automatic signing through the configured Apple account may resolve this, but it has not been verified.

**Required action:** Confirm the correct Apple team in Xcode, allow Xcode to obtain App Store distribution signing assets, archive, and run Organizer validation. Do not replace certificates or keys without a confirmed need.

### P2 — Reliability, UX, and compliance risks

#### P2-01 — Historical media refresh exists but needs regression coverage and real data verification

**Evidence:** The local root view refreshes history on foreground and Gallery selection. `mergeHistory` accepts the server's freshly signed image URL and merges clip libraries. The production backend's `sceneJobResponse` re-signs image, primary video, and each clip URL from private object keys.

**Remaining risk:** Old rows without object keys, missing objects, pagination beyond the current page, and real second-device behavior are unverified. Missing records must not be silently deleted.

#### P2-02 — Reported video HTTP 503 is not yet reproduced

**Evidence:** `origin/main` includes source-image re-signing immediately before fal.ai video submission, owner matching, idempotency, durable provider state, retries, ingestion to private storage, signed result URLs, concurrency limits, cost controls, and refunds. Latest `main` CI passed. No production paid generation was made in this audit.

**Remaining risk:** Render cold starts, provider timeouts, app polling timeout, expired playback URLs, or a completed server job not refreshed by the app may still explain the observed device failure. Production logs must be inspected without exposing prompts or media.

#### P2-03 — App Store metadata and privacy answers require field-by-field verification

**Evidence:** The app record is accessible, but the App Privacy form, updated age rating answers, Digital Goods questionnaire, subscription review screenshots, review contact/demo credentials, export declaration, and build attachment are not yet all evidenced.

#### P2-04 — Orientation and iPad experience require product decision and device testing

**Evidence:** iPhone supports portrait and both landscapes; iPad supports all orientations. The supplied marketing requirement asks for a separate iPad layout, but no actual iPad release-layout test is yet recorded.

### P3 — Cleanup candidates (no deletion authorized)

- The locally deleted `AuraUITestsLaunchTests.swift` must be confirmed intentionally superseded before removal is committed.
- Debug/screenshot UI-test fixtures are compiled only for simulator or `DEBUG`, but release preprocessing and archive inspection must confirm no reviewer/debug mode is present in the App Store binary.
- Duplicate/obsolete scripts and assets will be classified only after Xcode target membership and references are verified. No ambiguous file will be deleted without owner approval.

## Verified safeguards already present

- Server-owned durable credits with the approved 3 / 30 / 100 grants and 1 / 2 / 6 / 23 debit schedule.
- Refunds for failed generation and safe restart failure handling.
- Per-user concurrency and durable rate limits.
- Per-user and global daily budget checks.
- Private object keys scoped by user, short-lived signed downloads, upload validation/sanitization, bounded downloads, and account-deletion cleanup.
- Idempotency keys for expensive scene, reroll, and video operations.
- Server-side tier checks; client tier data is not the billing authority.
- Keychain session storage and refresh-token rotation.
- Account deletion removes account data and private media where configured, while preserving anonymized transaction records needed for financial integrity.
- Release configuration uses the production HTTPS API and does not compile the local simulator test bypass.

## Test evidence to date

| Command/check | Status | Notes |
|---|---|---|
| `git diff --check` | PASS | No whitespace errors at baseline |
| Latest `main` GitHub Actions CI | PASS | Run `39454279680`, backend + iOS jobs completed successfully |
| `npm test` on local backend | PASS | Mock/local test suite only; does not prove production fal.ai behavior |
| `npm test` on isolated `origin/main` backend | PASS | Full suite including reviewer, S3 compatibility, credit/rate/provider state and private video-source signing |
| `npm audit --omit=dev` | PASS | Zero known production dependency vulnerabilities at execution time |
| iOS unit tests with Xcode 26.6 | PASS | 14 tests on iPhone 17 Pro/iOS 26.5 simulator; xcresult under `/tmp/sceneme-derived-unit-review-audit` |
| Deterministic iOS UI smoke | PASS | 4/4 auth, Accessibility XXXL, catalog/support and companion-attestation tests; xcresult under `/tmp/sceneme-derived-ui-review-audit` |
| Post-patch Release simulator build | PASS | Isolated DerivedData, `CODE_SIGNING_ALLOWED=NO`; does not prove archive signing |
| Production health/legal/scenes HTTP checks | PASS / RELIABILITY BLOCKED | All endpoints returned HTTP 200 after the authorized Supabase resume; free-tier recurrence remains a release blocker |
| Render configuration inventory | PARTIAL | Required variable names and safe runtime flags were verified without exporting credentials; live storage lifecycle, budget amounts, backups and alerts remain unverified |
| App Store Connect field audit | PASS | Read-only inspection covered version/build, privacy, pricing/availability, subscriptions, agreements, TestFlight and review information; configuration remains BLOCKED as documented |
| Real-device/TestFlight journey | NOT TESTED | Requires owner-approved test execution and TestFlight build |

## Apple compliance sources

### Commercial and AI-content conclusions

- Guideline 3.1.1 says credits or in-app currency purchased through IAP may not expire. SceneMe's implemented design grants the subscription allowance monthly—including during annual terms—but does not erase unused stored credits at renewal, lapse, or cancellation. This is the conservative compliant posture; merely renaming expiring value would not cure an expiration rule. Sandbox/TestFlight and owner/counsel review remain required before activation.
- The approved product identifiers and prices are prepared but must remain inactive until financial validation and TestFlight approval. The accumulated non-expiring Pro balance is a redemption liability and is still a commercial blocker.
- Guideline 1.2 now expressly covers AI content-creation apps. SceneMe has no public feed, profiles, or user-to-user messaging, so user blocking is not applicable to the current product. Prompt/photo safety controls and a credential-free safety-report route exist; mailbox delivery, response ownership, and harmful-content escalation still require operational proof.
- Guideline 2.5.19 requires reviewer transparency. The temporary reviewer preview is server-user-ID scoped, finite, expiring, and documented in the review-notes draft; it is not a hidden global mode or fabricated Apple transaction.

- App Review Guidelines: <https://developer.apple.com/app-store/review/guidelines/>
- October 16, 2026 guideline update: <https://developer.apple.com/news/?id=92th7e5i>
- Upcoming submission requirements: <https://developer.apple.com/news/upcoming-requirements/?id=02032026a>
- Configure IAP for review: <https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases>
- Submit an IAP/subscription: <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/>
- Complete App Review information: <https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review>
- In-app account deletion: <https://developer.apple.com/support/offering-account-deletion-in-your-app/>

## Current readiness decision

**NOT READY FOR APP STORE REVIEW**

The production service has been recovered and the current source tests/reviewer-access patch are promising; App Store Connect also contains a previously validated build. The release is still blocked by free-tier recurrence risk, unreconciled source, incomplete agreements/App Privacy/app availability/subscription setup, absence of a current validated RC, unverified production review account, and missing Sandbox/TestFlight end-to-end evidence.
