# SceneMe 1.0 — Known Issues and Blockers

Last updated: 2026-11-15. Supabase was restored and hardened, and build 2 was distribution-archived locally. No paid provider call, plan purchase, IAP activation, build upload, legal agreement acceptance, or App Review submission was performed.

| Priority | Status | Issue | Required closure evidence |
| --- | --- | --- | --- |
| P0 | VERIFY | Release work is reconciled with `origin/main`, but the final commits/CI evidence are not yet published. | Clean release commits, green CI and reproducible archive hash. |
| P0 | VERIFY | Build 2 is distribution-signed and locally validated, but is not uploaded/processed by App Store Connect. | Upload build 2, confirm Apple processing and attach it to version 1.0. |
| P0 | BLOCKED | Apple Sandbox/TestFlight subscription lifecycle is untested. The four prices exist, but service levels are ordered incorrectly, Creator monthly localization is inaccurate, review screenshots are absent, and the first subscriptions are not attached to version 1.0. | Correct the group without changing product IDs, complete review metadata, test Notifications V2 and the full lifecycle, and attach the first subscriptions. |
| P0 | BLOCKED | App Privacy is not started and its privacy-policy URL is blank in App Store Connect. | Complete the audited data-use disclosures and publish/enter the verified privacy URL. |
| P0 | BLOCKED | The Free Apps Agreement is active, but the Paid Apps Agreement remains “New — View and Agree to Terms.” | Account Holder accepts the Paid Apps Agreement and completes tax/banking. The agent must not accept legal/financial terms. |
| P0 | BLOCKED | App price schedule and storefront availability are not configured. | Owner selects the free app price and intended storefronts; do not activate subscription commerce until financial/TestFlight approval. |
| P0 | BLOCKED | Production was recovered by resuming the `INACTIVE` SceneMe Supabase project; Render had crash-looped at `PostgresStore.init`. `/health` is back to HTTP 200, but free Supabase can pause again and free Render can cold-start for 50+ seconds. | Upgrade Supabase/Render to owner-approved always-on plans and collect availability/latency evidence before TestFlight or review. |
| P0 | BLOCKED | Exact reviewer account production grant, expiration, balance, and password are not verified. | Clean-device TestFlight login and `/v1/me` evidence without exposing credentials. |
| P0 | BLOCKED | Full real-device/TestFlight generation, video, export, restore, and deletion journey is untested. | Signed matrix for exact uploaded build. |
| P1 | FIXED / VERIFY ON RC | Reviewer access refresh previously raced login and used a possibly expired access token. | Patch now awaits refreshed account state and unit test passes; repeat on TestFlight with cold launch. |
| P1 | BLOCKED | Render has the required PostgreSQL, object-storage, AI-provider, Apple-verification, budget and mock-control variable names, but secret values/boolean settings, object lifecycle, backups, alerts, and restore behavior are not proven. Auto-deploy is off and no environment group is linked. | Verify safety values without exporting secrets; validate Supabase backup/restore and storage lifecycle; wire monitoring/alerts. |
| P1 | PASS | Production migrations 005/006 enabled RLS on all 16 SceneMe tables with no client policies and moved `citext` out of `public`; client roles retain zero table privileges and Render stayed healthy. | Keep advisor/privilege regression checks in each deployment. |
| P1 | BLOCKED | Live fal.ai image/video paths, provider timeout behavior, and reported video HTTP 503 are not reproduced. | Owner-approved minimal live test with job IDs, logs, costs, refund outcome, and no private media in report. |
| P1 | BLOCKED | App Review contact, sign-in credentials and notes are blank; automatic release is selected; App Store Server Notification production and sandbox URLs are unset. | Enter review details, switch to owner-controlled manual release, and configure/test both notification URLs after owner approval. |
| P1 | BLOCKED | Content Rights says no third-party content, category is unset, age rating is 4+, and DSA status is non-trader. These answers may not match a subscription AI app processing user/companion photos. | Owner/counsel reviews and corrects each answer before submission. |
| P1 | BLOCKED | TestFlight build 1 is Ready to Submit but has zero assigned groups/testers, no installs and no recorded test results. | Upload the new RC build, assign internal testers, fill What to Test, and execute the signed matrix. |
| P1 | BLOCKED | Safety reporting UI exists, but support mailbox delivery and moderation/escalation operations are not proven. | Mail delivery test, named owner, response target, harmful-content escalation runbook. |
| P2 | NOT TESTED | Existing Gallery rows with missing legacy object keys/objects, pagination, and second-device refresh. | Production-like migration sample and two-device test; unavailable items shown without silent deletion. |
| P2 | NOT TESTED | Poor connectivity, process termination, backgrounding, cold launch, and provider-resume behavior. | Network-conditioned TestFlight tests and restart recovery evidence. |
| P2 | NOT TESTED | Full iPhone/iPad/orientation/Split View/Dynamic Type/VoiceOver matrix. | Device/simulator matrix with screenshots and accessibility findings. |
| P2 | NOT TESTED | Memory and performance with large photos/videos. | Instruments run on a lower-memory supported device. |
| P2 | VERIFY | All 15 screenshots pass dimensions/RGB/no-alpha and visual current-build review, but have not been compared to the processed TestFlight build. | Owner approval and post-upload comparison or recapture. |
| P2 | BLOCKED | Legal/privacy text is engineering guidance, not professional legal advice; provider retention/licensing review remains. | Owner/counsel approval and documented template-asset rights. |
| P2 | BLOCKED | Pro yearly margin is sensitive to Apple proceeds, infrastructure, support, and accumulated non-expiring credit liability. | Real COGS sample, sensitivity analysis, owner approval before live activation. |

## Resolved in the current working tree

- The iOS client refreshes the access token and awaits `/v1/me` after email, Apple, and Google authentication before trusting temporary reviewer access.
- Reviewer preview remains server-derived, user-ID scoped, expiring, and is cleared on account switch/sign-out; there is no email-only or device-global Pro bypass.
- Profile now exposes a credential-free safety-report route.
- Backend legal/support copy now matches 3 starter credits, 30 Creator, 100 Pro, monthly annual-plan grants, non-expiring balances, 1/2/6/23 costs, and failed-job refunds.

These changes are not release evidence until committed, reviewed, included in the exact archive, and reverified through TestFlight.
