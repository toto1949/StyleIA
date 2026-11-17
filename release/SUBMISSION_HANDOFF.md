# SceneMe 1.0 submission handoff

Status: **BLOCKED**. Do not press **Submit for Review** until the evidence below is complete. This is an engineering status report, not a claim that App Review will approve the app.

## Completed by engineering

- Production Sign in with Apple credential mismatch fixed. Apple accepted the replacement client secret, Render deployment `dep-dbtt0ch42hec73au3t5g` is live, health returned HTTP 200, and the owner reported a successful iPhone sign-in. Repeat sign-in, Hide My Email and deletion/revocation remain untested.
- The four subscription products loaded on the owner's iPhone and prices appeared on the paywall. No purchase or restore lifecycle passed.
- Local backend suite passed after the Apple diagnostic test was added. The diagnostic safely records only allowlisted OAuth error codes. PR #19 contains the current release branch; backend CI passed at `0cfb417`, while iOS CI was still running when checked.
- Paid Apps Agreement, bank account and U.S. W-9 were previously verified Active. The latest Connect state must be rechecked before submission.
- Build 3 was uploaded. App Store version 1.0 was last verified with build 2 selected; choosing build 3 is still outstanding.

## Engineering work still open

1. Clear the App Review account's test jobs and private media while preserving a working login. Production has 12 uploads and 17 jobs for `appreview@sceneme.app`. The existing account-deletion route deletes private objects, sessions, grants and history. There is no safe history-only purge route. Do not delete database rows alone because that would orphan private media. If the owner deletes and recreates the account through the app, rebind `SCENEME_REVIEWER_FULL_ACCESS_USER_ID` to its new user ID, verify finite access and budget limits, and test review login on the exact build.
2. Finish PR #19 CI, review the final diff, merge only validated release changes, and deploy the exact backend commit. Current Render deploy uses main commit `852d6854bc1111cc5d958c6398717c86c1a53a5e` plus the corrected Apple key; PR #19 code is not deployed.
3. Validate the owner-reported face change across quality settings using paired input/output photos and real provider job IDs. No provider result should be called identity-safe from source inspection alone.
4. Execute signed StoreKit/Sandbox/TestFlight purchase, restore, upgrade, downgrade, expiry, refund, grace-period and notification scenarios. Product loading alone is insufficient. Do not activate or submit live subscription products before the owner's financial/TestFlight approval.
5. Verify real provider cost, failed-generation credit refunds, account deletion, private-media isolation, offline/background recovery, accessibility, performance and cold-start behavior on the selected build. Review backup, alerting and provider safety gates.
6. Recheck App Store Connect fields, review notes, age rating, rights, DSA answers, privacy label, URLs, screenshots and the selected build. Apple currently asks for a demo account with an expired subscription for auto-renewable subscription review; provide a usable path and explain any finite complimentary review access in review notes.

## Owner actions

1. Use the App Review account on a physical device to invoke **Delete Account**, then sign up again with `appreview@sceneme.app` and a strong password you keep privately. Tell engineering only when both steps succeed; do not paste the password into chat. Engineering must then rebind review access and verify no old private objects remain. If you cannot sign in to the reviewer account, say so before any deletion.
2. Review a final TestFlight build with engineering and perform one real purchase/restore cycle using a Sandbox tester. Confirm product prices and tier limits before authorizing live subscription submission. Use an account without complimentary reviewer access for purchase tests.
3. Provide the review contact phone and enter the working demo credentials directly in App Store Connect. Review the final legal/privacy wording, age-rating questionnaire, content rights and AI consent disclosures. Approve infrastructure spending if a paid production plan is required for reliable review access.
4. After engineering reports all release gates PASS, choose the exact build and subscription items for the same draft submission, inspect the review notes and screenshots, and initiate **Submit for Review** yourself.

## Source requirements

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) ask for on-device testing, a live backend and usable demo access.
- [Apple's complete-review guidance](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/) addresses subscription demo accounts, including expired subscriptions.
- [Apple's subscription submission guidance](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase) requires the app version, subscription group and products being reviewed together to be included in the same draft submission.
