# SceneMe App Store Screenshots

This package contains five screenshots for each current SceneMe device class:

| Folder | Native portrait size | Source layout |
| --- | ---: | --- |
| `final/iphone-large/` | 1320 × 2868 | iPhone 17 Pro Max simulator |
| `final/iphone-medium/` | 1206 × 2622 | iPhone 17 Pro simulator |
| `final/ipad-13/` | 2064 × 2752 | iPad Pro 13-inch simulator, native adaptive layout |

Every deliverable is an RGB PNG without an alpha channel. Each set combines genuine SceneMe simulator UI with a black-and-gold campaign frame and a device mockup. The catalog imagery is original offline scene artwork shipped in the asset catalog; the screenshots do not fabricate generated results, reviews, ratings, or unavailable features.

Apple currently requires at least one medium Dynamic Island screenshot and, when iPadOS is supported, at least one 13-inch iPad screenshot. The supplied dimensions are accepted native sizes. Reconfirm immediately before upload using [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Sequence

1. Place yourself anywhere.
2. Choose a scene. Make it yours.
3. Direct every detail.
4. Create with clear credits.
5. From one photo to any world.

The options screenshot is deliberately scrolled so image-quality and companion controls remain visible above the sticky action button. The paywall screenshot uses the four configured StoreKit prices and displays the computed annual savings: Creator 34% and Pro 33% at the approved US prices.

## Source and rebuild

Raw native captures are under `source/captures/<device>/`. Original scene artwork is under `source/scene-art/` and its optimized app copies are in `Aura/Assets.xcassets`.

Rebuild and validate all three sets with:

```bash
python3 release/app-store/screenshots/build_screenshots.py
```

The script writes `final/validation-report.json`, including dimensions, color mode, alpha status, and SHA-256 for each of the 15 submission files. Contact sheets are review aids only and must not be uploaded to App Store Connect. Superseded drafts are retained in `final/legacy-draft/`.

The deterministic DEBUG screenshot mode supplies the same US prices declared in `SceneMe.storekit` because StoreKit configuration is not injected into the UI-test child process. A unit test verifies those exact product prices. Release builds do not contain this fallback and load prices from StoreKit.

## Final submission gate

Before upload, compare or recapture every screen against the immutable TestFlight release candidate and verify the selected localization. Do not upload if UI, price, credit cost, product availability, or copy differs from that build. Real result, video, and export screens may be added only after those production-provider journeys pass on the release candidate.
