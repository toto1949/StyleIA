# SceneMe 1.0 QA Checklist

Last execution: 2026-11-15. Check boxes are intentionally left open unless the exact case was executed. Record build SHA, environment, device/OS, tester, date and evidence URL for every manual run.

## Automated commands

```bash
cd Backend
npm ci
npm audit --omit=dev
npm run db:migrate
npm test

cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project Aura.xcodeproj -scheme Aura \
  -destination 'platform=iOS Simulator,id=AE589C5A-5ADE-4BCC-B4E7-11B9107BABC8' \
  -only-testing:AuraTests CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -project Aura.xcodeproj -scheme Aura -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

## Current report

| Area | Status | Verification | Outstanding action |
| --- | --- | --- | --- |
| Backend unit/mock smoke on PostgreSQL | PASS | `npm test`, 2026-11-15; complete suite ended with `ALL SMOKE TESTS PASSED` and `CI smoke OK` | Mock provider responses are not live-provider proof. |
| PostgreSQL migration idempotency | PASS | Disposable PostgreSQL applied 001–006; all 16 tables had RLS enabled and `citext` moved to `extensions`. Production 005/006 applied successfully and Render stayed healthy | Repeat rollback rehearsal on managed staging. |
| Legacy import | PASS | Dry-run and apply preserved 24 users/78 uploads/139 jobs | Backup then repeat on production snapshot. |
| Backend smoke on PostgreSQL | PASS | Full suite completed on disposable PG 16 | Add object-storage/JWS fixtures. |
| Durable user/IP rate limits | PASS | 12 concurrent attempts produced exactly 5 allowed/7 denied; HTTP 429 included structured code and `Retry-After` | Run multi-instance staging load test and wire alerts. |
| Per-user generation concurrency | PASS | Two simultaneous HTTP generation requests produced exactly one 200 and one 429 | Repeat with real queue/provider staging path. |
| Durable fal queue contract | PASS | Injected no-spend test covered submit, request-state persistence callback, image resume without resubmit, video/TTS stage resume, timeout preservation, cancellation, NSFW-output rejection, model-specific inputs and PixVerse's 2,048-byte prompt bound | Paid provider kill/restart/cancel remains NOT TESTED. |
| Provider-state PostgreSQL round trip | PASS | `npm run test:provider-state` persisted and reloaded request ID, model, phase and intermediate video URL | Repeat in a real process-kill staging test. |
| Pre-generation image safety contract | PASS | `npm run test:content-safety` verified OpenAI multimodal request shape, allow/block, fail-closed provider error, cached PostgreSQL allow state, and separate client-ingress/internal-final keys without network access | Execute a consented real staging image check; complete NCII/CSAM escalation policy. |
| Upload decode and sanitization | PASS | `npm run test:upload-validation` verified valid JPEG decode, output hash, EXIF/orientation removal, PNG rejection, truncated/prefix-spoof rejection and configured pixel-limit rejection | Add a larger malformed-image corpus and real signed-object upload cases. |
| Companion-photo permission gate | PASS | Backend smoke rejects missing attestation with `COMPANION_CONSENT_REQUIRED`; deterministic UI automation verifies the friend-photo disclosure and default-off permission control; the view no longer clears an in-progress opt-in when SwiftUI re-evaluates its content | Exercise the real photo picker and submission flow in TestFlight. |
| Cross-user API isolation | PASS | Second account received 404 for foreign job read/delete and upload reuse; history was empty | Repeat against real private object storage. |
| Authentication session lifecycle | PASS | PostgreSQL smoke verified 15-minute access token metadata, refresh rotation, replayed-old-token rejection, logout revocation and account-deletion invalidation | Add clock-boundary, multi-device/family-reuse and live social-provider cases. |
| Dependency audit | PASS | `npm audit --omit=dev`, 2026-11-15: 0 known vulnerabilities | Re-run for every RC. |
| iOS unit tests | PASS | 14/14 on 2026-11-15, including approved credit constants, StoreKit product/price contract, account-scoped/expiring review access and safety-report routing; iPhone 17 Pro iOS 26.5 simulator, Xcode 26.6; `/tmp/SceneMeDerivedData-test/Logs/Test/` | Increase live API/offline/entitlement coverage. |
| Debug app first screen | PASS | Simulator launch and accessibility tree inspected | Not an end-to-end journey. |
| App Store Release archive | PASS | Xcode 26.6 archive/export succeeded 2026-11-15. IPA is Apple Distribution-signed for `3K82B6HTAT`, `com.sceneme.app`, version `1.0 (2)`, `get-task-allow=false`; StoreKit test data absent and privacy manifest present. App Store Connect now reports Ready to Submit | Install this exact build and complete physical-device validation. |
| Deterministic iOS UI smoke | PASS | Reran 2026-11-15: auth validation, Accessibility largest text, neutral catalog/support, default-off companion permission and screenshot/paywall contract; 5/5 passed | Extend through live authentication and core journeys. |
| Critical iOS UI journeys | NOT TESTED | Deterministic auth/catalog/support/permission coverage exists, but no real onboarding, generation, purchase, export or deletion automation | Add backend-controlled end-to-end journeys. |
| Real fal/OpenAI | NOT TESTED | No spending authorization | Run staging golden cases and record provider IDs/cost. |
| S3/R2 isolation/deletion | NOT TESTED | No credentials/provider selected | Execute two-user test and restart persistence check. |
| Apple JWS/notifications | NOT TESTED | Implementation compiles; no Apple roots/fixtures/config | Add verified fixtures and Sandbox notification test. |
| StoreKit local lifecycle | NOT TESTED | Automated configuration-contract test verifies all four recurring products, duration and Swift mappings; no transaction lifecycle passed | Run purchase/pending/restore/upgrade/downgrade/refund scenarios in an attached StoreKit test environment. |
| Sandbox/TestFlight | BLOCKED | Build 2 is Ready to Submit and assigned to the internal tester group; Notifications V2 production/Sandbox URLs are configured. No signed purchase, notification or device journey has passed | Install build 2 and complete the matrix below. |
| Physical devices/accessibility/memory | BLOCKED | Release build signed successfully for the attached iPhone, but live journeys, VoiceOver and Instruments were not executed | Install the TestFlight build; test iPhone/iPad and profile with Instruments. |

## Backend and security

- [ ] Email signup, sign-in, wrong password, unknown account, duplicate signup and deleted-session rejection. **Signup/sign-in and deleted access/refresh rejection PASS; negative email cases remain NOT TESTED.**
- [x] Refresh rotates atomically, replayed old refresh credentials fail, logout revokes the presented session, and account deletion invalidates access and refresh credentials. **Automated PostgreSQL smoke PASS.**
- [ ] Apple sign-in first use, repeat use, hidden email, cancelled consent, expired/wrong-audience/wrong-algorithm token.
- [ ] Google intentionally excluded, or callback/config and all token failures tested.
- [ ] Unverified provider email cannot link an existing account.
- [ ] User A cannot view, sign, generate from, cancel or delete User B's upload/job/result. **Database/API job, upload-use and history checks PASS; signed S3/R2 access remains NOT TESTED.**
- [ ] Non-JPEG, truncated JPEG, MIME spoof, oversized bytes, oversized pixels and decompression bomb are rejected. **PNG, truncated/prefix-spoof JPEG and configured pixel ceiling PASS at the decoder; HTTP byte-limit and a broader malformed/decompression-bomb corpus remain NOT TESTED.**
- [ ] Direct private-object GET without a signed URL fails.
- [ ] Signed upload/download expiration behaves as configured.
- [ ] Duplicate `Idempotency-Key` returns one job and debits credits once. **Ledger unit contract PASS; HTTP/PostgreSQL rerun required.**
- [ ] Concurrent jobs above image/video per-user limits reject before provider submission. **Image HTTP concurrency PASS; video/real-provider path NOT TESTED.**
- [ ] Pending job starts after restart. Processing job with persisted provider state resumes; a pre-submit interruption fails safely and all job credits are refunded. **Queue contract PASS; real process-kill test NOT TESTED.**
- [ ] Provider timeout, validation, rate-limit, billing and transient failures map to safe retryable/nonretryable errors.
- [ ] Provider request can be resumed/cancelled without duplicate billing. **No-spend queue contract PASS; real fal billing/restart/cancel remains NOT TESTED.**
- [ ] One-time Free grant and 30/100 monthly grants are idempotent across two app instances.
- [ ] Annual subscriptions receive exactly one grant per subscription-month anniversary, up to 12 per annual transaction.
- [ ] Stored balances do not expire on a calendar boundary or subscription lapse.
- [ ] Standard/premium/silent/talking jobs debit 1/2/6/23 and failure/cancellation refunds exactly once.
- [ ] Daily user/global cost ceilings stop work before provider submission. **Automated configuration/unit assertions PASS; owner-set production values and external alerts remain BLOCKED.**
- [ ] Result deletion and account deletion remove database rows and all private object keys.
- [ ] Logs contain no passwords, access tokens, Apple JWS/private keys, signed storage URLs or photo bytes.
- [ ] Backup restore reconstructs counts and representative auth/job/subscription/media metadata.

## Subscription lifecycle

- [x] Approved plan and operation weights have deterministic unit coverage. **PASS (no Apple transaction).**

- [ ] Four products load with App Store Connect prices and periods.
- [ ] New Creator monthly/yearly and Pro monthly/yearly purchase.
- [ ] Ask to Buy/pending leaves access unchanged and communicates status.
- [ ] User cancellation leaves no false success state.
- [ ] Restore on same SceneMe account and fresh device.
- [ ] Tagged entitlement does not transfer when SceneMe account changes.
- [ ] Upgrade/downgrade timing and highest active tier.
- [ ] Renewal, expiration, billing retry, grace period, refund and revocation.
- [ ] Notifications V2 duplicate UUID is idempotent; out-of-order older notification cannot overwrite newer entitlement.
- [ ] Missed notification is repaired through reconciliation.
- [ ] Subscription-management link opens Apple's management UI.
- [ ] Account deletion explains Apple subscription cancellation is separate.

## iOS critical journeys

- [ ] Fresh launch → email account creation → onboarding/home.
- [ ] Sign in with Apple and repeat launch from Keychain session.
- [ ] Limited Photos access, denied access, cancellation, unsupported/corrupt/huge photo.
- [ ] Solo scene, custom scene, friend companion, pet companion, remix and reroll.
- [ ] Generation progress on fast/slow/lost network; background, force-quit and cold-launch recovery.
- [ ] Failure and retry preserve input without duplicate charge.
- [ ] Video styles, talking TTS/lip-sync, captions, playback, background and notification return.
- [ ] History empty/loading/error/pagination and expired signed-URL refresh.
- [ ] Save denied/limited/allowed, share image/video, watermark rules, disk-full/export error.
- [ ] Paywall loading/retry, disclosures, purchase/pending/restore/manage.
- [ ] Result deletion, consent revocation, sign-out/account switch and complete account deletion.
- [ ] Airplane mode and 3G/high latency using Network Link Conditioner.

## Device, accessibility and performance matrix

- [ ] Smallest supported iPhone portrait/landscape.
- [ ] 6.9-inch iPhone portrait/landscape.
- [ ] 13-inch iPad portrait/landscape/split view.
- [ ] Light/dark appearance, increased contrast, Reduce Motion and Reduce Transparency.
- [ ] Dynamic Type default through Accessibility XXXL; no clipped purchase/legal controls.
- [ ] VoiceOver order, labels, traits, values and announcements through every critical journey.
- [ ] Switch Control/full keyboard focus where applicable; 44-point targets.
- [ ] Color contrast and color-independent error/selection indicators.
- [ ] Instruments: launch, photo decode, generation polling, filters, video playback and export.
- [ ] Memory warning/termination with large photo and 250 MB video; no persistent temp-file growth.

## TestFlight release sign-off

- [ ] Exact version/build recorded and immutable.
- [x] App Store processing completed for build 2; no processing rejection is visible. **Device/TestFlight validation remains open.**
- [ ] Owner, engineering and one external tester complete critical journey on physical devices.
- [ ] Staging/production environment marker and backend build SHA recorded.
- [ ] Crash-free run, API latency, generation failures, Apple verification failures and cost dashboard reviewed.
- [ ] No P0/P1; accepted P2/P3 defects linked with owner sign-off.
