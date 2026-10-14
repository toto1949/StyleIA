# SceneMe Production Architecture

Last verified: 2026-10-12

## System boundary

SceneMe is a SwiftUI iOS/iPadOS client backed by a Node.js API. The API is the only trusted caller of fal.ai, OpenAI, object storage, PostgreSQL, and Apple server APIs. Provider keys and storage credentials must never enter the app bundle.

```text
iOS app
  | HTTPS REST / authenticated WebSocket
  v
Render web service
  |-- PostgreSQL: identities, jobs, usage, transactions, entitlements, audit events
  |-- private S3/R2 bucket: originals, companion photos, generated images/videos
  |-- fal.ai: image, video, TTS, lip-sync/mux
  |-- OpenAI: text/image moderation and custom-template enhancement
  `-- Apple: identity keys, App Store Server API, Notifications V2
```

## Environments

| Environment | Data | AI | Apple | Purpose |
| --- | --- | --- | --- | --- |
| Local | JSON or disposable PostgreSQL; local files | explicit mock only | StoreKit config | Fast development and deterministic tests. |
| Staging | separate PostgreSQL and private bucket | real staging keys with small budgets | Sandbox | Integration, restart, deletion and TestFlight validation. |
| Production | managed PostgreSQL and private bucket | production keys and alerts | Production + Sandbox notification endpoint | App Store release only. |

Production configuration fails at startup if database, storage, Apple, fal.ai, OpenAI, encryption, or signing secrets are absent. Mock generation and billing fallback default off and must remain off.

## Data model

Versioned migrations in `Backend/migrations/` own the schema:

- `users`, `auth_identities`, `sessions`: accounts and provider identities.
- `uploads`: owner, private key, purpose, validation state, dimensions, hash and expiry.
- `generation_jobs`, `job_events`: durable job state, idempotency, provider identifiers, attempts, leases, estimated/actual cost and history.
- `generation_results`: private owned output metadata.
- `usage_counters`: server-side monthly image/video usage and cost.
- `subscription_entitlements`, `app_store_transactions`, `app_store_notifications`: verified Apple lifecycle state and replay protection.
- `credit_accounts`, `credit_grants`, `credit_ledger`: non-expiring balances, idempotent starter/monthly grants, debits and failed-job refunds.
- `rate_limit_windows`: fixed-window counters shared by every backend instance; only HMAC subject digests are stored.

Foreign keys delete user-owned data where appropriate. User history, queue claims, provider IDs, pending uploads and subscription lookups are indexed. Timestamps use `timestamptz`; identifiers use UUIDs; money uses fixed-precision numeric fields.

The current `PostgresStore` deliberately preserves the legacy snapshot/mutate route contract while moving state to PostgreSQL. Its transaction-scoped advisory lock makes mutations correct for the first release, but it serializes all writes. Replace it with targeted repositories and direct row-level credit/job transactions before significant scale.

## Media lifecycle

1. An authenticated user requests a private upload key.
2. Production returns a short-lived S3-compatible presigned PUT URL scoped to `private/{user}/uploads/{uuid}/incoming.jpg`.
3. Before generation, the API verifies ownership, size and declared type, fully decodes the image, enforces a pixel ceiling, auto-orients, strips metadata, and writes `validated.jpg` under an internal, non-presigned key. Generation never reads the client-writable ingress key.
4. The finalized subject and companion images receive fail-closed OpenAI image screening. Short-lived signed URLs are then sent to fal.ai; they are never returned as public permanent URLs.
5. Provider output is downloaded from an allowlisted HTTPS host with byte/time limits and copied into the private bucket before completion.
6. Owned API responses contain newly signed short-lived GET URLs. History refresh renews expired links.
7. Result/account deletion removes controlled objects and database rows. Provider retention remains governed by provider terms and must be described in policy.

Bucket controls required outside code: block public access, default encryption, least-privilege service credentials, object versioning or recovery policy, access logging, lifecycle cleanup (including removal of stale `incoming.jpg` objects), and separate buckets per environment.

## Job lifecycle

The client supplies a UUID `Idempotency-Key` for scene, reroll and video creation. The database uniqueness constraint prevents a second billable job for the same user/operation/key. Per-user concurrency is checked before submission. Provider calls have bounded local timeouts.

```text
pending -> processing -> completed
                    |-> failed
                    |-> cancelled/deleted
```

Every paid fal phase uses `queue.submit`, persists its request ID, exact model and phase before polling, and retrieves the result with `queue.result`. Video jobs also persist the intermediate base-video and audio URLs needed to resume TTS, lip-sync or mux. On startup, processing jobs with durable provider state resume polling; only work interrupted before a request ID was recorded fails safely and refunds the job's full credit debit. User cancellation propagates to fal before local deletion, and account deletion attempts cancellation while still completing the privacy deletion if the provider cannot confirm it. Provider result objects use deterministic per-job keys so replaying ingestion after a crash overwrites instead of orphaning a duplicate.

## Authentication and authorization

- Access tokens are HMAC-signed, expire after 15 minutes by default, carry issuer, audience, JTI and token-version claims, and are checked against a live user record.
- Opaque 30-day refresh credentials are stored only as SHA-256 hashes. Refresh rotates the credential atomically, logout revokes it, account deletion cascades all sessions, and each user is capped at ten active sessions.
- Apple and Google identity tokens require RS256, a key ID, signature, issuer, audience, subject and expiry checks.
- Provider email linking occurs only when the provider says the email is verified.
- Every upload, job, history, media URL and deletion lookup is scoped by authenticated user ID.
- New StoreKit purchases use the authenticated user UUID as `appAccountToken`.
- The server verifies Apple's signed transaction JWS, bundle, product, environment, expiry/revocation and account token before persisting an entitlement.

The remaining account-security work is email verification/recovery, breached-password screening, provider nonce coverage, refresh-token-family reuse response and a user-facing all-device session-management control; see `docs/SECURITY_AND_PRIVACY.md`.

## Scalability and known limits

- Global snapshot writes are safe but not high-throughput.
- PostgreSQL-backed API/IP and authenticated-user rate limits survive restarts and coordinate across instances. Paid job concurrency is user-scoped but still evaluated through the serialized store transaction.
- Durable fal request resume/cancel is implemented and covered by an injected no-spend queue contract test; a real paid-provider kill/restart/cancel test is still required in staging.
- No durable cleanup/deletion outbox or scheduled reconciliation worker exists yet.
- No measured production SLO, traffic capacity, or cost envelope exists.

These are explicitly BLOCKED in `release/RELEASE_READINESS.md`; production deployment must not proceed until the owner accepts or resolves them.
