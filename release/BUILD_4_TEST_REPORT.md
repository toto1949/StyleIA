# SceneMe 1.0 (4) purchase-unlock candidate

Assessment date: 2026-11-17 (America/New_York)

## Scope

- Explains when an App Store subscription belongs to a different SceneMe login. The existing Sandbox Pro yearly transaction stays bound to its original SceneMe account.
- Awaits backend verification and an updated credit balance before the paywall reports purchase or restore success.
- Applies account-scoped paid entitlements returned by `/v1/me`, with expiry checks and clearing on account switch.
- Grants the first monthly allowance in the same backend mutation that persists a verified Apple transaction; replayed notifications cannot duplicate it.
- Increments the iOS build number to 4. Prices and the four product IDs are unchanged.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Full local backend suite | PASS | `npm test` completed on 2026-11-17. |
| Immediate Pro yearly grant / replay / account conflict | PASS | `npm run test:subscriptions`; 100 paid credits plus 3 starter, one subscription grant after replay, second account rejected. |
| Credit and entitlement persistence round-trip | PASS | `npm run test:credit-storage`; verified purchase grant persisted once. GitHub CI run `44133411700` also passed the complete backend suite against PostgreSQL. |
| iOS Release compile | PASS | `xcodebuild build -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`; compiled app reports CFBundleVersion 4. |
| iOS unit suite | PASS | `xcodebuild test -only-testing:AuraTests` on iPhone 17 Pro simulator; account-scoped paid/reviewer access, grace period, revocation and product contract passed. |
| GitHub CI on PR #21 | PASS | Backend/PostgreSQL and iOS Release compile, unit tests, and critical UI smoke passed in run `44133411700` on commit `175dd6c`. A duplicate run was canceled after merge. |
| Local StoreKit product loading | PASS | The shared scheme's StoreKit file reference was corrected from `../../SceneMe.storekit` to `../../../SceneMe.storekit`. A forced local test then loaded all four products; `/tmp/SceneMeStoreKitFixedPath.xcresult` records two passing tests. The temporary test opt-in edit was reverted. This scheme change affects local Xcode runs, not TestFlight or the archived binary. |
| Local StoreKit transaction lifecycle | BLOCKED | In the same forced run, `localPurchaseRenewalRefundAndExpiry()` failed: after `SKTestSession.buyProduct`, `Transaction.currentEntitlements` still yielded Free for the tagged account and the final purchase reported `.unknown`. The result bundle records one failed test. Purchase, renewal, expiry and refund are not validated locally. |
| Build 4 archive and distribution export | PASS | After the owner restored Xcode account access, `/tmp/SceneMe-1.0-build4.xcarchive` exported to `/tmp/SceneMeExport-build4/SceneMe.ipa`. `DistributionSummary.plist` confirms version 1.0 (4), `com.sceneme.app`, Team `3K82B6HTAT`, cloud-managed Apple Distribution, Sign in with Apple and `get-task-allow=false`. IPA ZIP integrity passed; privacy manifests are present and no `.storekit` file is packaged. SHA-256: `2719d7aa2c44338dbed5dc57301f34f1eeef7d59d1287471eeb422f2b53e8943`. |
| Build 4 App Store Connect upload/processing | PASS | `xcodebuild -exportArchive` with destination `upload` exited 0 at 2026-11-17 22:42 EST. Connect listed version 1.0 (4) as **Processing** at 22:47 and then **Ready to Submit** in its available Builds table at about 22:49. Build Metadata reports **Validated**, `com.sceneme.app`, 1.0 (4), iPhone/iPad, arm64, Sign in with Apple entitlement, `get-task-allow=false`, symbols included and no non-exempt encryption. The build detail confirms two internal groups, one with a tester. Xcode warned that iOS 27 SDK will be required starting April 2027; this build uses iOS 26.5 SDK. |
| Backend production deploy | PASS | PR #21 merged as `aee87be`; Render deploy `dep-dbu8nr95efls739jr570` reached `live` on 2026-11-17. `/health` returned HTTP 200 and startup logs show mock generation disabled. No real post-deploy purchase was tested. |
| Production health latency spot check | BLOCKED | `/health` returned HTTP 200 in 22.53 seconds on one request at 22:49 EST, then HTTP 200 in 0.35 seconds on an immediate repeat. The first sample is consistent with a cold start; these two samples do not establish typical latency. The free Render/Supabase setup remains a reliability risk for App Review. |
| Build 4 TestFlight install | PASS | The owner installed build 4 from TestFlight. `devicectl device info apps` independently confirms SceneMe 1.0 (4) on the connected iPhone 17 Pro Max. |
| Build 4 real-device same-account Sandbox purchase/restore | BLOCKED | The owner chose the Sign in with Apple SceneMe account. Production PostgreSQL still shows tier Free, 3 starter credits, zero subscription grants and zero transactions for that user after a reported second Sandbox purchase. The first reported Pro result was actually on the separate reviewer login: a device Profile capture showed its temporary Pro access, 92 credits and an account-mismatch warning. Render recorded repeated `/v1/subscriptions/sync` 409 account-conflict errors, including after the second reported purchase. The phone's actual Sandbox Apple Account and SceneMe Profile state must be reconciled; no new transaction or grant reached the selected account. |
| Real paid production purchase | BLOCKED | TestFlight always uses Sandbox. Production charges require Apple approval and owner authorization after financial validation. |

## Release decision

**BLOCKED** for App Review submission until a same-account Sandbox purchase on installed build 4 creates one 100-credit Pro grant and unlocks the tier and features on the physical device. If the 3 starter credits remain unused, the displayed balance should be 103. Verify restore, renewal/expiry, refund, and account switching separately. App Store version 1.0 still selected build 2 at last inspection. TestFlight purchases cannot be charged production transactions.
