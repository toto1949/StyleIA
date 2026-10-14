# StyleAI / SceneMe Backend

Node 20 API for SceneMe, a Zevynta Labs LLC product (generation, auth, uploads, legal pages).

Company website: https://zevyntalabs.com/

## Run locally

```bash
cd Backend
cp .env.example .env
npm install
npm start
```

For local UI testing without fal.ai credits:

```bash
npm run dev
```

The iOS app should point at:

```text
API base URL: http://localhost:8080/v1
WebSocket URL: ws://localhost:8080/ws
```

On a physical iPhone, replace `localhost` with your Mac's LAN IP and set `PUBLIC_BASE_URL` to that same origin.

## Tests

```bash
npm run test:companions   # friend/pet gender prompt locks
npm run test:subscriptions # plan gates, monthly grants, ledger debits/refunds and budgets
npm run test:rate-limits  # atomic durable limiter race
npm run test:provider-state # PostgreSQL queue-state round trip
npm run test:content-safety # no-network text/image moderation contract
npm run test:upload-validation # JPEG decode, metadata stripping and malformed/pixel-limit rejection
npm run test:fal-queue    # no-spend durable fal submit/resume/cancel contract
npm run test:smoke        # mock API smoke (auth, generate, legal, video)
npm test                  # all checks
```

## Required production configuration

- `PUBLIC_BASE_URL`: a public HTTPS URL reachable by fal.ai. For local fal.ai testing, use an HTTPS tunnel such as ngrok or Cloudflare Tunnel.
- `STYLEAI_JWT_SECRET`: a strong secret, at least 32 random bytes.
- `STYLEAI_JWT_ISSUER`, `STYLEAI_JWT_AUDIENCE`: exact access-token issuer and iOS audience (`com.sceneme.app` by default).
- `STYLEAI_ACCESS_TOKEN_TTL_SECONDS`, `STYLEAI_REFRESH_TOKEN_TTL_DAYS`: short access-token and rotating refresh-session lifetimes (defaults: 900 seconds and 30 days).
- `STYLEAI_API_RATE_LIMIT_PER_MINUTE`, `STYLEAI_USER_RATE_LIMIT_PER_MINUTE`, `STYLEAI_AUTH_RATE_LIMIT_PER_15_MINUTES`, `STYLEAI_APP_STORE_NOTIFICATION_RATE_LIMIT_PER_MINUTE`: PostgreSQL-backed abuse ceilings.
- `DATABASE_URL`: required managed PostgreSQL connection/pool URL in production; apply `npm run db:migrate` before startup.
- `OBJECT_STORAGE_*`: private S3/R2 bucket, endpoint and least-privilege credentials; public access must be blocked.
- `APPLE_CLIENT_ID`: the Sign in with Apple audience. For this app it should match the configured app/service identifier, for example `com.sceneme.app`.
- `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`: Sign in with Apple key used to exchange and revoke the user's credential during account deletion.
- `STYLEAI_DATA_ENCRYPTION_KEY`: a separate 32+ character random secret used to encrypt Apple refresh tokens at rest.
- `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, `APP_STORE_PRIVATE_KEY`: App Store Connect In-App Purchase API key used to verify subscriptions on the server.
- `APP_STORE_BUNDLE_ID`: `com.sceneme.app`.
- `GOOGLE_CLIENT_ID`: the Google OAuth iOS client ID (ends with `.apps.googleusercontent.com`). Must match `GIDClientID` in the iOS app.
- `FAL_KEY`: server-side fal.ai API key. Never put this in the iOS app.
- `OPENAI_API_KEY`: server-side OpenAI key used for user-text safety checks and optional custom scene improvement. Never put it in the iOS app.
- `OPENAI_TEMPLATE_MODEL`: defaults to `gpt-5-mini` for low-cost structured template output.
- `OPENAI_MODERATION_MODEL`: defaults to `omni-moderation-latest` for text and pre-generation image screening.
- `FAL_MODEL`: defaults to `fal-ai/flux-pro/kontext` (~$0.04/image).
- `FAL_MULTI_MODEL`: companion path; defaults to `fal-ai/flux-pro/kontext/multi` (~$0.04). Use `…/max/multi` (~$0.08) only if needed.
- `FAL_KONTEXT_NUM_INFERENCE_STEPS`: eco `fal-ai/flux-kontext/dev` step count. Defaults to `36`; it is not sent to Kontext Pro.
- `FAL_KONTEXT_GUIDANCE_SCALE`: solo guidance. Defaults to `3.75`.
- `FAL_MULTI_GUIDANCE_SCALE`: companion guidance. Defaults to `4.5`.
- `STYLEAI_REUSE_IDENTICAL_RESULTS`: reuse completed identical photo+prompt jobs (default `true`).
- `STYLEAI_ECO_MODE`: cheaper/lower-quality path — leave `false` in production.
- `STYLEAI_VIDEO_RESOLUTION`: `360p` / `540p` / `720p` / `1080p` (default `720p`).
- `STYLEAI_ENABLE_MOCK_GENERATION`: set to `true` to skip fal.ai entirely for local UI testing.
- `STYLEAI_FAL_FALLBACK_TO_MOCK_ON_BILLING`: set to `true` to return mock looks when fal.ai returns a billing/balance lock during local QA.

`npm start` loads `Backend/.env` automatically.

## Implemented API

- `POST /v1/auth/email`
- `POST /v1/auth/apple`
- `POST /v1/auth/google`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `POST /v1/app-store/notifications`
- `POST /v1/subscriptions/sync`
- `GET /v1/me`
- `POST /v1/upload/presign`
- `PUT /v1/upload/:uploadId?token=...`
- `GET /v1/scenes`
- `POST /v1/templates/improve`
- `POST /v1/scene-jobs`
- `GET /v1/scene-jobs/:jobId`
- `DELETE /v1/scene-jobs/:jobId`
- `POST /v1/scene-jobs/:jobId/reroll`
- `POST /v1/scene-jobs/:jobId/video`
- `GET /v1/history?page=&limit=`
- `DELETE /v1/account`
- `GET /uploads/:fileName` (local/mock development only; originals are private in production)
- `GET /health`
- `GET /support`
- `WS /ws/:jobId?token=...`

The upload presign endpoint returns a short-lived signed PUT URL. Production
requires a private S3-compatible bucket. The client can write only an ingress
key; validation normalizes the object into a separate internal key so a still-
valid PUT URL cannot replace content after safety screening. OpenAI screens the
finalized photo, fal.ai receives a short-lived signed input URL, and provider
results are ingested back into the private bucket. Only expiring signed
downloads are returned. Local files are available only for development;
original photos are never a public production endpoint.

Paid provider work uses fal's durable queue API. The database records the exact
request ID, model and image/video/TTS/lip-sync/mux phase before polling, so a
restart can resume status/result retrieval without resubmitting paid work.
Cancellation is propagated to fal; real paid restart/cancellation behavior must
still be proven in staging before release.
