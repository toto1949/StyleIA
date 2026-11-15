# SceneMe App Store Metadata Draft

Owner review required. Do not upload until the final release build and commercial limits match this copy.

## Identity

- Primary name: **SceneMe – Cinematic AI Photos**
- Alternate names: **SceneMe: AI Scene Creator**; **SceneMe – Movie-Style Portraits**
- Subtitle: **Turn your photos into scenes**
- Primary category suggestion: Photo & Video
- Secondary category suggestion: Entertainment
- Copyright: **© 2026 Zevynta Labs LLC**

Name availability and trademark clearance are NOT TESTED.

## Promotional text

Step into cinematic scenes from your own photos. Choose a setting, direct the mood, add a companion, and bring select creations to life with motion.

## Description

SceneMe transforms your photos into personalized cinematic scenes.

Start with a photo, choose a setting, and direct the details—from time of day and weather to pose and wardrobe. Create a custom scene when inspiration strikes, add a friend or pet on supported plans, and turn select results into short animated videos.

Create with SceneMe:

- Explore a catalog of cinematic scene templates
- Adjust lighting, weather, pose, and styling
- Write and refine custom scene ideas
- Add a companion photo with permission
- Generate personalized AI images
- Direct short animations, including supported voice and lip-sync effects
- Revisit creations in your private history
- Save and share images and videos from your device

Your photos and creative instructions are processed only to provide the features you request. SceneMe explains when third-party AI processing is used and provides in-app account deletion.

AI results can vary. Only upload photos you own or have permission to use, and never use SceneMe to deceive, harass, impersonate, or create unlawful or non-consensual content.

SceneMe offers optional auto-renewable Creator and Pro subscriptions. Creator grants 30 credits each month at $6.99 monthly or $54.99 yearly. Pro grants 100 credits each month at $14.99 monthly or $119.99 yearly. Annual plans grant credits monthly during the subscription term. Credits do not expire. Standard images, companion images and rerolls use 1 credit; premium images use 2; five-second silent videos use 6; and five-second talking videos use 23. Payment is charged to your Apple Account at confirmation. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. You can manage or cancel subscriptions in your Apple Account settings. Localized prices and benefits are shown in the app before purchase.

Terms of Use: [FINAL TERMS URL]

Privacy Policy: [FINAL PRIVACY URL]

## Keywords

`AI photo,cinematic,portrait,scene,photo editor,avatar,movie,animation,video,creative`

Validate the final field against App Store Connect's current character counter; do not add competitor or trademark terms.

## What's New — Version 1.0

Welcome to SceneMe. Create cinematic AI scenes from your photos, customize the mood and setting, add supported companions, animate favorite results, and save or share your creations.

## Screenshot plan

Screenshots must be captured from the actual immutable release candidate with consented demo media. Do not use provider mock output, fabricated UI, unshipped features, real customer content, or unsupported subscription claims. The shipped scene picker uses deterministic offline artwork rather than remote placeholder photography.

Suggested sequence:

1. Home/template catalog — “Choose your scene.”
2. Photo and scene controls — “Direct every detail.”
3. Generated image result — “Your cinematic moment.”
4. Custom scene composer — “Create a scene of your own.”
5. Companion flow — “Bring a friend or pet.”
6. Video Director result — “Bring the moment to life.”
7. Private history/export — “Save and revisit your creations.”

As of 2026-10-13, Apple accepts one to ten screenshots per device size and requires a medium Dynamic Island screenshot plus a 13-inch iPad screenshot when iPadOS is supported. SceneMe now has five native RGB, non-alpha PNGs for each requested class: 1320×2868 in `release/app-store/screenshots/final/iphone-large/`, 1206×2622 in `release/app-store/screenshots/final/iphone-medium/`, and 2064×2752 in `release/app-store/screenshots/final/ipad-13/`. Reconfirm immediately before upload using [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

The UI portions are genuine SceneMe simulator captures, including the app's native adaptive iPad layout. Original scene artwork is shipped in the asset catalog; the campaign frames contain no generated UI, fake results, reviews, ratings, or unsupported feature claims. The options view is unobscured, and the paywall shows loaded US prices plus computed 34% Creator and 33% Pro annual savings. Rebuild instructions, source policy, and automated format validation are in `release/app-store/screenshots/README.md`.

Final status: **BLOCKED** only for immutable TestFlight RC comparison/recapture and owner approval. Real result, video, and export screenshots are intentionally excluded until their production-provider release-candidate journeys pass.

## App Preview

Optional. If produced, record the actual app: photo selection disclosure, scene controls, real progress state, real result and export. Never simulate generation speed or show unavailable results. Status: **NOT TESTED / not required for 1.0**.

## App Review notes draft

SceneMe creates private AI-generated images and short videos from photos selected by the user. Photos are uploaded only after an in-app third-party AI-processing disclosure is accepted. The backend validates authenticated ownership, enforces plan features and usage, and stores originals/results in private object storage using short-lived signed access.

Sign in with Apple and email authentication are available. Google Sign-In is [NOT INCLUDED IN 1.0 / CONFIGURED — OWNER TO SELECT]. Account deletion is available in Profile → Account → Delete Account. This deletes the SceneMe account and controlled media; Apple subscriptions must be managed separately in Apple's subscription settings.

Subscriptions use StoreKit 2 and these products: `com.sceneme.creator.monthly`, `com.sceneme.creator.yearly`, `com.sceneme.pro.monthly`, and `com.sceneme.pro.yearly`. The backend grants 30 Creator or 100 Pro credits on each subscription-month anniversary, including during annual terms; stored credits do not expire. Restore and Manage Subscription are in the paywall/profile.

Review access:

- Demo email: `[CREATE APP REVIEW ACCOUNT]`
- Demo password: `[STORE ONLY IN APP STORE CONNECT REVIEW NOTES]`
- Demo account state: preloaded with non-sensitive consented sample content and sufficient server allowance; it must exercise real production behavior, not bypass purchases unless the bypass is fully explained to Review.
- Special steps: `[ADD ONLY AFTER TESTFLIGHT VERIFICATION]`

## URLs

- Support URL: `https://styleia.onrender.com/support` (implemented and verified over HTTPS on 2026-11-15). Support email: `contact@zevyntalabs.com`. The currently entered `https://zevyntalabs.com/sceneme/support` returns HTTP 404 and must be replaced before submission.
- Privacy URL candidate: `https://styleia.onrender.com/privacy` (reachable 2026-10-12; final branded domain recommended).
- Terms URL candidate: `https://styleia.onrender.com/terms` (reachable 2026-10-12).
- Marketing URL: optional; **BLOCKED** if provided because no audited public marketing page exists.
