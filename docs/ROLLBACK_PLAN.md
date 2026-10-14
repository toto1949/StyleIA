# SceneMe Rollback Plan

## Principles

- Stop new harm first: disable provider submissions or remove traffic from the faulty release.
- Preserve evidence and paid-job state; never delete production data to make a rollback easier.
- Application rollback and schema rollback are separate decisions.
- Prefer a forward fix for additive migrations. Use `001_initial.down.sql` only for an empty/abandoned environment; it is destructive. `002_durable_rate_limits.down.sql` drops only limiter counters but still requires a writer stop or compatible application rollback.

## Backend rollback

1. Incident lead declares rollback and records time, deploy ID, Git SHA and reason.
2. Disable new generation at the edge/config if costs, privacy or authorization are implicated.
3. Snapshot PostgreSQL and object inventory before changing anything.
4. Roll Render to the last known-good deploy only if that code understands the current schema.
5. If incompatible, deploy a forward compatibility patch; do not drop columns/tables while writes exist.
6. Mark uncertain in-flight jobs failed/refunded unless a persisted provider request can be reconciled. Do not resubmit automatically.
7. Verify health, auth, owned media, history, deletion and entitlement checks.
8. Reopen provider submissions gradually and document affected users/credits.

## Database recovery

- Additive migration failure before commit: the migration runner transaction rolls back and does not insert `schema_migrations`.
- Migration 002 rollback/reapply was exercised locally on disposable PostgreSQL 16. Migration 003 rollback is destructive to credit history and must not be executed after accepting paid jobs; restore the pre-migration backup or deploy a forward fix instead. Exercise 003 rollback/reapply only on disposable data before production.
- Bad data after deploy: stop writers, take a backup, restore PITR into a new database, compare row counts/representative records, then switch connection only with owner approval.
- Legacy import: importer refuses a nonempty database. If verification fails, discard the new empty target and repeat from the original JSON/backup; do not modify the source.
- Never run the down migration against production user data.

## Object storage recovery

- Revoke exposed credentials immediately and rotate Render secrets.
- Turn on bucket access logging/forensics and block public access.
- Restore deleted objects from versioning/recovery only after confirming the owning database record and user.
- If database rows were rolled back, reconcile orphan objects by prefix and age; quarantine before deletion.

## iOS/TestFlight rollback

- TestFlight: expire the defective build and direct testers to the last accepted build; uploaded build numbers cannot be reused.
- App Store before release: remove the selected build or developer-reject the submission.
- Phased/manual release: pause phased release where available. A shipped binary cannot be remotely removed from devices; submit an expedited fixed build if necessary.
- Keep server API backward compatible with the current public app during any backend rollback.

## Verification and closeout

Confirm no new duplicate charges, stuck jobs, entitlement drift, inaccessible media, deletion failures or cross-user access. Publish an internal incident timeline, root cause, user remediation, cost impact and preventive action owner. Owner/counsel decides whether user or regulatory notification is required.
