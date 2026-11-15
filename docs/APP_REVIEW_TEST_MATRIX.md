# SceneMe 1.0 — App Review Test Matrix

Last updated: 2026-10-23 (America/New_York)

Status meanings: **PASS** was executed with recorded evidence; **BLOCKED** needs owner credentials, authorization, an immutable TestFlight build, or paid external activity; **NOT TESTED** has not been executed. Simulator fixtures and mocked providers never count as live proof.

## Test identities

| Identity | Intended use | State |
| --- | --- | --- |
| Signed out | First launch, legal links, authentication entry | Simulator UI coverage PASS (2026-10-23); physical/TestFlight NOT TESTED |
| New email Free account | Three one-time starter credits, consent, deletion | BLOCKED pending staging/TestFlight account |
| Existing exhausted Free account | Paywall and insufficient-credit handling | BLOCKED pending staging/TestFlight account |
| Creator subscriber | 30-credit monthly grants and Creator gates | Local StoreKit contract PASS; Sandbox/TestFlight BLOCKED |
| Pro subscriber | 100-credit monthly grants and video gates | Local StoreKit contract PASS; Sandbox/TestFlight BLOCKED |
| Apple review account | Temporary server-scoped Pro preview, finite credits | Source/unit tests PASS; production configuration BLOCKED |
| Expired subscription account | Paid gates removed; stored non-expiring balance retained | Backend contract partial; Sandbox/TestFlight BLOCKED |

## Required identity-by-feature matrix

Legend: **A-PASS** = automated/source behavior passed but the real identity was not exercised; **BLOCKED** = needs Sandbox/TestFlight, production reviewer state, or paid-provider authorization. “Expected” is the required result; “observed” states the available evidence.

| Identity | Login | Standard | Premium | Custom | Companion | Reroll | Animation | Talking | Gallery | Restore | Delete |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| New Free | Expected: succeeds, 3 starter credits. Observed: BLOCKED | Expected: 1 credit. A-PASS | Expected: Pro gate. A-PASS | Expected: Creator gate. A-PASS | Expected: Pro gate. A-PASS | Expected: Creator gate. A-PASS | Expected: Pro gate. A-PASS | Expected: Pro gate. A-PASS | Expected: own private jobs only. A-PASS | Expected: no paid entitlement. BLOCKED | Expected: removes account/media. A-PASS |
| Returning Free | Expected: restored session/refresh. A-PASS | Expected: remaining balance enforced. A-PASS | Expected: paywall/insufficient credits. A-PASS | Expected: plan gate. A-PASS | Expected: plan gate. A-PASS | Expected: needs result + credit. A-PASS | Expected: Pro gate. A-PASS | Expected: Pro gate. A-PASS | Expected: refreshed signed URLs. A-PASS | Expected: restores only verified purchases. BLOCKED | Expected: removes account/media. A-PASS |
| Creator | Expected: succeeds. BLOCKED | Expected: 1 credit. A-PASS | Expected: Pro gate. A-PASS | Expected: allowed. A-PASS | Expected: Pro gate. A-PASS | Expected: 1 credit. A-PASS | Expected: Pro gate. A-PASS | Expected: Pro gate. A-PASS | Expected: own media. A-PASS | Expected: Creator restored once. BLOCKED | Expected: deletes app account, warns subscription remains. A-PASS |
| Pro | Expected: succeeds. BLOCKED | Expected: 1 credit. A-PASS | Expected: 2 credits. A-PASS | Expected: allowed. A-PASS | Expected: allowed with consent. A-PASS | Expected: 1 credit. A-PASS | Expected: 6 credits. A-PASS | Expected: 23 credits. A-PASS | Expected: own image/clips. A-PASS | Expected: Pro restored once. BLOCKED | Expected: deletes app account, warns subscription remains. A-PASS |
| Reviewer Pro | Expected: ordinary email auth plus scoped grant. Unit PASS / production BLOCKED | Expected: debit finite review balance. A-PASS | Expected: no paywall, 2 credits. A-PASS | Expected: no paywall. A-PASS | Expected: no paywall + consent. A-PASS | Expected: no paywall, 1 credit. A-PASS | Expected: no paywall, 6 credits. A-PASS | Expected: no paywall, 23 credits. A-PASS | Expected: private review history. A-PASS | Expected: normal StoreKit remains available separately. BLOCKED | Expected: clears grant/session and deletes media. A-PASS |
| Expired subscriber | Expected: signs in without paid tier. BLOCKED | Expected: allowed only if stored balance remains. A-PASS | Expected: balance/feature gates enforced. A-PASS | Expected: current tier gate. A-PASS | Expected: current tier gate. A-PASS | Expected: balance/feature gate. A-PASS | Expected: Pro entitlement removed. A-PASS | Expected: Pro entitlement removed. A-PASS | Expected: existing private history retained. A-PASS | Expected: current Apple state restored, not stale paid access. BLOCKED | Expected: removes account/media. A-PASS |
| Signed out | Expected: auth entry. UI PASS | Expected: unavailable. A-PASS | Expected: unavailable. A-PASS | Expected: unavailable. A-PASS | Expected: unavailable. A-PASS | Expected: unavailable. A-PASS | Expected: unavailable. A-PASS | Expected: unavailable. A-PASS | Expected: no account media. A-PASS | Expected: sign-in required. A-PASS | Expected: no account to delete. A-PASS |

