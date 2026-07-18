# StyleAI Backend

Dependency-free Node 20 backend for the Aura/StyleAI iOS app.

## Run locally

```bash
cd Backend
cp .env.example .env
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

## Required production configuration

- `PUBLIC_BASE_URL`: a public HTTPS URL reachable by fal.ai. For local fal.ai testing, use an HTTPS tunnel such as ngrok or Cloudflare Tunnel.
- `STYLEAI_JWT_SECRET`: a strong secret, at least 32 random bytes.
- `APPLE_CLIENT_ID`: the Sign in with Apple audience. For this app it should match the configured app/service identifier, for example `com.sceneme.app`.
- `GOOGLE_CLIENT_ID`: the Google OAuth iOS client ID (ends with `.apps.googleusercontent.com`). Must match `GIDClientID` in the iOS app.
- `FAL_KEY`: server-side fal.ai API key. Never put this in the iOS app.
- `FAL_MODEL`: defaults to `fal-ai/flux-pro/kontext` (~$0.04/image).
- `FAL_MULTI_MODEL`: companion path; defaults to `fal-ai/flux-pro/kontext/multi` (~$0.04). Use `…/max/multi` (~$0.08) only if needed.
- `FAL_KONTEXT_NUM_INFERENCE_STEPS`: solo step count. Defaults to `36` (pro is priced per image).
- `FAL_KONTEXT_GUIDANCE_SCALE`: solo guidance. Defaults to `3.75`.
- `FAL_MULTI_GUIDANCE_SCALE`: companion guidance. Defaults to `4.5`.
- `STYLEAI_REUSE_IDENTICAL_RESULTS`: reuse completed identical photo+prompt jobs (default `true`).
- `STYLEAI_ECO_MODE`: cheaper/lower-quality path — leave `false` in production.
- `STYLEAI_VIDEO_RESOLUTION`: `360p` / `540p` / `720p` / `1080p` (default `720p`).
- `STYLEAI_ENABLE_MOCK_GENERATION`: set to `true` to skip fal.ai entirely for local UI testing.
- `STYLEAI_FAL_FALLBACK_TO_MOCK_ON_BILLING`: set to `true` to return mock looks when fal.ai returns a billing/balance lock during local QA.

`npm start` loads `Backend/.env` automatically.

## Generation request contract

`POST /v1/jobs` accepts profile data used to personalize prompts and avoid repeated generic looks across users:

```json
{
  "s3Key": "uploads/example.jpg",
  "styleGoal": "casual",
  "styleGoals": ["casual", "professional", "sporty", "luxury", "streetwear"],
  "subjectGender": "female",
  "styleProfile": {
    "subjectGender": "female",
    "ageRange": "25-34",
    "bodyType": "petite",
    "heightRange": "short",
    "skinTone": "medium",
    "undertone": "warm olive",
    "hairColor": "dark brown",
    "faceShape": "oval",
    "fitPreference": "clean tailored feminine fit",
    "colorPreference": "earth tones",
    "modestyPreference": "balanced modern coverage",
    "climate": "temperate",
    "occasion": "daily style discovery",
    "budget": "mid premium",
    "stylePersona": "minimal editorial",
    "favoriteColors": ["olive", "ivory"],
    "avoid": ["boxy fit"]
  }
}
```

Supported `subjectGender` values are `male`, `female`, and `nonbinary`. The backend stores the normalized profile on the job, uses it in the fal prompt, derives a per-user style signature from `userId + seed + profile`, and returns product matches under each look.

## Implemented API

- `POST /v1/auth/email`
- `POST /v1/auth/apple`
- `POST /v1/auth/google`
- `POST /v1/upload/presign`
- `PUT /v1/upload/:uploadId?token=...`
- `POST /v1/jobs`
- `GET /v1/jobs/:jobId`
- `DELETE /v1/jobs/:jobId`
- `GET /v1/history?page=&limit=`
- `DELETE /v1/account`
- `GET /uploads/:fileName`
- `GET /health`
- `WS /ws/:jobId?token=...`

The upload presign endpoint returns a signed upload URL hosted by this backend. This satisfies the existing iOS app contract without requiring AWS credentials for local development. In production you can place this service behind HTTPS and durable storage, or swap the upload adapter for S3/R2 while keeping the same client contract.
