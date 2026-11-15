# SceneMe 1.0 Approved Commercial Model

Status: **OWNER APPROVED FOR ENGINEERING — NOT APPROVED FOR LIVE ACTIVATION**
Approved: 2026-10-13

## Plans and prices

| Tier | Allowance | Monthly | Yearly |
| --- | ---: | ---: | ---: |
| Free | 3 one-time starter credits | — | — |
| Creator | 30 credits granted each subscription month | $6.99 | $54.99 |
| Pro | 100 credits granted each subscription month | $14.99 | $119.99 |

Annual subscribers receive one allowance on each monthly anniversary during the paid annual term. Grants are durable and do not expire. An expired or cancelled subscription stops future grants and gated feature access; the stored balance remains available for eligible generation. Live prices and products must remain inactive until the owner approves financial validation and TestFlight results.

## Credit costs

| Operation | Credits | Estimated provider reservation |
| --- | ---: | ---: |
| Standard image, companion image, or reroll | 1 | $0.04 |
| Premium image | 2 | $0.08 |
| Five-second silent video | 6 | $0.35 |
| Five-second talking/lip-synced video | 23 | $1.35 conservative cap |

Accepted jobs debit atomically. Idempotent replays do not debit again. Terminal generation failure, cancellation before completion, and unrecoverable restart interruption receive one equal, idempotent refund. Daily per-user and global dollar limits remain independent kill switches.

The premium implementation was cross-checked against fal.ai's published contracts on 2026-10-13: [`fal-ai/flux-pro/kontext/max`](https://fal.ai/models/fal-ai/flux-pro/kontext/max/api) accepts one `image_url` and lists $0.08 per image, while [`fal-ai/flux-pro/kontext/max/multi`](https://fal.ai/models/fal-ai/flux-pro/kontext/max/multi/api) accepts `image_urls` for companion generation. This documentation check does not replace a paid staging run or invoice reconciliation.

## Apple Guideline 3.1.1 decision

Apple states that credits or in-game currencies purchased through in-app purchase may not expire. Apple also permits auto-renewable subscriptions to include consumable credits when the subscription provides ongoing value. There is no published exception that clearly permits unused subscription-issued generation value to be erased each month. Renaming the units “allowances” would not change their economic function.

SceneMe therefore uses monthly **granting**, not monthly **expiration**: balances roll over and remain recorded. This is the conservative engineering interpretation, not legal advice. Counsel/owner review and App Review confirmation remain required because Apple does not publish SceneMe-specific guidance for the interaction between non-expiring value and subscription-gated capabilities.

Official references: [App Review Guidelines 3.1.1 and 3.1.2](https://developer.apple.com/app-store/review/guidelines/) and [auto-renewable subscription availability](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-availability-for-an-auto-renewable-subscription).

## Financial sensitivity

Using the conservative configured reservations:

| Plan | Conservative net after 30% commission | Maximum provider reservation if fully redeemed | Remainder before infrastructure, moderation, support, tax and refunds |
| --- | ---: | ---: | ---: |
| Creator monthly | $4.89 | about $1.20 | about $3.69 |
| Creator yearly | $38.49/year | about $14.40/year | about $24.09/year |
| Pro monthly | $10.49 | about $5.87 | about $4.62 |
| Pro yearly | $83.99/year | about $70.43/year | about $13.56/year |

The Pro yearly case is thin under the conservative talking-video reservation and accumulated balances create a future redemption liability. Before activation, capture real fal.ai invoices for standard, premium, silent-video and talking-video golden tests; add retry/storage/egress/Render costs; model Apple proceeds and taxes for the actual account; and define alert thresholds. The owner must approve that completed validation.

## Approval record

- [x] 3 / 30 / 100 grant model approved for engineering.
- [x] 1 / 2 / 6 / 23 operation weights approved for engineering.
- [x] $6.99 / $54.99 Creator and $14.99 / $119.99 Pro target prices approved for preparation.
- [x] Uncapped-generation marketing removed.
- [ ] Financial validation approved after real staging cost capture.
- [ ] StoreKit/Sandbox/TestFlight lifecycle approved.
- [ ] Live App Store Connect activation and price change authorized.
