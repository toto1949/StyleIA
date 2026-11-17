# App Store Connect Setup Worksheet

Live App Store Connect configuration was updated and verified on 2026-11-15. This worksheet records the resulting state without committing secrets; submission, legal agreements, live subscription activation and public release remain owner-controlled.

## App record and signing

| Field | Expected | Status |
| --- | --- | --- |
| Legal entity | Zevynta Labs LLC | Owner verify |
| Bundle ID | `com.sceneme.app` | Source/archive/portal PASS |
| SKU | Stable existing Connect value | Portal PASS; keep private/internal |
| Platform/version | iOS/iPadOS 1.0 | Source/portal PASS |
| Build | 3 is the latest uploaded candidate | Build 3 was uploaded and tested for product loading on the owner's iPhone; App Store version 1.0 was last verified with build 2 selected. Recheck processing and select the exact signed-off build before review. Build 1 must not be submitted. |
| Apple team | `3K82B6HTAT`; matches every Xcode target | Archive and portal PASS |
| Distribution certificate/profile | Apple Distribution / App Store managed profile | Archive/export PASS |
| Numeric Apple app ID | `6822467260` / `APP_STORE_APPLE_ID` | Portal PASS |
| App Store Server API issuer ID | `bcc9e67d-a7f4-444f-a1a2-9deefff625fd` / `APP_STORE_ISSUER_ID` | Owner-provided; API verification NOT TESTED |
| App Store Server API key ID | `399AQ2HR33` / `APP_STORE_KEY_ID` | Owner-provided; matching `.p8` NOT PROVIDED |

Apple currently requires an app record before upload, and 2026 iOS uploads must be built with Xcode 26 or later. Record the exact Xcode version used. See [Apple upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).

## Subscriptions

Create one subscription group such as **SceneMe Membership** and preserve identifiers:

| Product | Duration | Tier | Price | Status |
| --- | --- | --- | --- | --- |
| `com.sceneme.creator.monthly` | 1 month | Creator, 30 credits/month | $6.99 | APPROVED FOR PREPARATION; activation BLOCKED |
| `com.sceneme.creator.yearly` | 1 year | Creator, 30 credits granted monthly | $54.99 | APPROVED FOR PREPARATION; activation BLOCKED |
| `com.sceneme.pro.monthly` | 1 month | Pro, 100 credits/month | $14.99 | APPROVED FOR PREPARATION; activation BLOCKED |
| `com.sceneme.pro.yearly` | 1 year | Pro, 100 credits granted monthly | $119.99 | APPROVED FOR PREPARATION; activation BLOCKED |

Live setup now places Pro monthly/yearly at service level 1 and Creator monthly/yearly at level 2, supplies the English group/product localizations, keeps all four products at Prepare for Submission, and shows the real paywall screenshot on every product review page. Credits do not expire; annual allowances are granted monthly. Leave the first-subscription attachment and activation blocked until the owner approves the completed financial validation and TestFlight results.

Commercial approval record: `release/COMMERCIAL_LIMIT_DECISION.md`. Engineering preparation is approved; live product configuration is not.

## Apple server configuration to provide later

Store only in Render/App Store Connect secret facilities:

- Matching In-App Purchase `.p8` private key for issuer `bcc9e67d-a7f4-444f-a1a2-9deefff625fd` and key `399AQ2HR33`.
- Sign in with Apple team ID, key ID and `.p8` private key.
- Numeric App Store Apple ID: `6822467260`.
- Current Apple Root CA DER files from [Apple PKI](https://www.apple.com/certificateauthority/) mounted as secret files; set `APP_STORE_ROOT_CA_PATHS` to their absolute paths.
- App Store Server Notifications V2 production URL: `https://styleia.onrender.com/v1/app-store/notifications` (saved in Connect).
- Sandbox URL: `https://styleia.onrender.com/v1/app-store/notifications` (saved in Connect).

After configuration, request an Apple test notification, verify HTTP 200 and durable notification status, then test duplicate delivery and notification history recovery. Never paste keys into issues, chat transcripts, docs, `.env`, source or CI logs.

## App Privacy worksheet

Published Connect answers currently reflect the audited archive/backend behavior:

- Contact info: email, name — linked to identity; account functionality.
- Identifiers: user ID — linked; app functionality.
- User content: photos, videos, other content/prompts — linked; app functionality.
- Purchases: purchase history — linked; app functionality.
- Usage data: product interaction — linked; app functionality.
- Diagnostics: crash/performance data — disclose only if a production SDK/service is added.
- Tracking: No.

List processors and retention: Render, PostgreSQL provider, S3/R2 provider, fal.ai, OpenAI (including photo and text safety screening), Apple, Google only if enabled, and monitoring/support vendors once selected. Reconcile answers with the final archive privacy report and `Aura/Resources/PrivacyInfo.xcprivacy`.

## Age rating

Complete Apple's current questionnaire; do not self-assign solely from this document. Recommended posture: not Made for Kids; declare user-generated/AI-created content and any mature themes reachable through open-ended prompts accurately. Consider an owner-selected higher override if safety controls do not reliably prevent mature generated material. Apple's questionnaire is required and can produce region-specific results; see [age-rating setup](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/).

## Export compliance

SceneMe uses standard Apple networking/security and cryptography for HTTPS, Keychain and authentication. Owner must answer App Store Connect encryption questions for the final binary and determine whether the standard/exempt encryption declaration applies. Do not rely on this engineering note as legal/export advice; retain the submitted determination and any required documentation.

## Required URLs and agreements

- Public privacy policy, terms, support URL and optional marketing URL.
- Paid Applications Agreement, tax and banking status completed by the Account Holder.
- Current developer agreements accepted only by an authorized owner.
- Support/contact ownership and escalation route.

## TestFlight and review

1. Upload only after local archive validation and owner authorization.
2. Wait for processing; resolve all compliance/privacy warnings.
3. Add internal testers, then external testing details if used.
4. Complete beta review information and a working review/demo account.
   Apple's current guidance asks subscription apps to provide a demo account with an expired subscription so reviewers can exercise the purchase flow. Provide that separately from SceneMe's finite complimentary reviewer account, and explain both paths in review notes.
5. Run the exact checklist in `docs/QA_CHECKLIST.md`.
6. Select one immutable build for version 1.0. The owner chooses manual, automatic or phased release and initiates submission.
