# Device feedback investigation

Submission status: BLOCKED pending real-device reproduction and validation.

## Observed evidence

- Owner reports missing prices in TestFlight and local installs, and changed facial identity after switching image quality.
- Supplied console log is from Debug-iphoneos. It shows account access and system warnings, but no StoreKit product response or error. It cannot establish why products were unavailable.
- SubscriptionService previously swallowed product-fetch errors in Release and did not distinguish an empty successful response from loading. Paywall had no visible retry control. Local changes add loading/error state, retry for missing products, and privacy-safe StoreKit count/error-code logging.
- Existing product identifiers remain unchanged. Apple's sandbox troubleshooting requires current agreements, configured prices, localizations and product availability. The Paid Apps Agreement was previously pending; its current status needs owner verification. Products need not be approved for review to test in Sandbox.
- Standard and Premium use different image-editing models, with each request using the uploaded original. Quality selection is not a lossless upscale. Identity instructions alone cannot prove face fidelity.
- Fixed a conditional bug: Premium requests previously inherited economy/dev parameters when economy mode was enabled, despite choosing Kontext Max. Regression coverage verifies source image, aspect ratio, disabled prompt enhancement and absence of dev-only parameters with economy mode both on and off. This is not evidence that the reported face drift is solved or that production had economy mode enabled.
- Public production health check initially timed out at 20 seconds, then returned HTTP 200 with PostgreSQL healthy in 0.334 seconds. The cause of the timeout is unconfirmed.
- Owner confirmed Taoufiq's workspace. Authenticated Render logs show live commit 852d6854, economy mode disabled, Standard completion in 19.661 seconds and Premium Max completion in 30.242 seconds. Both used full parameters, with no fallback recorded in the queried events. A video request resumed after restart and completed. These observations do not establish visual identity fidelity.
- Live App Store Connect Business inspection confirms Paid Apps Agreement is still `New — View and Agree to Terms`. The separate Free Apps Agreement and DSA status are Active. Account Holder action is required before Sandbox purchase validation.

## Local verification

- iOS unit tests: 14 passed on iPhone 17 Pro simulator; changed client code compiled. This does not validate live Apple product loading.
- fal durable queue tests: passed, including Premium/economy regression; no paid generation was triggered by these tests.
- `git diff --check`: passed.

## Required remaining validation

1. Verify Paid Apps Agreement is active and all four products load on the device; capture new StoreKit diagnostics if not.
2. Inspect Render generation events corresponding to the affected requests, without logging photos, signed URLs or secrets.
3. Compare the same original photo and scene in Standard and Premium, with owner-authorized provider spending; assess face likeness visually.
4. Build a new candidate containing the client changes and repeat price loading, purchase/restore and generation tests. Build 2 does not contain these changes.
5. Submit only after the reported issues and other release-readiness gates pass.

References: https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox and https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases/
