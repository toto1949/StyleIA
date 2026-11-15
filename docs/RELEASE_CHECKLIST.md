# SceneMe 1.0 — Upload and Submission Checklist

This is the go/no-go checklist for the exact release candidate. **Upload** means sending a build to App Store Connect; **submit** means sending the version and subscriptions to App Review. Owner authorization remains required for both external actions.

## Source and build

- [x] Reconcile `origin/main` with the iOS release work; conflicts resolved and verified on `codex/release-1.0`.
- [ ] Commit every required source, asset, privacy manifest, StoreKit config, test, and release document; exclude credentials and customer data.
- [ ] Open/merge reviewable PRs and require green CI on the exact release commit.
- [x] Xcode 26.6 / iOS 26 SDK available; bundle ID `com.sceneme.app`, team `3K82B6HTAT`, version 1.0 verified in source.
- [x] Increment `CURRENT_PROJECT_VERSION` to build 2.
- [x] Confirm App Store Distribution signing/provisioning for Zevynta Labs LLC.
- [x] Archive Release for `Any iOS Device` and export a distribution-signed IPA; retain `/tmp/SceneMe-1.0-build2.xcarchive` and export/log evidence.
- [x] Inspect exported app entitlements, privacy manifest, bundle/version and compiled strings; StoreKit test data and release-test bypass markers are absent.

## Backend and reviewer access

- [x] Resume the previously `INACTIVE` SceneMe Supabase project; status returned to `ACTIVE_HEALTHY` without changing its plan.
- [x] Verify the restored private bucket is non-public, production row/object counts survived, and health/privacy/terms/support/catalog all return HTTP 200.
- [ ] Verify signed-media/auth/account-deletion behavior and measure sustained cold/warm API latency.
- [x] `origin/main` backend automated suite passes, including auth, private storage, credit ledger, rate limits, reviewer isolation, queue durability, and video-source signing.
- [x] Confirm required Render variable names exist for PostgreSQL, private object storage, fal.ai/OpenAI, Apple auth/IAP verification, reviewer access and daily budgets; no secret values were exported.
- [x] Verify `NODE_ENV=production`, mock generation is false, billing fallback is blank/false by code default, and App Store online checks are true; values were immediately re-masked.
- [x] Verify the daily user and global budget caps are both configured as positive numeric limits without exporting their amounts; values were re-masked.
- [ ] Validate actual rejection/alert behavior against paid provider calls and obtain owner approval of the cap amounts during financial sign-off.
- [ ] Obtain owner approval for always-on Supabase and Render plans. Current official base pricing is approximately $25/month for Supabase Pro plus $7/month for 512 MB Render compute ($32/month before bandwidth/overages); no purchase was made. Free Supabase can pause after low activity and free Render can cold-start for 50+ seconds.
- [ ] Verify private storage access/lifecycle, backups, alerts, spending caps, and production WebSocket in dashboards/staging.
- [x] Apply tested migrations 005/006: all 16 server-only tables now have RLS with no client policies, `anon`/`authenticated` retain zero privileges, `citext` is outside `public`, and Render stayed healthy.
- [ ] Verify `appreview@sceneme.app` exists, password works, grant is scoped to its server user ID, expiration is correct, and balance is sufficient but finite.
- [ ] Confirm support mailbox delivery and the safety-response owner/escalation process.

## StoreKit and App Store Connect

- [x] App record 6822467260 is accessible under Zevynta Labs LLC; bundle ID `com.sceneme.app`, SKU and version 1.0 are correct.
- [ ] Free Apps Agreement is active effective 2026-11-15; Account Holder must still accept the Paid Apps Agreement marked “New” and complete tax/banking.
- [ ] Set the app's free price schedule and intended storefront availability.
- [ ] Set the primary category and review content-rights, 4+ age-rating and DSA non-trader answers for accuracy.
- [x] Verify the four existing product IDs exist in the SceneMe Membership group and are in Prepare for Submission.
- [ ] Reorder subscription levels so Pro is above Creator and monthly/yearly products of the same tier share the same service level.
- [x] Approved US prices are present: Creator $6.99 monthly / $54.99 yearly; Pro $14.99 monthly / $119.99 yearly. **Do not activate until owner approval after financial/TestFlight validation.**
- [ ] Complete product localization, duration, availability, tax category, review screenshot, and subscription disclosures.
- [ ] Create the subscription-group display name/description and correct Creator Monthly's generic name and “SceneMe IA” description.
- [ ] Attach first subscriptions to version 1.0 as required by App Store Connect.
- [ ] Configure and test App Store Server API key `399AQ2HR33`, issuer `bcc9e67d-a7f4-444f-a1a2-9deefff625fd`, and Notifications V2 without committing the `.p8` key.
- [ ] Configure and test both production and sandbox App Store Server Notification URLs; both are currently unset.
- [ ] Execute local StoreKit, Apple Sandbox, and TestFlight lifecycle matrix: buy, pending, renew, restore, upgrade/downgrade, billing retry/grace, expire, revoke, refund, duplicate notification.
- [ ] Complete App Privacy from the audited implementation and enter the verified privacy-policy URL; the form is currently not started.
- [ ] Complete export compliance, review contact, demo sign-in and review notes. Change release behavior from automatic to owner-controlled manual release.
- [x] Local build 2 archive/export has correct Apple Distribution signature, team/bundle, Sign in with Apple entitlement and `get-task-allow=false`.
- [ ] Upload build 2 and treat build 1 as superseded; build 1 has zero assigned TestFlight evidence.

## QA and metadata

- [x] Patched iOS unit suite passes on iPhone 17 Pro simulator.
- [x] Deterministic UI suite passes 5/5 on the current working tree; rerun after any source change.
- [ ] Real iPhone and iPad TestFlight journeys pass: onboarding, auth, image, companion, custom scene, silent/talking video, background recovery, Gallery, export, restore, and deletion.
- [ ] Test poor/slow/offline networking, cold launch, app backgrounding, orientation, Split View, Dynamic Type, VoiceOver, Reduce Motion, and lower-memory device behavior.
- [ ] Perform one owner-approved live standard image and one video run while observing costs/logs; verify failure refunds without exposing content.
- [x] Fifteen final screenshot PNGs validate as RGB/no-alpha at 1320×2868, 1206×2622, and 2064×2752.
- [ ] Compare/recapture screenshots against the immutable TestFlight build and owner-approve them.
- [ ] Replace placeholder URLs in metadata with the verified privacy, terms, and support URLs.
- [ ] Complete and verify `docs/APP_REVIEW_NOTES_DRAFT.md` credentials/instructions.

## Go/no-go

- [ ] Financial validation approved by owner.
- [ ] Legal/privacy copy and processor retention reviewed by owner/counsel.
- [ ] No open P0/P1 issue in `docs/KNOWN_ISSUES_AND_BLOCKERS.md`.
- [ ] Owner explicitly approves the exact build, metadata, screenshots, prices, products, review notes, and upload.
- [ ] Owner separately authorizes App Review submission and release behavior (manual/automatic/phased).

Current decision: **GO for build 2 TestFlight upload; NO-GO for App Review submission or public release** until Paid Apps Agreement, App Privacy, app pricing/availability, subscription configuration/review assets, demo credentials and required live/TestFlight evidence are complete.
