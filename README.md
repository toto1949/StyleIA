# SceneMe

SceneMe places you into cinematic scenes from a photo — stills, companions, and Pro Video Director clips — with an iOS app and a Node backend on Render.

| Piece | Path | Notes |
| --- | --- | --- |
| iOS app | `Aura/` | SwiftUI, StoreKit 2, Sign in with Apple |
| Unit / UI tests | `AuraTests/`, `AuraUITests/` | Xcode test targets |
| Backend API | `Backend/` | Node 20, fal.ai generation |
| Deploy blueprint | `render.yaml` | Render web service |
| StoreKit config | `SceneMe.storekit` | Local subscription testing |

**Bundle ID:** `com.sceneme.app` · **iOS:** 17.0+ · **API:** `https://styleia.onrender.com/v1`

---

## Quick start

### Backend

```bash
cd Backend
cp .env.example .env
# Set FAL_KEY (or leave STYLEAI_ENABLE_MOCK_GENERATION=true for UI-only)
npm install
npm start
```

Mock mode (no fal spend):

```bash
npm run dev
```

Health check: `GET http://localhost:8080/health`  
REST base: `http://localhost:8080/v1`  
WebSocket: `ws://localhost:8080/ws`

Point the iOS app at your Mac’s LAN IP when testing on a device (`STYLEIA_API_BASE_URL` in `Aura/Resources/Info.plist`, or the Debug env override).

### iOS

1. Open `Aura.xcodeproj` in Xcode 15+
2. Select the **Aura** scheme and a simulator / device
3. For local StoreKit: enable `SceneMe.storekit` on the scheme
4. Sign in with Apple: capability + `APPLE_CLIENT_ID` on the backend must match `com.sceneme.app`

---

## Features (shipping)

- Scene catalog + **saved custom scenes** (Yours)
- Friend / pet companions with gender lock
- Cinematic color grades with live STRENGTH
- Pro Video Director (motion styles, talking + lip-sync)
- Subscriptions: Free / Creator / Pro (StoreKit 2 + restore)
- Privacy & Terms hosted on the API origin (`/privacy`, `/terms`)
- Local notification when a background clip finishes

---

## Environment (backend)

See `Backend/.env.example` and `Backend/README.md`. Required for production:

| Variable | Purpose |
| --- | --- |
| `STYLEAI_JWT_SECRET` | Session tokens (≥ 32 chars) |
| `FAL_KEY` | fal.ai API key (server only) |
| `APPLE_CLIENT_ID` | Sign in with Apple audience |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | Apple credential revocation on account deletion |
| `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, `APP_STORE_PRIVATE_KEY` | Server-side subscription verification |
| `STYLEAI_DATA_ENCRYPTION_KEY` | Encrypts stored Apple revocation tokens |
| `OPENAI_API_KEY` | Text safety checks and optional custom-scene enhancement |
| `PUBLIC_BASE_URL` / `RENDER_EXTERNAL_URL` | Public HTTPS origin for uploads + legal pages |

Cost / quality knobs: `FAL_MULTI_MODEL`, `FAL_KONTEXT_NUM_INFERENCE_STEPS`, `STYLEAI_REUSE_IDENTICAL_RESULTS`, `STYLEAI_VIDEO_RESOLUTION`.

---

## Deploy

Render Blueprint:

1. Dashboard → **New** → **Blueprint** → select this repo (`render.yaml`)
2. Set the required secret variables listed above (and optional `GOOGLE_CLIENT_ID`)
3. Confirm the `0.5c-512mb` service and `/var/data` persistent disk before launch

After merge, redeploy so production picks up backend changes.

---

## CI / tests

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and PR:

1. **Backend lint/syntax** — `node --check` on server modules  
2. **Companion prompt regression** — `npm run test:companions`  
3. **Subscription gates** — `npm run test:subscriptions`
4. **Mock smoke test** — auth, safety, image/video, legal, and deletion flows

Locally:

```bash
cd Backend
npm install
npm test   # starts a mock server, runs all backend checks, then exits
```

iOS unit tests (on a Mac):

```bash
xcodebuild test \
  -project Aura.xcodeproj \
  -scheme Aura \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AuraTests
```

---

## App Store checklist

- Privacy URL: `https://styleia.onrender.com/privacy`
- Terms URL: `https://styleia.onrender.com/terms`
- Demo account in App Review notes (auth-gated app)
- IAP product IDs match `SceneMe.storekit` / `SubscriptionTier`
- Restore Purchases on Paywall + Profile
- Account deletion in Profile
- Explicit third-party AI consent before any personal content is sent
- App Store Server API entitlement checks and server-side monthly limits
- Allow notifications for clip-ready alerts

The release owner must complete the account-level App Store Connect and Render
steps in `APP_STORE_SUBMISSION.md`; those require private credentials and cannot
be completed from source code alone.

---

## Repo layout

```text
Aura/                 iOS app sources
AuraTests/            Unit tests
AuraUITests/          UI tests
Backend/              Node API + fal services
  src/routes/         REST handlers (generate, legal, upload, …)
  src/services/       fal, prompts, store
  scripts/            smoke + companion verify
render.yaml           Render deploy blueprint
SceneMe.storekit      Local StoreKit configuration
.github/workflows/    CI pipeline
```

## License

Private / proprietary — all rights reserved.
