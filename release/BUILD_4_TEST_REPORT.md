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
| Credit and entitlement persistence round-trip | PASS | `npm run test:credit-storage`; verified purchase grant persisted once. Local store configuration was used; PostgreSQL CI is still required. |
| iOS Release compile | PASS | `xcodebuild build -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`; compiled app reports CFBundleVersion 4. |
| iOS unit suite | PASS | `xcodebuild test -only-testing:AuraTests` on iPhone 17 Pro simulator; account-scoped paid/reviewer access, grace period, revocation and product contract passed. |
| Local StoreKit transaction lifecycle | NOT TESTED | Opt-in purchase/renewal/refund tests were skipped by the simulator runner despite the shell environment variable. |
| Build 4 archive, signing, App Store upload | NOT TESTED | Awaiting CI and final review. |
| Build 4 real-device same-account Sandbox purchase/restore | NOT TESTED | Requires the owner to choose the SceneMe login and use a Sandbox tester. |
| Real paid production purchase | BLOCKED | TestFlight always uses Sandbox. Production charges require Apple approval and owner authorization after financial validation. |

## Release decision

**BLOCKED** for App Review submission until build 4 is uploaded and a same-account Sandbox purchase grants the expected 100 Pro credits and unlocks the tier and features on the physical device. Verify restore, renewal/expiry, refund, and account switching separately. App Store version 1.0 still selects build 2 at last inspection.
