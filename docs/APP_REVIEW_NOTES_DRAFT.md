# SceneMe 1.0 — App Review Notes Draft

Do not paste this draft into App Store Connect until the bracketed fields are completed against the immutable TestFlight release candidate.

## Contact and demo access

- Demo email: `appreview@sceneme.app` **(production existence and access state must be verified)**
- Demo password: `[ENTER SECURELY IN APP STORE CONNECT ONLY — NEVER COMMIT]`
- Contact email/phone: `[OWNER TO ENTER]`
- Temporary access expiration: `[COPY THE VERIFIED SERVER UTC EXPIRATION]`

The demo account uses ordinary production authentication and generation APIs. It may receive a temporary, finite, server-side Pro feature preview for App Review. The grant is bound to one server user ID, has an expiration, is not a StoreKit transaction, is not selected by email or client input, and does not grant access to other accounts. Confirm its production credit balance immediately before submission.

## Suggested notes to Apple

SceneMe creates private AI-generated images and five-second videos from photos selected by the user. It has no public feed, public profiles, or user-to-user messaging.

Before a selected photo or creative text is sent to third-party AI processors, SceneMe presents an explicit disclosure naming fal.ai and OpenAI and asks for permission. The user may decline or later withdraw permission in **Profile → AI Data Sharing**. Users must confirm permission before using another person's companion photo.

To test the core flow:

1. Sign in with the review credentials above.
2. On Explore, select a scene and add a consented test photo.
3. Review the AI-processing disclosure and choose Allow.
4. Adjust scene options and generate an image.
5. Open the result to save/share it or create a five-second animation. Talking/lip-synced video uses 23 credits; silent video uses 6.
6. Open Gallery to revisit private results.
7. Open Profile for Restore Purchases, Manage Subscription, privacy/terms/support, AI data-sharing control, safety reporting, and Delete Account.

Subscriptions use StoreKit 2 only. Product identifiers are:

- `com.sceneme.creator.monthly`
- `com.sceneme.creator.yearly`
- `com.sceneme.pro.monthly`
- `com.sceneme.pro.yearly`

Creator grants 30 credits each subscription month; Pro grants 100. Annual subscribers also receive the allowance monthly. Stored credits do not expire. Standard images, companion images, and rerolls cost 1 credit; premium images cost 2; silent videos cost 6; talking/lip-synced videos cost 23. Restore and Manage Subscription are available from the paywall/Profile.

Account deletion is available in **Profile → Account → Delete Account** and deletes the SceneMe account and controlled private media. The app explains that deleting the SceneMe account does not cancel an Apple subscription and provides Apple's subscription-management route.

AI results can vary. SceneMe applies prompt/image safety checks, authenticates all paid generation endpoints, uses private object storage with short-lived signed access, and provides **Profile → Report a Safety Issue**. Support: `contact@zevyntalabs.com`.

## Before submission

- Verify the credentials on the uploaded TestFlight build from a clean device.
- Verify the server grant belongs to that exact account, is unexpired, has a finite balance, and survives cold launch.
- Replace every bracketed field.
- Record typical real generation time and any first-request cold-start delay based on TestFlight measurements.
- If review access is not verified, remove the claim and submit only instructions that were actually tested.
- Do not include API keys, transaction keys, private signed media URLs, or customer data.
