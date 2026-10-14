# SceneMe Security and Privacy Review

Last updated: 2026-10-13
Scope: engineering controls and disclosure inputs; not legal advice.

## Data inventory

| Data | Purpose | Location/processors | Sensitivity | Deletion path |
| --- | --- | --- | --- | --- |
| Email, name, provider subject | Account access | PostgreSQL; Apple/Google during sign-in | Personal | In-app account deletion; provider token revocation attempted. |
| Password hash/salt | Email authentication | PostgreSQL | Credential | Cascade delete. PBKDF2-SHA256, 310k iterations. |
| Face/companion photos | AI scene creation and safety screening | Private S3/R2; short-lived transfer to OpenAI and fal.ai | Highly sensitive user content | Object + row deletion; provider retention disclosed separately. |
| Prompts, scene settings, spoken lines | Generation/customization | PostgreSQL; fal.ai; OpenAI for text features | User content | Job/account deletion. |
| Generated images/video/audio | Results/export/history | Private S3/R2; fal.ai during processing | Sensitive derived content | Result/account deletion. |
| Apple transaction data | Subscription verification | PostgreSQL; Apple | Purchase history | User link is removed on deletion; transaction audit retained as legally/operationally required. Retention needs counsel approval. |
| Credit grants, ledger, usage, job and security logs | Billing enforcement, support, fraud, reliability | PostgreSQL/log platform | Account activity | Credits do not expire; ledger retention/deletion policy requires counsel/accounting review. Logs must not contain tokens or signed URLs. |

## Implemented controls

- Production refuses local JSON/filesystem storage and requires PostgreSQL plus a private S3-compatible bucket.
- Uploads are owner-scoped and production media is accessed through short-lived signed URLs. Client-writable ingress keys are finalized to separate internal keys before moderation/generation, preventing reuse of an unexpired PUT URL from replacing approved content.
- JPEGs are fully decoded, pixel/byte limited, metadata-stripped and normalized before AI processing.
- Validated subject and companion photos are screened through OpenAI image moderation before paid generation; allow/block state is cached per upload and provider failure blocks generation rather than bypassing review.
- Provider output download is HTTPS-only, host-allowlisted and bounded by type/size/time.
- Account and result deletion remove controlled object keys; access tokens fail after user deletion.
- API errors are structured, responses disable caching, and baseline browser security headers are applied.
- Error logs use request paths rather than raw URLs, avoiding upload-token query leakage.
- Apple/Google JOSE algorithms, issuer, audience, signature, subject and expiry are validated; verified email is required for implicit linking.
- StoreKit transactions and Notifications V2 use Apple's official server library and trusted root certificates supplied at deploy time. Notification UUIDs and original transaction ownership are persisted.
- Provider/API credentials remain server-side and all documented secret values are placeholders.
- Production mock generation is disabled by default and missing credentials fail startup.

## Threat review

| Threat | Current mitigation | Residual action |
| --- | --- | --- |
| Cross-user photo/result access | Owner-scoped DB lookup and storage key prefix; signed GET created only during owned response serialization; hostile second-account job/upload/history HTTP checks pass | Run real S3/R2 signed-object integration suite. |
| Public bucket exposure | App code never sets public ACL; production requires object storage | Owner must enable block-public-access, encryption, least-privilege policy and audit logs. |
| Malicious/decompression-bomb upload | Bounded body/object size, actual Sharp decode and pixel limit | Add malware workflow if risk assessment requires it; fuzz malformed formats. |
| SSRF through provider URL | HTTPS and host allowlist, redirects rejected, response bounded | Confirm all current fal output hostnames in staging. |
| Duplicate paid work | Required UUID idempotency key and DB uniqueness; persisted fal request/model/phase; restart resumes queue status/result; deterministic result-object key; provider cancellation | Run a paid staging kill/restart/cancel test and reconcile provider billing records. |
| Subscription forgery/account switching | Verified Apple JWS, bundle/product/account-token checks, durable original transaction binding | Sandbox and Notifications V2 fixture tests remain blocked on Apple configuration. |
| Credential theft/session replay | Keychain on device; 15-minute issuer/audience/JTI/token-version access tokens; hashed 30-day refresh credentials rotate atomically; logout and account deletion revoke sessions; active-session cap | Add refresh-token-family reuse response, user-facing all-device revocation and operational session anomaly alerts. |
| Brute force/abuse | PostgreSQL-backed IP and authenticated-user windows, PBKDF2, structured `429` and `Retry-After`; raw IPs are HMACed | Add breached-password screening, email verification/reset and operational alerts. |
| AI abuse/NCII/impersonation | User-text moderation, pre-generation OpenAI image screening, fal safety checker, provider `has_nsfw_concepts` rejection, consent disclosure, and server-required friend-photo permission attestation | Add minor/NCII/CSAM and human escalation workflows. OpenAI documents that `sexual/minors` is text-only, so its image moderation is not a dedicated CSAM detector. |
| Sensitive logs | No request bodies, secrets, or signed query URLs intentionally logged | Redaction tests and centralized log-retention policy required. Mock logs currently include prompts and must not be used with real user data. |

## Privacy/App Store worksheet

The current privacy manifest declares linked identifiers/contact information, photos, videos, other user content, product interaction and purchase history, with no tracking. Confirm the assembled archive's third-party manifests and use Apple's App Privacy questionnaire to describe backend collection, not merely on-device APIs.

Recommended disclosure concepts for owner/counsel review:

- Photos and creative text are sent to service providers, including fal.ai and OpenAI, to perform requested AI processing and safety checks.
- Users must own or have permission to use photos, including photos of companions.
- Outputs are private to the authenticated account in SceneMe; exporting/sharing is a user action.
- Controlled data is deleted after an in-app deletion request, subject to narrowly stated security, transaction, backup and provider-retention limitations.
- AI output can be inaccurate or altered and must not be used for deception, harassment, sexual exploitation, impersonation, fraud, or unlawful purposes.

Review current provider terms and data-processing agreements before launch. Engineering did not verify a zero-retention guarantee from fal.ai or OpenAI and must not promise one.

## Required operational controls

- Separate staging/production accounts, databases, buckets, Apple keys and AI keys.
- Hardware-backed MFA for owner/admin accounts; least-privilege service identities; quarterly access review.
- Managed PostgreSQL encrypted backups/PITR and a witnessed restore drill.
- Bucket encryption, public-access block, versioning/recovery and lifecycle policies.
- Dependency and secret scanning in CI; patch SLA for critical/high findings.
- Crash/error monitoring, failed-generation and transaction alerts, latency SLOs, cost alerts and a global AI kill switch.
- Incident response contacts, breach assessment workflow, evidence retention and user/regulator notification decision tree.
- Documented retention periods for originals, results, failed jobs, pending uploads, logs, backups and Apple audit data.

## Launch blockers

1. No real object-storage isolation/deletion test.
2. Durable provider resume/cancel has no real paid staging kill/restart proof.
3. Session rotation is implemented, but email verification/recovery and refresh-family reuse response are incomplete.
4. Pre-generation image moderation and friend-photo permission attestation are implemented, but no real moderation-provider call, dedicated minor/NCII/CSAM process, or human escalation workflow exists.
5. No backup restore drill, centralized monitoring, cost alerts or incident response exercise.
6. Legal/privacy/terms copy and processor contracts have not been approved by qualified counsel.

References: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion), [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), [privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), and [OpenAI moderation guidance](https://developers.openai.com/api/docs/guides/moderation).
