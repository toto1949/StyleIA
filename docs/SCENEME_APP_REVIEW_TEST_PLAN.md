# SceneMe App Review test access (October 2026)

Apple requires full app access during review and a functional purchase flow.
The test account is `appreview@sceneme.app`. Its password must only be entered
in **App Store Connect > App Review Information**, not committed to GitHub.

## Complimentary test access

This backend deliberately distinguishes *complimentary review access* from a
verified StoreKit purchase. For the account's exact database UUID only, set
these **server-side Render variables**:

- `SCENEME_REVIEWER_FULL_ACCESS_USER_ID`: UUID of the already-created App Review user
- `SCENEME_REVIEWER_FULL_ACCESS_UNTIL`: future UTC ISO 8601 date, e.g.
  `2026-12-15T23:59:59Z`

With these values, `GET /v1/me` reports `subscription.tier=pro`,
`subscription.status=active`, `subscription.isReviewAccess=true`,
`subscription.environment=complimentary_review`, and a null subscription
product ID. The server enforces the same Pro requirements against all gated
features, including premium imagery, custom scenes, re-roll, companions, AI
templates, and Video Director. Only this authenticated user ID can receive it.
There is no fake purchase transaction and no change to a normal user's
subscription.

The reviewer gets a **one-time 120-credit test grant** (plus ordinary 3
starter credits). Credits still decrement for generations; duplicate starts
cannot recreate the grant. The actual AI provider charges are real, and
`STYLEAI_DAILY_USER_BUDGET_USD` and `STYLEAI_DAILY_GLOBAL_BUDGET_USD`
remain enforced for this account. Increase these only with the account
holder's express approval and a defined spend ceiling. Apple Sandbox / TestFlight
purchases remain the recommended separate test of the StoreKit purchase flow.

Do **not** set mock generation or a pretend StoreKit transaction to make
features pass review. Do **not** set another user's ID or an unbounded expiry.
To turn off complimentary access, delete either variable and redeploy; doing
so does not revoke authentic purchased subscriptions.

## Test and submission sequence

1. Sign in on the **actual review build** and reload the account screen. Verify
   Pro access and the credits balance.
2. Generate one standard image and a premium image, create a custom scene,
   improve its template, reroll an outfit, try a companion, and try a silent
   and talking video using consenting, harmless test material. These require
   functioning FAL/OpenAI provider keys and sufficient budget; the demo grant
   does not waive real provider costs. Check physical media output and
   private storage permissions.
3. Exercise restore purchases, purchase flow and expiry with an
   **independent free/sandbox test account**, not the complimentary reviewer
   account. Do not fabricate App Store transactions. Apple's documentation
   specifically asks for an expired-subscription demo account when applicable.
4. Test privacy policy, support, sign-out, sign-in, and account deletion using
   a disposable separate test account.
5. **After the owner declares testing complete**, clear only the reviewer
   account's generated jobs, uploads, usage history and associated private
   media. Keep the review login, complimentary access, and enough test credits
   available to Apple. Check no jobs are still pending; back up any material
   the owner wants to keep. Do not delete data from other accounts.
6. Confirm the reviewer account signs in after cleanup and can still generate.
   Keep the demo access enabled through Apple's review window, noting its
   expiration and ensuring this is later than the review date.
7. In App Store Connect App Review Information, provide the login, explain
   complimentary Pro access and the separate Sandbox purchase flow, and list
   any extra test credentials. Add metadata and subscriptions as required.

Important: *Do not clean up the account before the owner finishes testing.*
Retain no test photos unnecessarily. This checklist is not evidence that
any listed feature or purchase has already passed a real-device test.

Sources:
- https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review
- https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases
