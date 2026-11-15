# SceneMe App Store Submission Checklist

Code readiness was verified on September 14, 2026. Items below marked as
external require the release owner's Apple or Render credentials.

## Payments decision

SceneMe sells digital subscriptions used inside the iOS app. Keep the current
StoreKit 2 purchase flow. Do not add Stripe Checkout, a web-purchase button, or
copy directing users to an external payment method. Stripe live mode is not
part of this iOS release.

## 1. Deploy the production backend (external)

- Sync `render.yaml` and confirm the paid `0.5c-512mb` service plus the 5 GB
  persistent disk mounted at `/var/data`.
- If the existing ephemeral service contains any real user data, export it
  before attaching the disk; mounting the disk does not migrate old files.
- Set `FAL_KEY` and `OPENAI_API_KEY`.
- Set Sign in with Apple secrets: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and
  `APPLE_PRIVATE_KEY`.
- Set App Store Server API secrets from an In-App Purchase key:
  `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, and `APP_STORE_PRIVATE_KEY`.
- Leave `APPLE_CLIENT_ID` and `APP_STORE_BUNDLE_ID` as `com.sceneme.app`.
- Keep `STYLEAI_ENABLE_MOCK_GENERATION=false` and
  `STYLEAI_FAL_FALLBACK_TO_MOCK_ON_BILLING=false`.
- Deploy, then verify `/health`, `/privacy`, and `/terms` return HTTP 200.
- On a physical device, verify Apple sign-in, one real generation, restore,
  and in-app account deletion against the deployed release.

## 2. Configure App Store Connect (external)

- Confirm Paid Apps agreement, banking, and tax setup are active.
- Create one auto-renewable subscription group and these exact product IDs:
  - `com.sceneme.creator.monthly`
  - `com.sceneme.creator.yearly`
  - `com.sceneme.pro.monthly`
  - `com.sceneme.pro.yearly`
- Add prices, localization, review screenshots, and required subscription
  metadata. Submit the first subscriptions with the app version.
- Test all four products with a Sandbox Apple Account: purchase, upgrade,
  downgrade, pending purchase, cancellation/expiration, and Restore Purchases.
- App Privacy answers should match `Aura/Resources/PrivacyInfo.xcprivacy`:
  Name, Email Address, User ID, Photos or Videos, Other User Content, Product
  Interaction, and Purchase History; linked to the user, used for app
  functionality, with no tracking.
- Privacy Policy: `https://styleia.onrender.com/privacy`
- Terms of Use: `https://styleia.onrender.com/terms`
- Confirm Sign in with Apple is enabled for the primary App ID and production
  provisioning profile.
- Complete the age-rating questionnaire accurately for user-supplied photos,
  AI-generated media, and unrestricted web access (the app has none).
- Upload final iPhone and iPad screenshots for every required display size.

## 3. Review notes

Provide a fresh email demo account with unused generation allowance. Suggested
notes:

> SceneMe uses Apple In-App Purchase for all digital subscriptions. Restore is
> available on both the paywall and Profile. Before any selected photo or
> creative text is sent to third-party AI providers, the app presents an
> explicit disclosure naming fal.ai and OpenAI; permission can be withdrawn in
> Profile → AI Data Sharing. Account deletion is in Profile and attempts to
> revoke Sign in with Apple credentials. Deleting the SceneMe account does not
> cancel an Apple subscription, which the confirmation dialog explains.

Include exact steps to reach the paywall, custom scenes, companion upload, and
Video Director, plus any special Sandbox purchase instructions.

## 4. Final release check

- Increment the build number for every upload after build 1.
- Run `npm test` from `Backend/`.
- Run the Aura unit tests and make a signed Release archive in Xcode.
- Install the archive through TestFlight and test on a physical iPhone and iPad.
- Confirm production API keys have funds/quotas and alerts, and watch logs while
  App Review is in progress.
