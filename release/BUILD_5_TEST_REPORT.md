# SceneMe 1.0 (5) Test Report

Assessment date: 2026-11-17 (America/New_York)

## Why build 5 is required

On TestFlight build 4, the owner's Sign in with Apple SceneMe account displayed **Pro with 3 credits** after an Apple Sandbox sheet, while production PostgreSQL still recorded Free, 3 starter credits, zero subscription grants and zero transactions. Render returned HTTP 409 for `/v1/subscriptions/sync`: the App Store subscription was linked to another SceneMe account. Build 4's `SubscriptionService.tier` combined a StoreKit-local tier with the server tier, causing the false Pro display. The first apparent Pro result in this investigation was also observed while the device was signed into the separate reviewer account, which has a finite complimentary Pro allowance. Neither observation proves a successful purchase for the selected account.

PR #26 (`03a8023`, merged as `0476994`) makes paid UI and feature gates depend on the account-scoped, unexpired backend entitlement. StoreKit transactions remain purchase proofs sent for server verification. Restore Purchases now attempts server verification when StoreKit finds a matching transaction even if the displayed tier is Free. The app and test bundle build number increased to 5.

## Verification

| Item | Status | Evidence and limit |
| --- | --- | --- |
| Local iOS unit tests | PASS | `xcodebuild test -only-testing:AuraTests` on iPhone 17 Pro iOS 26.5 simulator exited 0. The server-access test now asserts a local Pro entitlement alone leaves the effective tier Free and a revoked server entitlement leaves it Free. StoreKit lifecycle opt-in tests remained skipped. |
| Local iOS UI smoke | PASS | Four critical `AuraUITests` cases (authentication modes, largest text, authenticated catalog/support, companion consent) exited 0 on iPhone 17 Pro iOS 26.5 simulator. These are simulator tests, not purchase validation. |
| Local Release compile and archive | PASS | Generic iOS Release compile, signed archive `/tmp/SceneMe-1.0-build5.xcarchive` and App Store export `/tmp/SceneMeExport-build5/SceneMe.ipa` succeeded. `DistributionSummary.plist` confirms 1.0 (5), `com.sceneme.app`, Team `3K82B6HTAT`, cloud-managed Apple Distribution, Sign in with Apple, symbols and `get-task-allow=false`. IPA ZIP integrity passed; privacy manifests are present and no `.storekit` file is packaged. SHA-256: `51d2741cfcda6ee2ae79091e8e8607968904df3754f5d0084859bdd0b231ea85`. |
| GitHub CI on PR #26 | PASS | Backend/PostgreSQL and iOS Release/unit/UI smoke passed on PR run `44235345285`. A duplicate push run was intentionally canceled after the PR run was underway; its canceled iOS job is not a test failure. |
| Source matches merged main | PASS | `git diff --exit-code 03a8023 0476994 -- Aura Aura.xcodeproj AuraTests` produced no diff. |
| App Store Connect upload | PASS | `xcodebuild -exportArchive` with destination `upload` exited 0 at 2026-11-17 23:20 EST and reported “Upload succeeded.” Connect independently lists version 1.0 (5) as **Ready to Submit** and assigned to the internal TestFlight groups. This status is package processing, not App Review approval. |
| Build 5 real-device account/credit gate | PASS | `devicectl` confirmed SceneMe 1.0 (5) installed on the connected iPhone. A device Profile capture after dismissing an existing-subscription sheet shows the selected Sign in with Apple SceneMe account as **Free, 3 credits**. A read-only production PostgreSQL query at the same point showed Free/inactive, balance 3, zero subscription grants and zero App Store transactions. This verifies the false Pro display was removed for this case. |
| Same-account purchase, restore, renewal, expiry, refund and switch | BLOCKED | Apple’s sheet said the Sandbox tester was already subscribed to **Creator Yearly**, renewing November 18, 2026. Dismissing the sheet produced no new server transaction or grant on the selected SceneMe account. A clean Sandbox transaction is still required; the tester’s purchase history/cache must be isolated before buying Pro Yearly. Restore and later lifecycle events remain untested. |

## Release decision

**BLOCKED for public App Review.** Build 5 fixes the false client Pro display on the tested account, but the same-account purchase path still needs a new server-verified transaction and 100-credit grant, plus lifecycle and wider TestFlight validation. App Store version 1.0 still selects build 2; builds 1–4 must not be selected as the public release candidate. TestFlight transactions are Sandbox transactions and do not charge testers.
