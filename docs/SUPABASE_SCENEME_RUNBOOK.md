# SceneMe — dedicated Supabase Free project migration

**Status:** preparation only. Creating the project, billing, database migration, data export, secrets, and production deployment each require owner confirmation. Never reuse Melora/ Memories to Melody database or storage credentials.

## Cost and suitability
- Supabase Free: a dedicated project with PostgreSQL (500 MB limit), file storage (1 GB limit), and a **50 MB maximum per stored file**.
- Free projects may pause after low activity; free tier does not provide managed daily backups. Before shipping, arrange verified periodic external exports and a recoverable off-site media backup.
- Video Director media might exceed 50 MB; check actual 720p video sizes. If so, use a private R2/S3 bucket instead of silently rejecting output.
- Keep the Render web service paid if consistent app launch response times are necessary; a free instance spins down.

## Prepare project and secrets

1. Create a **new**, separate Supabase project for SceneMe in `us-east-2`, with no Melora tables/data copied into it.
2. Under Storage, create a **private** bucket, e.g. `sceneme-private`, with no anonymous read access. Enable S3 protocol and generate a dedicated server-side access key pair under Storage > S3.
3. Use the project dashboard's **Connect** dialog to obtain a PostgreSQL connection string, using Supavisor session pooler if IPv6 direct connections are not reachable by Render. Confirm SSL configuration and password in the dashboard. Do **not** put connection strings or secrets in Git.
4. Store in Render environment variables for the **existing** `StyleIA` service:

   - `DATABASE_URL` = secret Supabase connection string (never log)
   - `DATABASE_SSL_REJECT_UNAUTHORIZED` = `true` when chain validates; configure the official CA if necessary
   - `OBJECT_STORAGE_BUCKET` = `sceneme-private` (or actual private bucket)
   - `OBJECT_STORAGE_REGION` = `us-east-2`
   - `OBJECT_STORAGE_ENDPOINT` = `https://<project-ref>.storage.supabase.co/storage/v1/s3`
   - `OBJECT_STORAGE_FORCE_PATH_STYLE` = `true`
   - `OBJECT_STORAGE_ACCESS_KEY_ID` and `OBJECT_STORAGE_SECRET_ACCESS_KEY` = server-only S3 keys (full bucket access; restrict operator access)
   - Other mandatory JWT/encryption, Apple Server API, OpenAI, fal.ai and spending-budget values from `Backend/README.md`

5. The client creates only short-lived presigned upload/download URLs; never put a full-access S3 secret in the iOS app.
6. Do not add an `Authorization` header to S3 presigned URLs: the signature already authorizes one operation.
7. Supabase S3 does not accept `x-amz-server-side-encryption`; the backend helper omits this header **only** for recognized Supabase Storage S3 endpoints. At-rest encryption remains provided by Supabase. Test full signed PUT, normalization, signed GET, deletion, and access isolation before launch.

## Preserve existing production records

Render's currently deployed August backend uses ephemeral JSON and local media paths. **Do not deploy a new version yet.**
1. Freeze old writes or schedule a maintenance window.
2. Export the current legacy JSON and media from the running Render instance **before any restart or redeploy**, if available; make a secure backup and checksum. Render free ephemeral storage may already have lost older data.
3. Run the current backend's `npm run storage:migrate-legacy` dry run against recovered files. Only apply once all expected photos/media are recovered or unavoidable losses are explicitly approved.
4. Initialize the new PostgreSQL database using migration scripts in ascending order. Supabase's management SQL migration runner can apply source SQL for `001`, `002` and `003`, after confirming all permissions and schema ownership.
5. Run `npm run db:import-json -- --file=...` dry-run, then --apply against an **empty** database; validate user, job and upload counts. Keep original JSON and private media until account login and history are verified.
6. Only after the private media and database are ready, update Render environment variables, deploy the approved GitHub commit, and check `GET /health` says `database: "postgresql"`.

## Reviewer login and launch verification

- Use `SCENEME_REVIEWER_EMAIL` and `SCENEME_REVIEWER_PASSWORD` temporarily on first PostgreSQL-backed production startup (password at least 16 characters).
- Use a publisher-controlled email inbox. Provisioner is idempotent and refuses to reset an existing account.
- Remove provisioning secrets after creation; restart and verify email/password sign-in persists.
- In App Store Connect, enter credentials under **App Review Information**, not the public description.
- Pro privileges are **not** manually granted; test subscription purchases/renewals with StoreKit Sandbox.
- Test a consenting dummy image, image creation, short video, signed files, account deletion, Restore Purchases, storage retention, rate limiting, and rollback.
