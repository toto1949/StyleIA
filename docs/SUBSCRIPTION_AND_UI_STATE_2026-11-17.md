# SceneMe subscription link and UI state investigation

Assessment date: 2026-11-17 (America/New_York)

## Purchase ownership

The selected Sign in with Apple SceneMe account remains Free with 3 starter credits, zero subscription grants, and zero App Store transactions in production PostgreSQL. A separate, earlier SceneMe login owns one Sandbox Pro Yearly subscription chain. A read-only query showed that chain updated again at 23:35 EST after the reported cancellation, history clear, and repurchase attempts. It did not move to the selected account.

The backend verifies Apple's signed transaction, requires its `appAccountToken` to match the authenticated SceneMe user, and rejects an `originalTransactionId` already bound to another user with HTTP 409 (`backend/src/services/app-store-service.mjs`). The conflict test in `backend/scripts/verify-subscription-gates.mjs` covers this guard. Removing it would allow an Apple subscription to unlock multiple SceneMe accounts and duplicate allowances. No entitlement or credit transfer was performed.

Apple documents that the original transaction ID is retained across subscription restores and renewals. Canceling and buying again therefore does not establish a new SceneMe ownership link. Apple's Sandbox history reset can take longer than several minutes; its instructions also require signing out of the Sandbox Apple Account to clear the device cache, signing back in, and restarting the app. The owner reported clearing history, but this attempt still produced the prior chain. A truly unused Sandbox tester is the next isolated TestFlight test. Sources: [Apple transaction identifier](https://developer.apple.com/documentation/appstoreservernotifications/originaltransactionid), [Sandbox purchase-history reset](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).

The local simulator StoreKit test was forced on an iPhone 17 Pro simulator. Product loading reached four Sandbox products, and the lifecycle test failed at `SKTestSession.buyProduct` with `.notEntitled`; the test runner did not use the local StoreKit purchase environment. A temporary Test-action StoreKit file reference produced the same result and was reverted. This is a failed local purchase test, not evidence of a valid server purchase. The ordinary iOS unit suite later passed 16 cases with two opt-in StoreKit tests skipped.

## Visible state changes for build 6

- Credits are unknown until the first `/v1/me` response. Profile displays a loading or unavailable state instead of a false zero, and the client does not block generation merely because the balance has not loaded. The backend remains the quota authority.
- The app refreshes the combined account and credit state when it becomes active and when Profile opens. Duplicate root refresh handlers were removed.
- Gallery thumbnails are downsampled and held in a small, account-scoped memory cache across tab switches and signed-URL rotation. The private thumbnail fetch uses an ephemeral session with disk caching disabled. Cache entries are purged on sign-out, account switch, and deletion.
- History signed URLs are refreshed at most once every two minutes while navigating tabs; a successful refresh updates the timestamp.
- Account-conflict text now explains that canceling and buying again may keep the same Apple subscription link.

These fixes require a new TestFlight build. A simulator unit test is not a substitute for a same-account, server-verified Sandbox purchase on that build. Keep App Review submission blocked until the fresh transaction produces exactly one entitlement and one monthly credit grant, and Restore does not grant again.