No row above is a claimed real-device PASS unless it explicitly says so. Cross-user isolation is tested separately by the backend smoke suite and the reviewer-grant unit test.

## Reviewer-critical journey

| Test | Expected result | Status | Verification/evidence |
| --- | --- | --- | --- |
| Cold launch signed out | Authentication screen; no hidden debug/reviewer controls | PASS | Release simulator build and UI source guards |
| Invalid email/password | Clear inline error; no crash | PASS | `testAuthenticationModeAndValidation` |
| Largest accessibility text | Authentication remains usable | PASS | `testAuthenticationAtLargestAccessibilityTextSize` |
| Email review login | Server session loads account-scoped temporary access before paywall decisions | PASS (code/unit) / BLOCKED (production) | `serverReviewGrantIsAccountScopedAndExpiring`; production account state needs read-only verification |
| Sign in with Apple | Valid first/repeat login and cancellation handling | NOT TESTED | Requires configured capability and real Apple flow |
| Google sign-in | Hidden when client ID is absent | PASS (source) | Release configuration intentionally has no Google client ID |
| Catalog and support | Neutral scene names; Profile exposes support and safety report | PASS | 2026-10-23 deterministic UI test plus `safetyReportRouteIsPublicAndCredentialFree` |
| Photo selection | Add-only picker, validation, optimization, consent before AI transfer | PASS (source) / NOT TESTED (device permissions) | Source review and unit upload checks |
| Companion photo | Permission attestation is required | PASS | `testFriendCompanionShowsRequiredPermissionAttestation` and backend smoke |
| Standard/premium image | Debit 1/2 credits once; private result; failed job refunds | PASS (automated contract) / BLOCKED (live provider) | Backend suite; paid fal.ai call not authorized |
| Reroll | Debit 1 credit; idempotent; failure refunds | PASS (contract) / BLOCKED (live provider) | Backend suite only |
| Silent/talking video | Debit 6/23 credits; private signed media; resumable job | PASS (contract) / BLOCKED (live provider) | Queue/video-source tests; no paid live call |
| Background/cold-launch recovery | Job resumes or refreshes without duplicate charge | NOT TESTED | Needs Network Link Conditioner/process-kill TestFlight run |
| History on second device | Fresh signed URLs, clips and missing-media state | NOT TESTED | Requires two real devices/accounts and production-like data |
| Save/share/export | Real image/video exports correctly | NOT TESTED | Requires final TestFlight result media |
| Delete account | Account and controlled private media removed; subscription warning shown | PASS (backend automation/source) / NOT TESTED (TestFlight) | Backend smoke and source review |

## Subscription lifecycle

| Scenario | Expected server state | Status |
| --- | --- | --- |
| Product loading | Four exact product IDs with localized StoreKit prices | Local config PASS; Sandbox/TestFlight BLOCKED |
| New purchase | Verified transaction maps to authenticated account | BLOCKED |
| Pending/Ask to Buy | UI remains pending; no entitlement before verification | BLOCKED |
| Upgrade/downgrade | Pro above Creator; entitlement follows Apple effective date | BLOCKED |
| Renewal | Monthly grant occurs once per subscription month | Automated backend contract PASS; Apple Sandbox BLOCKED |
| Annual renewal cadence | Annual subscriber receives monthly allowance, not all at once | Automated backend contract PASS; Apple Sandbox BLOCKED |
| Restore | Current verified entitlement restores without duplicate credit grant | BLOCKED |
| Billing retry/grace | Server reflects billing retry/grace state | BLOCKED |
| Expiration/revocation/refund | Paid access is removed and transaction remains auditable | Automated parser/contract partial; signed Apple events BLOCKED |
| Duplicate notification | Idempotent processing with no duplicate grant | Automated contract partial; Apple test notification BLOCKED |
| Stored credit non-expiration | Existing credit balance is not erased at renewal/lapse | PASS | Credit-ledger tests and source contract |

## Security, privacy, and operations

| Check | Status | Evidence/outstanding action |
| --- | --- | --- |
| Cross-user job/media isolation | PASS | Backend smoke rejects read/delete/use of another user's job/upload |
| Upload type/size/pixel validation and sanitization | PASS | Backend upload-validation suite |
| Private S3-compatible storage and fresh signed URLs | PASS (source/tests) / BLOCKED (dashboard) | S3/video-source checks pass; verify Render/Supabase configuration read-only |
| PostgreSQL durability | PASS | Production `/health` reports PostgreSQL; storage/provider-state tests pass |
| Rate/concurrency/daily budget controls | PASS (tests) / NOT TESTED (managed staging) | Backend automated suite |
| Production mock/fallback disabled | BLOCKED | Inspect production environment without exposing secrets |
| Privacy/terms/support reachability | PASS | Production endpoints returned HTTP 200 on 2026-10-23 |
| Safety reporting and support mailbox | PASS (route/UI) / BLOCKED (operations) | Confirm mailbox delivery and response owner/SLA |
| Archive privacy report/entitlements | BLOCKED | Requires signed immutable App Store archive |
| Crash, memory, poor-network profiling | NOT TESTED | Run Instruments and device matrix |

## Required TestFlight sign-off

Run every row above marked BLOCKED or NOT TESTED that affects the reviewer journey on the exact uploaded build. Record build number, device/OS, account, timestamp, transaction environment, job IDs, and result. Do not include passwords, tokens, photos, private URLs, or provider keys in the evidence log.
