# Sign in with Apple — 2026-11-16

Status: **BLOCKED — production sign-in fails; exact Apple rejection code not yet available.**

## Verified configuration mismatch (follow-up)

Authenticated Codex in-app browser inspection found:

| Setting | Render service | Apple Developer |
| --- | --- | --- |
| Client / bundle ID | `com.sceneme.app` | Key configured for `3K82B6HTAT.com.sceneme.app` |
| Team ID | `3K82B6HTAT` | `3K82B6HTAT` (ZEVYNTA LABS LLC) |
| Sign in with Apple key ID | **`J72PKMJU9W`** | **`543SL2NUZZ`**, “SceneMe Sign In”, the sole key listed |

The configured key ID is not the key listed in the current Apple team. This is a verified credential configuration defect consistent with the token-exchange failures; the exact OAuth rejection still requires a live attempt with improved diagnostics. The private key was not revealed or compared, so changing only the ID is not yet known to be sufficient. Replace/configure the matching ID and private key together, then verify a fresh real-device login.

The matching `.p8` file was not found in Downloads, Desktop, Documents or `.codex` in the local filename search. The only discovered download was an App Store subscription key, which must not be substituted. Apple disables downloading the existing sign-in key again. Owner must locate its original private-key file or authorize creating a replacement. No production settings were changed; revealed non-secret IDs were re-masked.

## Replacement key registered (2026-11-17 follow-up)

After owner approval, a new Apple Developer key named `SceneMe Sign In Replacement` was registered for primary App ID `3K82B6HTAT.com.sceneme.app`, with only Sign in with Apple enabled. New key ID: **`BZ63PVGWJ9`**. Apple showed the one-time key download as completed. A local search of Downloads, Desktop, Documents, `.codex`, macOS Containers, and Application Support did **not** locate `AuthKey_BZ63PVGWJ9.p8`. The in-app browser's download destination must be identified before configuring Render. The old key was not revoked. No secret contents were printed or committed, and no production environment values were changed.

Reviewer account inspection: `appreview@sceneme.app` remains active and has 12 uploads, 17 generation jobs, 3 credit grants, and 20 ledger entries. The owner requested preserving its login while clearing test history and media. The backend has account deletion and job cancellation but no history/media purge endpoint. Database-only deletion would leave private objects orphaned; cleanup is pending a storage-aware approach and verification.

## Owner-download replacement

After explicit owner confirmation, unusable key `BZ63PVGWJ9` was revoked. Apple immediately offered `com.sceneme.app` as a primary App ID again. A fresh key, `DUK92YGRRL` (“SceneMe Sign In Owner Download”), was registered with only Sign in with Apple enabled and SceneMe as primary App ID. The Apple **Download Your Key** page is open, with its Download button untouched so the owner can save the `.p8` file personally. Render remains unchanged; live sign-in has not been retested. The earlier key `543SL2NUZZ` remains listed and was not revoked.

Owner downloaded `AuthKey_DUK92YGRRL.p8` to Downloads. Local OpenSSL parsing passed and file permissions were restricted to `0600`. Render environment variables `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` were updated together via the Render connector without printing key material; merge mode preserved unrelated variables. Deployment `dep-dbtt0ch42hec73au3t5g` reached `live`, and `/health` returned HTTP 200 in 0.696 s. A direct Apple `/auth/token` request with a correctly signed client secret and deliberately invalid authorization code returned `400 invalid_grant`, which establishes Apple accepted the signing credentials and rejected the test code. No user token or session was created by that check. Real iPhone Sign in with Apple remains to be verified.

The owner subsequently reported a **successful Sign in with Apple on the iPhone** against the live deployment. This establishes the immediate sign-in failure is resolved for that attempt. The Render log query did not surface a matching successful request, so this is owner-observed device evidence rather than independently recorded server-response evidence. Returning sign-in, Hide My Email, cancellation, deletion/revocation, and other account scenarios remain untested.

## Verified production evidence

Render service `srv-d98llertqb8s7399g35g` recorded `Apple authorization-code exchange failed (400).` for POST `/v1/auth/apple`:

- 2026-11-16 04:35:00.744 UTC, request `825ef16f-2f9c-4557-bdbc-892035a90c16`.
- 2026-11-16 16:53:20.739 UTC, request `bdddd71e-1a38-40d7-b41c-41f01e88fa7e`.

`Backend/src/server.mjs`, `authApple`, verifies the identity token before this exchange and issues a session only afterward. These attempts therefore passed identity verification but failed before session issuance. The deployed exception discards Apple's OAuth error code; HTTP 400 alone does not establish the underlying cause.

Apple distinguishes `invalid_client` (client-secret/signing credentials), `invalid_grant` (code/client mismatch, expired or consumed code), and `invalid_request` (request parameters). Source: [Apple TN3107](https://developer.apple.com/documentation/technotes/tn3107-resolving-sign-in-with-apple-response-errors).

## Local diagnostic change and checks

- `Backend/src/services/apple-account-service.mjs` now includes only allowlisted OAuth error codes in its exception. Arbitrary response text, error descriptions, keys, codes, and tokens are excluded. This does not bypass authentication or token exchange.
- `Backend/scripts/verify-apple-account.mjs` passed locally. It verifies ES256/P1363 JWT signature and claims using an ephemeral test key, error-code redaction, no automatic code retry, encrypted refresh-token storage, and decryption for revocation.
- Provider responses were mocked. This is not proof of live Apple sign-in or of valid production credentials.
- Diagnostic change is **not deployed**. No production configuration was changed.

## Remaining verification

1. Dashboard access is now verified through the owner's Codex in-app browser (Apple tab 8, Render tab 5); earlier Chrome access was logged out.
2. Obtain the matching private key securely, then correct the mismatched `APPLE_KEY_ID` and verify `APPLE_PRIVATE_KEY` as a pair. App Store Connect API credentials are separate and must not be assumed interchangeable.
3. Deploy the tested diagnostic change if configuration inspection does not identify the mismatch. Capture one fresh real-device attempt and inspect the allowlisted error code.
4. Correct the verified cause, then test first sign-in, returning sign-in, Hide My Email, cancellation, and account deletion/revocation. Until a real login succeeds, keep authentication marked BLOCKED and do not submit the release.
