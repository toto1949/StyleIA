# SceneMe 1.0 (6) Test Report

Assessment date: 2026-11-18 (America/New_York)

## Scope

PR #28 (merged as `bec996b`) fixes Gallery thumbnail flashes across tab switches, the initial false zero-credit display, duplicate account refresh handlers, and the purchase-account conflict explanation. The release build number is 6. The backend's original-transaction ownership check remains in place. See `docs/SUBSCRIPTION_AND_UI_STATE_2026-11-17.md` for the diagnosis.

| Item | Status | Verification and limit |
| --- | --- | --- |
| Debug simulator compile | PASS | `xcodebuild build` for generic iOS Simulator exited 0. |
| Release simulator compile | PASS | Generic iOS Simulator Release build exited 0 after the final code edit. |
| Simulator unit tests | PASS | iPhone 17 Pro, iOS 26.5: 16 passed, 0 failed, 2 opt-in StoreKit tests skipped. The new checks cover unknown credits and account isolation for thumbnail memory. Result bundle: `Test-Aura-2026.11.17_23-50-41--0500.xcresult` (local DerivedData). |
| GitHub CI | PASS | Both PR #28 backend/PostgreSQL jobs and both iOS Release/unit/UI smoke jobs passed. These are automated checks, not a real purchase. |
| Archive | PASS | `/tmp/SceneMe-1.0-build6.xcarchive` was created with version 1.0 (6), `com.sceneme.app`, Team `3K82B6HTAT`. `git diff` confirms its source files match merged `main`. |
| Apple Distribution export and upload | PASS | After the owner restored the Zevynta Labs account in Xcode, build 6 exported with cloud-managed Apple Distribution, Team `3K82B6HTAT`, Sign in with Apple, symbols, and `get-task-allow=false`. `/tmp/SceneMeExport-build6/SceneMe.ipa` passed ZIP integrity; privacy manifests are present and `.storekit` is absent. SHA-256: `a6b4966847675c35362381e8f144bb3f154a60b5aa16aaac0a2a683727a113e8`. Upload exited 0 at 2026-11-18 23:38 EST. App Store Connect subsequently listed build 6 **Ready to Submit** in two internal TestFlight groups. Apple's iOS 27 SDK warning applies starting April 2027, not to this upload. |
| Local StoreKit transaction lifecycle | BLOCKED | A forced iPhone 17 Pro simulator test loaded four Sandbox products, but `SKTestSession.buyProduct` failed with `.notEntitled`; the test runner did not use the local StoreKit purchase environment. A temporary Test-action configuration reference did not change this and was reverted. A passing product-contract test is not purchase proof. |
| Build 6 TestFlight UI and purchase | NOT TESTED | Build 6 is available to internal testers but has not yet been installed or tested on the owner's iPhone. The exact-build Gallery/Profile and purchase journeys remain open. |
| Same-account Sandbox purchase | BLOCKED | Production PostgreSQL still shows the selected Sign in with Apple SceneMe account as Free/3, with no subscription grant or transaction. The earlier Sandbox Pro Yearly chain remains linked to a separate SceneMe login, including a later update after the reported reset/re-purchase. A truly unused Sandbox tester is needed for a clean transaction. |

**Decision: BLOCKED for App Review.** Install build 6 from TestFlight, verify the Gallery/Profile state on the real device, and purchase Pro Yearly once using the owner's newly activated Sandbox tester while signed into the selected SceneMe account. Confirm one server transaction, one 100-credit grant, Pro access, and idempotent Restore before selecting build 6 for App Review.
