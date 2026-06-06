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
- `APPLE_CLIENT_ID`: the Sign in with Apple audience. For this app it should match the configured app/service identifier, for example `toto.StyleAI`.
- `FAL_KEY`: server-side fal.ai API key. Never put this in the iOS app.
- `FAL_MODEL`: defaults to `fal-ai/ip-adapter-face-id`.

`npm start` loads `Backend/.env` automatically.

## Implemented API

- `POST /v1/auth/email`
- `POST /v1/auth/apple`
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
