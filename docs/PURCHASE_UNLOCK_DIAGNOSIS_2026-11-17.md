# SceneMe Sandbox purchase and feature-unlock diagnosis — 2026-11-17

## Verified production observations

- The owner reported a successful purchase while the SceneMe Profile still showed Free.
- PostgreSQL contains a verified `com.sceneme.pro.yearly` transaction in Apple's **Sandbox** environment. Its App Account Token matches the SceneMe user to which the backend linked it. That user's server entitlement is Pro/active. No subscription credit grant had been created; its remaining balance was one starter credit.
- The SceneMe account open on the owner's iPhone showed an Apple private-relay email. PostgreSQL identifies it as a different user, with no subscription entitlement and three starter credits. The purchased transaction is linked to a separate Gmail SceneMe account. The Free display on the private-relay account is therefore the correct account-isolation behavior.
- One older Sandbox Creator transaction is unlinked after its original SceneMe account was deleted. Do not attach either transaction to a different account by editing database IDs.

## Engineering fix on `codex/purchase-entitlement-unlock`

- Server verification records the verified transaction and its first due monthly credit grant in one store mutation. Grant keys make retries idempotent. Annual subscribers continue to receive later monthly grants on account activity.
- The iOS app applies account-scoped server entitlements, gives a clear message when StoreKit finds a subscription tied to another SceneMe account, and waits for backend verification and refreshed credits before claiming that a purchase or restore succeeded.
- Account changes clear cached paid and reviewer access. Transactions without a matching App Account Token do not unlock a different SceneMe account.

The fix does **not** transfer the existing Sandbox transaction. The owner must choose one SceneMe login for further tests and use a matching Sandbox purchase/restore on that account. The revised build must be uploaded to TestFlight and tested before App Review.

## Verification and limits

- Full local backend suite passed, including immediate-grant and replay tests. PostgreSQL CI is required before deployment.
- iOS Release build and simulator unit tests passed. The opt-in local StoreKit lifecycle tests were still skipped by Xcode's test runner despite setting the shell environment variable. No new build has been uploaded or tested on the owner's device.
- Real TestFlight purchases are always Sandbox transactions and do not charge testers. A production charge cannot be tested in an unreleased TestFlight build. Apple reviews the first auto-renewable subscription group and subscriptions with the new app version. Do not mark the products ready for live sale until the owner approves the financial validation and a matching-account Sandbox purchase/restore passes.

Sources: [Apple TestFlight purchase testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/), [Apple's App Review purchase preparation](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases/), [Apple's first subscription submission process](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).
