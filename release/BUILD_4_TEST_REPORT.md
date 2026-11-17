# SceneMe 1.0 (4) purchase-unlock candidate

Assessment date: 2026-11-17 (America/New_York)

## Scope

- Explains when an App Store subscription belongs to a different SceneMe login. The existing Sandbox Pro yearly transaction stays bound to its original SceneMe account.
- Awaits backend verification and an updated credit balance before the paywall reports purchase or restore success.
- Applies account-scoped paid entitlements returned by `/v1/me`, with expiry checks and clearing on account switch.
- Grants the first monthly allowance in the same backend mutation that persists a verified Apple transaction; replayed notifications cannot duplicate it.
- Increments the iOS build number to 4. Prices and the four product IDs are unchanged.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Full local backend suite | PASS | `npm test` completed on 2026-11-17. |
| Immediate Pro yearly grant / replay / account conflict | PASS | `npm run test:subscriptions`; 100 paid credits plus 3 starter, one subscription grant after replay, second account rejected. |
| Credit and entitlement persistence round-trip | PASS | `npm run test:credit-storage`; verified purchase grant persisted once. GitHub CI run `44133411700` also passed the complete backend suite against PostgreSQL. |
| iOS Release compile | PASS | `xcodebuild build -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`; compiled app reports CFBundleVersion 4. |
| iOS unit suite | PASS | `xcodebuild test -only-testing:AuraTests` on iPhone 17 Pro simulator; account-scoped paid/reviewer access, grace period, revocation and product contract passed. |
| GitHub CI on PR #21 | PASS | Backend/PostgreSQL and iOS Release compile, unit tests, and critical UI smoke passed in run `44133411700` on commit `175dd6c`. A duplicate run was canceled after merge. |
| Local StoreKit transaction lifecycle | BLOCKED | The opt-in tests were forced to run locally; `/Users/Apple/Library/Developer/Xcode/DerivedData/Aura-ghwwhrzltipobcfftjygtbctquvd/Logs/Test/Test-Aura-2026.11.17_12-14-40--0500.xcresult` records zero products from `Product.products(for:)` and a purchase entitlement remaining Free. Xcode test cleanup stalled and was interrupted. The temporary test edit was reverted. This is not a passing purchase test. |
| Build 4 archive | PASS | `/tmp/SceneMe-1.0-build4.xcarchive` contains version 1.0 (4), bundle `com.sceneme.app`, Team `3K82B6HTAT`. The archive is development signed pending App Store export. |
| Build 4 App Store distribution export/upload | BLOCKED | Xcode reports stale account credentials and no local iOS Distribution certificate. A subscription server API key cannot authenticate Xcode distribution. The owner must re-sign into Xcode → Settings → Accounts; export and upload remain unrun. |
| Backend production deploy | PASS | PR #21 merged as `aee87be`; Render deploy `dep-dbu8nr95efls739jr570` reached `live` on 2026-11-17. `/health` returned HTTP 200 and startup logs show mock generation disabled. No real post-deploy purchase was tested. |
| Build 4 real-device same-account Sandbox purchase/restore | NOT TESTED | Requires the owner to choose the SceneMe login and use a Sandbox tester. |
| Real paid production purchase | BLOCKED | TestFlight always uses Sandbox. Production charges require Apple approval and owner authorization after financial validation. |

## Release decision

**BLOCKED** for App Review submission until build 4 is distribution-signed and uploaded, and a same-account Sandbox purchase grants the expected 100 Pro credits and unlocks the tier and features on the physical device. Verify restore, renewal/expiry, refund, and account switching separately. App Store version 1.0 still selected build 2 at last inspection. TestFlight purchases cannot be charged production transactions.
