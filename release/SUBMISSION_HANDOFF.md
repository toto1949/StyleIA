# SceneMe 1.0 submission handoff

Status: **BLOCKED**. Do not press **Submit for Review** until the evidence below is complete. This is an engineering status report, not a claim that App Review will approve the app.

## Completed by engineering

- Production Sign in with Apple credential mismatch fixed. Apple accepted the replacement client secret, Render deployment `dep-dbtt0ch42hec73au3t5g` is live, health returned HTTP 200, and the owner reported a successful iPhone sign-in. Repeat sign-in, Hide My Email and deletion/revocation remain untested.
- The four subscription products loaded on the owner's iPhone and prices appeared on the paywall. No purchase or restore lifecycle passed.
- Local backend suite passed after the Apple diagnostic test was added. The diagnostic safely records only allowlisted OAuth error codes. PR #19 contains the current release branch; backend CI passed at `0cfb417`, while iOS CI was still running when checked.
- Paid Apps Agreement, bank account and U.S. W-9 were previously verified Active. The latest Connect state must be rechecked before submission.
- Build 3 was uploaded. App Store version 1.0 was last verified with build 2 selected; choosing build 3 is still outstanding.
- Live App Store Connect recheck: build 3 is listed in TestFlight as **Ready to Submit** for external beta review; build 2 is **Waiting for Review** there. The App Store version still has build 2 selected. These TestFlight statuses are not proof that build 3 passed public App Review.
- App Store version 1.0 has empty review username/password, contact and notes fields. The release option is set to **Manually release this version**.
- App Store Connect now displays two China mainland compliance notices: a security assessment and an AI-generated-content (AIGC) services declaration. Owner decision is needed to supply these filings or exclude China mainland from 1.0 availability.
- Reviewer account cleanup: the owner used in-app deletion and recreated `appreview@sceneme.app`; production SQL now shows a new active user with zero uploads and jobs. The old user, 12 uploads, 17 jobs and result rows are absent. Render review access was rebound to the new user ID, with the existing expiry `2026-12-15T23:59:59Z`; deployment `dep-dbtt4aoae00c73dlk1l0` is live. A subsequent production query showed the expected 123-credit starter/reviewer balance. Direct object-bucket enumeration and a real reviewer generation remain open.

## Engineering work still open

1. Verify the recreated App Review account's Pro entitlement, finite allowance, real generation, login on the exact build and temporary expiry. The old database history is gone and review access is rebound; private object deletion followed the authenticated account-deletion route but has not been independently enumerated in the bucket.
2. Finish PR #19 CI, review the final diff, merge only validated release changes, and deploy the exact backend commit. Current Render deploy uses main commit `852d6854bc1111cc5d958c6398717c86c1a53a5e` plus the corrected Apple key; PR #19 code is not deployed.
3. Validate the owner-reported face change across quality settings using paired input/output photos and real provider job IDs. No provider result should be called identity-safe from source inspection alone.
4. Execute signed StoreKit/Sandbox/TestFlight purchase, restore, upgrade, downgrade, expiry, refund, grace-period and notification scenarios. Product loading alone is insufficient. Do not activate or submit live subscription products before the owner's financial/TestFlight approval.
5. Verify real provider cost, failed-generation credit refunds, account deletion, private-media isolation, offline/background recovery, accessibility, performance and cold-start behavior on the selected build. Review backup, alerting and provider safety gates.
6. Recheck App Store Connect fields, review notes, age rating, rights, DSA answers, privacy label, URLs, screenshots and the selected build. Apple currently asks for a demo account with an expired subscription for auto-renewable subscription review; provide a usable path and explain any finite complimentary review access in review notes.

## Draft App Review notes for owner approval

> SceneMe creates private AI images and short videos from photos supplied by the user. Sign in with Apple and email sign-in are available. Use the review account credentials entered in the Sign-In Information fields to explore the template catalog, photo upload, custom scenes, companion flow, generation, Video Director, private history, export and in-app deletion. The review account receives a finite, temporary server-side feature allowance for evaluation; it is not an App Store purchase. Paid Creator and Pro plans are available through StoreKit in the paywall. To exercise a purchase from an expired state, use the separate expired-subscription demo account documented in the Sign-In Information/attachment [INSERT DETAILS AFTER VERIFIED]. Generation uses fal.ai and OpenAI; output varies by input and provider availability. Do not use real customer faces during review. For support, contact contact@zevyntalabs.com.

Replace the bracketed text with a tested expired-account path before using these notes. Do not enter an expired demo claim unless the actual account exists and works. Credentials belong in App Store Connect's private review fields, not in this repository.

## Owner actions

1. Confirm the recreated App Review account shows its temporary Pro allowance and can perform a generation, then enter its password privately in App Store Connect only after the exact build is chosen. Do not paste the password into chat.
2. Review a final TestFlight build with engineering and perform one real purchase/restore cycle using a Sandbox tester. Confirm product prices and tier limits before authorizing live subscription submission. Use an account without complimentary reviewer access for purchase tests.
3. Provide the review contact phone and enter the working demo credentials directly in App Store Connect. Review the final legal/privacy wording, age-rating questionnaire, content rights and AI consent disclosures. Approve infrastructure spending if a paid production plan is required for reliable review access.
4. After engineering reports all release gates PASS, choose the exact build and subscription items for the same draft submission, inspect the review notes and screenshots, and initiate **Submit for Review** yourself.

## Source requirements

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) ask for on-device testing, a live backend and usable demo access.
- [Apple's complete-review guidance](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/) addresses subscription demo accounts, including expired subscriptions.
- [Apple's subscription submission guidance](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase) requires the app version, subscription group and products being reviewed together to be included in the same draft submission.
