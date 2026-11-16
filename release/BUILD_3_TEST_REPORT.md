# SceneMe 1.0 (3) verification

Date: 2026-11-15 (America/New_York). App Review submission: BLOCKED.

| Scenario | Status | Evidence and next action |
| --- | --- | --- |
| Backend automated regression suite | PASS | `npm test --prefix Backend` exited 0. Includes auth, deletion, isolation, credits, rate limits, uploads, safety, queue recovery and private video-source signing. Local smoke uses mocked providers; this is not a live-provider or managed-database test. |
| Full iOS unit/UI suite | PASS | 19 passed (14 unit + 5 UI), 0 failed, 1 explicitly skipped local StoreKit lifecycle test on iOS 26.5. The separate attempted lifecycle run failed as recorded below. CI now includes four deterministic UI smoke scenarios. |
| Local StoreKit lifecycle | BLOCKED | Two attempted runs returned zero products; the stable iOS 26.5 run also threw `StoreKitError.notEntitled`. Purchase, renewal, refund and expiry assertions did not pass. Preserve this failure until a working local StoreKit host or Sandbox validates the flows. |
| Missing-price feedback/retry | PASS | Client compiles with explicit loading, error and retry state; live-device behavior pending. |
| Apple Sandbox/TestFlight purchase, restore, pending, upgrades/downgrades, billing retry/grace and notifications | BLOCKED | Paid Apps Agreement remains pending in last live inspection. Run after activation; local tests cannot establish these results. |
| Face identity across quality choices | BLOCKED | Standard and Premium completed in Render logs, but owner reports identity loss. Need consented original/result pairs and controlled visual comparison. Economy mode was off, ruling out the fixed economy/Premium parameter bug for those requests. |
| Physical-device offline, background/resume, export, accessibility and deletion | NOT TESTED | Repeat on build 3 and record outcomes. Simulator tests do not replace this matrix. |
| Archive and distribution export | PASS | `/tmp/SceneMe-1.0-build3.xcarchive`, `/tmp/SceneMeExport-build3/SceneMe.ipa`; version 1.0 build 3, team 3K82B6HTAT, bundle com.sceneme.app, get-task-allow=false. Privacy manifests present; no .storekit file in IPA. |
| TestFlight upload | PASS | Xcode reported Upload succeeded at 2026-11-15 20:14 EST; package processing. Processing acceptance, tester assignment and device installation are still pending. App Store version still references build 2. |

Exported IPA SHA-256: `8f3cc2507524ff1806db3fec325f86b1ed90fa0e1c940263c81e68fb13b10f77`.

## Running the local StoreKit scenario

The Debug launch scheme now references `SceneMe.storekit`. This simulates local prices and transactions; it does not activate production subscriptions or affect TestFlight. Set the scheme's StoreKit Configuration to None when testing the real Apple Sandbox from Xcode.

The local lifecycle test is explicitly opt-in because it requires a functioning StoreKit testing host. Add `SCENEME_RUN_STOREKIT_TESTS=1` to the test process environment in Xcode, then run `StoreKitConfigurationTests.localPurchaseRenewalRefundAndExpiry`. Its exclusion from ordinary unit CI must not be interpreted as purchase-test success. The scenario covers unavailable-price feedback, retry, account binding, renewal, expiration, refund, cancellation and the app purchase path. A failure aborts later scenarios; do not count them as passed.

No financial approval, production subscription activation or App Review submission has occurred.
