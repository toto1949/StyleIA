# App Store Connect Setup Worksheet

No App Store Connect mutation was performed. Fill this worksheet without committing secrets.

## App record and signing

| Field | Expected | Status |
| --- | --- | --- |
| Legal entity | Zevynta Labs LLC | Owner verify |
| Bundle ID | `com.sceneme.app` | Source PASS; portal NOT TESTED |
| SKU | Owner-defined stable internal value | BLOCKED |
| Platform/version | iOS/iPadOS 1.0 | Source PASS |
| Build | Increment from 1 for every upload | Owner/release action |
| Apple team | `3K82B6HTAT`; matches every Xcode target | Owner-confirmed; portal organization/role NOT TESTED |
| Distribution certificate/profile | Automatic or managed distribution signing | BLOCKED: read-only local audit found no distribution identity; one development profile matches the app and expires 2027-07-10 |
| Numeric Apple app ID | `6822467260` / `APP_STORE_APPLE_ID` | Owner-provided; portal/API verification NOT TESTED |
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

For each product complete localization, display name, description, review screenshot, availability and tax category. Ensure upgrade/downgrade levels put Pro above Creator. Credits do not expire; annual allowances are granted monthly. Do not enable sale until the owner approves the completed financial validation and TestFlight results. Confirm renewal terms, actual localized prices and benefits match the paywall.

Commercial approval record: `release/COMMERCIAL_LIMIT_DECISION.md`. Engineering preparation is approved; live product configuration is not.

## Apple server configuration to provide later

Store only in Render/App Store Connect secret facilities:

- Matching In-App Purchase `.p8` private key for issuer `bcc9e67d-a7f4-444f-a1a2-9deefff625fd` and key `399AQ2HR33`.
- Sign in with Apple team ID, key ID and `.p8` private key.
- Numeric App Store Apple ID: `6822467260`.
- Current Apple Root CA DER files from [Apple PKI](https://www.apple.com/certificateauthority/) mounted as secret files; set `APP_STORE_ROOT_CA_PATHS` to their absolute paths.
- App Store Server Notifications V2 production URL: `https://[FINAL API HOST]/v1/app-store/notifications`.
- Sandbox URL: use the same endpoint unless operational separation is chosen.

After configuration, request an Apple test notification, verify HTTP 200 and durable notification status, then test duplicate delivery and notification history recovery. Never paste keys into issues, chat transcripts, docs, `.env`, source or CI logs.

## App Privacy worksheet

Final answers must reflect actual backend/provider behavior. Candidate data types:

- Contact info: email, name — linked to identity; account functionality.
- Identifiers: user ID — linked; account functionality, fraud prevention.
- User content: photos, videos, other content/prompts — linked; app functionality.
- Purchases: purchase history — linked; app functionality.
- Usage data: product interaction — linked; analytics/app functionality if collected.
- Diagnostics: crash/performance data — disclose only if a production SDK/service is added.
- Tracking: No, provided no data is linked across other companies' apps/sites for advertising or brokered.

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
5. Run the exact checklist in `docs/QA_CHECKLIST.md`.
6. Select one immutable build for version 1.0. The owner chooses manual, automatic or phased release and initiates submission.
