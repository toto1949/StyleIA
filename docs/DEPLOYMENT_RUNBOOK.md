# SceneMe Deployment Runbook

No step in this document authorizes spending, production mutation, build upload or release. The owner must approve the change window and secrets/configuration first.

## Preconditions

1. Select staging/production region, managed PostgreSQL plan, private S3/R2 bucket and budget.
2. Configure private bucket public-access block, encryption, CORS only for required signed PUT, versioning/recovery, lifecycle and a least-privilege service credential. Add a short lifecycle for abandoned `private/*/uploads/*/incoming.jpg` objects; generation reads only internal `validated.jpg` keys.
3. Obtain secrets through Render/secret files: database URL, object-storage values, JWT/encryption secrets, fal/OpenAI keys, Sign in with Apple values, the App Store Server API `.p8`, and paths to current Apple root CA DER certificates. Configure numeric Apple app ID `6822467260`, issuer ID `bcc9e67d-a7f4-444f-a1a2-9deefff625fd`, and key ID `399AQ2HR33`. Confirm the four `STYLEAI_*RATE_LIMIT*` values are positive and appropriate for expected client polling before deploying.
4. Confirm `com.sceneme.app`, Apple organization/team, four subscription IDs and notification URLs.
5. Approve finite commercial limits/cost controls or explicitly accept the risk in writing.
6. All required checks in `docs/QA_CHECKLIST.md` and `release/RELEASE_READINESS.md` must be PASS.

## Staging deploy

1. Record Git SHA, dependency lock hash, migration list and existing service/database/bucket identifiers.
2. Create a database backup and prove it is restorable to a separate instance.
3. Run `cd Backend && npm ci && npm audit --omit=dev && npm run db:migrate`.
4. For legacy data, run `npm run storage:migrate-legacy` first and review its recoverable/missing counts. Recover every missing file where possible. After the owner reviews any unavoidable loss, run it with `--apply` to copy validated JPEGs to private storage and produce `data/styleai.private-storage.json`. The generated file is mode `0600` and gitignored; protect it as user data.
5. Run `npm run db:import-json -- --file=./data/styleai.private-storage.json`; review checksum/counts; only then add `--apply` against an empty migrated database. Do not import the legacy snapshot directly because it contains server-local paths and formerly public URLs.
6. Migrate historical generated results separately: copy every reachable image/video result into the job's private `imageObjectKey`/`videoObjectKey`, and mark inaccessible history unavailable. Never retain provider URLs as the durable production copy.
7. Update the existing `StyleIA` Render service in place in Virginia (US East) so `https://styleia.onrender.com` remains stable. Use the Blueprint values as the configuration source, but do not create a second web service. Keep auto-deploy disabled. Confirm startup fails if a required value is omitted, then restore it.
8. Verify `/health`, `/privacy`, `/terms`, `/v1/scenes`, authentication and authenticated WebSocket over HTTPS/WSS. Confirm a refresh rotates once, replaying the old refresh returns `401`, and logout revokes the current refresh credential.
9. Run two-user object isolation, deletion, idempotency, restart, multi-instance rate-limit and backup/restore tests.
10. With explicit spending approval, run one solo image, one companion image, one video and one talking video. Record provider request IDs, duration, outcome and actual cost without recording user photos or signed URLs.
11. Send Apple Sandbox test notification and complete purchase lifecycle matrix.

## Production change

1. Owner approves exact SHA, infrastructure cost, maintenance window and rollback decision maker.
2. Freeze writes or place the old service in maintenance mode if importing legacy JSON.
3. Capture PostgreSQL backup/PITR marker, legacy JSON checksum/counts and object inventory.
4. Apply migrations through Render `preDeployCommand`; do not import twice.
5. Deploy one instance; watch startup/readiness, database connections, memory and logs.
   Existing pre-release bearer tokens lack the new issuer/audience/JTI claims and will require users to sign in again after this deployment. Announce this expected one-time development-session reset; do not weaken production token validation to preserve old tokens.
6. Run non-destructive smoke: health/legal/catalog, test account auth, upload to a dedicated test prefix, owned signed download, then delete it.
7. Only with provider-spend approval, run one production generation using a consented non-sensitive test image and delete the result.
8. Validate WSS progress, history after restart, entitlement sync and Notifications V2.
9. Open traffic gradually. Monitor 5xx, p95 latency, DB saturation, failed/stuck jobs, provider costs, storage errors and Apple verification failures.
10. Close the change only after the observation window and backup/object checks pass.

## iOS release candidate

1. Increment build number; keep marketing version `1.0`.
2. Confirm Release API is `https://styleia.onrender.com/v1`, debug controls are compiled out, Google is intentionally configured or hidden, and privacy/legal/support URLs are final.
3. Run unit/UI suite and unsigned Release compile, then archive with the verified Apple team/profile.
4. Validate the archive, dependency privacy reports, entitlements, icon and export-compliance answers.
5. Owner authorizes TestFlight upload. Record archive SHA, version/build, Xcode version and upload result.
6. Complete TestFlight checklist before selecting a build for review.

## Monitoring and alert thresholds

Rollback or disable new provider submissions for: sustained 5xx above 2%, p95 API latency above 2 seconds excluding generation polling, database connection exhaustion, cross-user authorization anomaly, repeated signed-URL failures, unbounded provider spend, entitlement verification failure spike, or confirmed sensitive-data logging/exposure.

No public App Store release is performed by this runbook without a final owner message approving the exact build and release mode.
