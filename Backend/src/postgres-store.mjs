import fs from "node:fs";
import path from "node:path";
import pg from "pg";

const { Pool } = pg;
const STORE_LOCK_ID = 1_938_447_102;

/**
 * PostgreSQL compatibility repository for the existing route layer.
 *
 * It preserves the JsonStore snapshot/mutate contract so the product can move
 * to durable storage without rewriting every working route at once. Mutations
 * are serialized with a transaction-scoped advisory lock; dedicated targeted
 * repositories should replace this bridge as traffic grows.
 */
export class PostgresStore {
  constructor(connectionString, { sslRejectUnauthorized = true } = {}) {
    // The Supabase shared pooler signs its TLS certificates with a private CA.
    // Only trust the explicitly installed CA; never disable certificate checks.
    const caFile = String(process.env.DATABASE_SSL_CA_FILE || "").trim();
    const sslCA = caFile ? fs.readFileSync(path.resolve(process.cwd(), caFile), "utf8") : undefined;
    this.pool = new Pool({
      connectionString,
      max: Number(process.env.DATABASE_POOL_MAX || 10),
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 10_000,
      statement_timeout: 15_000,
      application_name: "sceneme-backend",
      ssl: isLocalDatabase(connectionString)
        ? false
        : { rejectUnauthorized: sslRejectUnauthorized, ...(sslCA ? { ca: sslCA } : {}) }
    });
    this.lastRateLimitCleanupAt = 0;
  }

  async init() {
    const result = await this.pool.query("select to_regclass('public.users') as users_table");
    if (!result.rows[0]?.users_table) {
      throw new Error("Database migrations are missing. Run `npm run db:migrate` before starting SceneMe.");
    }
  }

  async close() {
    await this.pool.end();
  }

  async snapshot() {
    const client = await this.pool.connect();
    try {
      return await readSnapshot(client);
    } finally {
      client.release();
    }
  }

  async mutate(operation) {
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      await client.query("select pg_advisory_xact_lock($1)", [STORE_LOCK_ID]);
      const data = await readSnapshot(client, true);
      const result = await operation(data);
      await writeSnapshot(client, data);
      await client.query("commit");
      return result;
    } catch (error) {
      await client.query("rollback").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Atomically consumes one fixed-window allowance across every service
   * instance sharing this database. Only a keyed digest is stored; raw IP
   * addresses and bearer tokens never enter the rate-limit table.
   */
  async consumeRateLimit(scope, subjectHash, limit, windowMs) {
    const windowSeconds = Math.max(1, Math.ceil(windowMs / 1_000));
    const result = await this.pool.query(`
      with boundary as (
        select to_timestamp(
          floor(extract(epoch from statement_timestamp()) / $3::double precision) * $3::double precision
        ) as window_start
      )
      insert into rate_limit_windows (
        scope, subject_hash, window_start, request_count, expires_at
      )
      select $1, $2, window_start, 1, window_start + ($3 * interval '1 second')
      from boundary
      on conflict (scope, subject_hash, window_start) do update set
        request_count = rate_limit_windows.request_count + 1,
        expires_at = excluded.expires_at
      returning request_count, expires_at
    `, [scope, subjectHash, windowSeconds]);

    const count = Number(result.rows[0].request_count);
    const resetAt = new Date(result.rows[0].expires_at).getTime();
    this.scheduleRateLimitCleanup();
    return {
      allowed: count <= limit,
      remaining: Math.max(0, limit - count),
      resetAt
    };
  }

  async createRefreshSession(userId, refreshTokenHash, expiresAt) {
    await this.pool.query("delete from sessions where expires_at <= now() or revoked_at is not null and revoked_at < now() - interval '7 days'");
    await this.pool.query(`
      insert into sessions (user_id, refresh_token_hash, expires_at)
      values ($1, $2, $3::timestamptz)
    `, [userId, refreshTokenHash, expiresAt]);
    await this.pool.query(`
      delete from sessions
      where id in (
        select id from sessions
        where user_id = $1 and revoked_at is null
        order by created_at desc
        offset 10
      )
    `, [userId]);
  }

  async rotateRefreshSession(oldHash, newHash, expiresAt) {
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      const current = await client.query(`
        select s.id, s.user_id
        from sessions s
        join users u on u.id = s.user_id
        where s.refresh_token_hash = $1
          and s.revoked_at is null
          and s.expires_at > now()
          and u.deleted_at is null
          and u.status = 'active'
        for update of s
      `, [oldHash]);
      if (current.rowCount !== 1) {
        await client.query("rollback");
        return null;
      }
      await client.query("update sessions set revoked_at = now(), last_used_at = now() where id = $1", [current.rows[0].id]);
      await client.query(`
        insert into sessions (user_id, refresh_token_hash, expires_at)
        values ($1, $2, $3::timestamptz)
      `, [current.rows[0].user_id, newHash, expiresAt]);
      await client.query("commit");
      return current.rows[0].user_id;
    } catch (error) {
      await client.query("rollback").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  async revokeRefreshSession(refreshTokenHash) {
    await this.pool.query(`
      update sessions
      set revoked_at = coalesce(revoked_at, now()), last_used_at = now()
      where refresh_token_hash = $1
    `, [refreshTokenHash]);
  }

  scheduleRateLimitCleanup() {
    const now = Date.now();
    if (now - this.lastRateLimitCleanupAt < 5 * 60_000) {
      return;
    }
    this.lastRateLimitCleanupAt = now;
    void this.pool.query(`
      delete from rate_limit_windows
      where expires_at < statement_timestamp() - interval '1 hour'
    `).catch(() => {});
  }
}

async function readSnapshot(client, forUpdate = false) {
  const suffix = forUpdate ? " for update" : "";
  // A checked-out pg client executes one statement at a time. Keep these
  // sequential so transaction snapshots remain deterministic and compatible
  // with pg 9, which removes concurrent client.query calls.
  const usersResult = await client.query(`select * from users where deleted_at is null order by created_at${suffix}`);
  const identitiesResult = await client.query(`select * from auth_identities order by id${suffix}`);
  const uploadsResult = await client.query(`select * from uploads where deleted_at is null order by created_at${suffix}`);
  const jobsResult = await client.query(`select * from generation_jobs order by created_at${suffix}`);
  const usageResult = await client.query(`select * from usage_counters order by period_start${suffix}`);
  const creditAccountsResult = await client.query(`select * from credit_accounts order by user_id${suffix}`);
  const creditGrantsResult = await client.query(`select * from credit_grants order by created_at${suffix}`);
  const creditLedgerResult = await client.query(`select * from credit_ledger order by created_at${suffix}`);
  const entitlementsResult = await client.query(`select * from subscription_entitlements order by user_id${suffix}`);
  const transactionsResult = await client.query(`select * from app_store_transactions order by created_at${suffix}`);
  const notificationsResult = await client.query(`select * from app_store_notifications order by received_at${suffix}`);

  const identitiesByUser = new Map();
  for (const identity of identitiesResult.rows) {
    const entry = identitiesByUser.get(identity.user_id) || {};
    entry[identity.provider] = identity;
    identitiesByUser.set(identity.user_id, entry);
  }

  const uploads = uploadsResult.rows.map((row) => ({
    ...(row.metadata || {}),
    id: row.id,
    userId: row.user_id,
    s3Key: row.storage_key,
    status: legacyUploadStatus(row.status),
    size: Number(row.size_bytes || 0),
    contentType: row.content_type,
    width: row.width,
    height: row.height,
    sha256: row.sha256,
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at)
  }));

  const uploadKeyById = new Map(uploads.map((upload) => [upload.id, upload.s3Key]));
  const jobPublicIdById = new Map(jobsResult.rows.map((row) => [row.id, row.public_id]));

  return {
    users: usersResult.rows.map((row) => {
      const identities = identitiesByUser.get(row.id) || {};
      return {
        id: row.id,
        email: row.email || "",
        fullName: row.full_name || "",
        passwordHash: row.password_hash || "",
        passwordSalt: row.password_salt || "",
        tokenVersion: Number(row.token_version || 0),
        appleSub: identities.apple?.provider_subject || "",
        appleRefreshToken: identities.apple?.encrypted_refresh_token || "",
        googleSub: identities.google?.provider_subject || "",
        createdAt: iso(row.created_at),
        updatedAt: iso(row.updated_at)
      };
    }),
    uploads,
    jobs: jobsResult.rows.map((row) => ({
      ...(row.request_payload || {}),
      ...(row.response_payload || {}),
      id: row.id,
      jobId: row.public_id,
      userId: row.user_id,
      sourceJobId: row.parent_job_id ? jobPublicIdById.get(row.parent_job_id) || null : null,
      s3Key: row.subject_upload_id ? uploadKeyById.get(row.subject_upload_id) || "" : "",
      companionS3Key: row.companion_upload_id
        ? uploadKeyById.get(row.companion_upload_id) || null
        : null,
      type: row.kind === "video" ? "scene-video" : "scene",
      status: row.status === "cancel_requested" ? "processing" : row.status,
      progress: row.progress,
      providerRequestId: row.provider_request_id || null,
      idempotencyKey: row.idempotency_key || null,
      attemptCount: row.attempt_count,
      estimatedCostUSD: Number(row.estimated_cost_usd || 0),
      actualCostUSD: row.actual_cost_usd == null ? null : Number(row.actual_cost_usd),
      creditCost: Number(row.credit_cost || 0),
      creditRefunded: Boolean(row.credit_refunded),
      error: row.error_message || row.response_payload?.error || "",
      createdAt: iso(row.created_at),
      updatedAt: iso(row.updated_at)
    })),
    usage: usageResult.rows.map((row) => ({
      userId: row.user_id,
      month: iso(row.period_start).slice(0, 7),
      generations: row.image_generations,
      videoGenerations: row.video_generations,
      estimatedCostUSD: Number(row.estimated_cost_usd || 0),
      actualCostUSD: Number(row.actual_cost_usd || 0)
    })),
    creditAccounts: creditAccountsResult.rows.map((row) => ({
      userId: row.user_id,
      balance: Number(row.balance),
      updatedAt: iso(row.updated_at)
    })),
    creditGrants: creditGrantsResult.rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      grantKey: row.grant_key,
      sourceType: row.source_type,
      tier: row.tier,
      amount: Number(row.amount),
      productId: row.product_id,
      transactionId: row.transaction_id,
      grantPeriodStart: nullableISO(row.grant_period_start),
      createdAt: iso(row.created_at)
    })),
    creditLedger: creditLedgerResult.rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      grantId: row.grant_id,
      jobId: row.job_public_id,
      eventType: row.event_type,
      operation: row.operation,
      amount: Number(row.amount),
      balanceAfter: Number(row.balance_after),
      idempotencyKey: row.idempotency_key,
      metadata: row.metadata || {},
      createdAt: iso(row.created_at)
    })),
    entitlements: entitlementsResult.rows.map((row) => ({
      userId: row.user_id,
      tier: row.tier,
      productId: row.product_id,
      originalTransactionId: row.original_transaction_id,
      environment: row.environment,
      status: row.status,
      expiresAt: nullableISO(row.expires_at),
      gracePeriodExpiresAt: nullableISO(row.grace_period_expires_at),
      lastTransactionId: row.last_transaction_id,
      lastVerifiedAt: nullableISO(row.last_verified_at),
      updatedAt: iso(row.updated_at)
    })),
    appStoreTransactions: transactionsResult.rows.map((row) => ({
      transactionId: row.transaction_id,
      originalTransactionId: row.original_transaction_id,
      userId: row.user_id,
      appAccountToken: row.app_account_token,
      productId: row.product_id,
      environment: row.environment,
      purchasedAt: nullableISO(row.purchased_at),
      expiresAt: nullableISO(row.expires_at),
      revokedAt: nullableISO(row.revoked_at),
      revocationReason: row.revocation_reason,
      isUpgraded: row.is_upgraded,
      signedTransaction: row.signed_transaction,
      createdAt: iso(row.created_at),
      updatedAt: iso(row.updated_at)
    })),
    appStoreNotifications: notificationsResult.rows.map((row) => ({
      notificationUUID: row.notification_uuid,
      notificationType: row.notification_type,
      subtype: row.subtype,
      environment: row.environment,
      signedDate: nullableISO(row.signed_date),
      signedPayload: row.signed_payload,
      processingStatus: row.processing_status,
      errorMessage: row.error_message,
      receivedAt: iso(row.received_at),
      processedAt: nullableISO(row.processed_at)
    }))
  };
}

async function writeSnapshot(client, data) {
  await syncUsers(client, data.users || []);
  await syncUploads(client, data.uploads || []);
  await syncJobs(client, data.jobs || [], data.uploads || []);
  await syncUsage(client, data.usage || []);
  await syncCreditAccounts(client, data.creditAccounts || []);
  await syncCreditGrants(client, data.creditGrants || []);
  await syncCreditLedger(client, data.creditLedger || []);
  await syncEntitlements(client, data.entitlements || []);
  await syncAppStoreTransactions(client, data.appStoreTransactions || []);
  await syncAppStoreNotifications(client, data.appStoreNotifications || []);
}

async function syncUsers(client, users) {
  const ids = users.map((user) => user.id);
  await deleteMissing(client, "users", "id", ids);

  for (const user of users) {
    await client.query(`
      insert into users (
        id, email, full_name, password_hash, password_salt, token_version, created_at, updated_at
      ) values ($1, nullif($2, ''), $3, nullif($4, ''), nullif($5, ''), $6, coalesce($7::timestamptz, now()), now())
      on conflict (id) do update set
        email = excluded.email,
        full_name = excluded.full_name,
        password_hash = excluded.password_hash,
        password_salt = excluded.password_salt,
        token_version = excluded.token_version,
        updated_at = now()
    `, [
      user.id,
      user.email || "",
      user.fullName || "",
      user.passwordHash || "",
      user.passwordSalt || "",
      Number(user.tokenVersion || 0),
      nullableDate(user.createdAt)
    ]);

    await syncIdentity(client, user, "apple", user.appleSub, user.appleRefreshToken);
    await syncIdentity(client, user, "google", user.googleSub, null);
  }
}

async function syncIdentity(client, user, provider, subject, encryptedRefreshToken) {
  if (!subject) {
    await client.query("delete from auth_identities where user_id = $1 and provider = $2", [user.id, provider]);
    return;
  }
  await client.query(`
    insert into auth_identities (
      user_id, provider, provider_subject, provider_email, email_verified, encrypted_refresh_token
    ) values ($1, $2, $3, nullif($4, '')::citext, true, $5)
    on conflict (provider, provider_subject) do update set
      user_id = excluded.user_id,
      provider_email = excluded.provider_email,
      encrypted_refresh_token = coalesce(excluded.encrypted_refresh_token, auth_identities.encrypted_refresh_token),
      updated_at = now()
  `, [user.id, provider, subject, user.email || "", encryptedRefreshToken || null]);
}

async function syncUploads(client, uploads) {
  const ids = uploads.map((upload) => upload.id);
  await deleteMissing(client, "uploads", "id", ids);

  for (const upload of uploads) {
    const metadata = withoutKeys(upload, [
      "id", "userId", "s3Key", "status", "size", "contentType", "width", "height",
      "sha256", "createdAt", "updatedAt"
    ]);
    await client.query(`
      insert into uploads (
        id, user_id, storage_key, purpose, status, content_type, size_bytes,
        width, height, sha256, expires_at, validated_at, metadata, created_at, updated_at
      ) values (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
        $11::timestamptz, $12::timestamptz, $13::jsonb, coalesce($14::timestamptz, now()), now()
      )
      on conflict (id) do update set
        storage_key = excluded.storage_key,
        status = excluded.status,
        content_type = excluded.content_type,
        size_bytes = excluded.size_bytes,
        width = excluded.width,
        height = excluded.height,
        sha256 = excluded.sha256,
        expires_at = excluded.expires_at,
        validated_at = excluded.validated_at,
        metadata = excluded.metadata,
        updated_at = now()
    `, [
      upload.id,
      upload.userId,
      upload.s3Key,
      upload.purpose === "companion" ? "companion" : "subject",
      databaseUploadStatus(upload.status),
      upload.contentType || "image/jpeg",
      Number(upload.size || 0),
      upload.width || null,
      upload.height || null,
      upload.sha256 || null,
      nullableDate(upload.expiresAt),
      nullableDate(upload.validatedAt || (upload.status === "uploaded" ? upload.updatedAt : null)),
      JSON.stringify(metadata),
      nullableDate(upload.createdAt)
    ]);
  }
}

async function syncJobs(client, jobs, uploads) {
  const ids = jobs.map((job) => job.id);
  await deleteMissing(client, "generation_jobs", "id", ids);
  const uploadIdByKey = new Map(uploads.map((upload) => [upload.s3Key, upload.id]));

  for (const job of jobs) {
    const kind = job.type === "scene-video" ? "video" : "image";
    const operation = kind === "video" ? "video" : (job.isReroll ? "reroll" : "generate");
    const payload = withoutKeys(job, [
      "id", "jobId", "userId", "sourceJobId", "s3Key", "companionS3Key", "type",
      "status", "progress", "providerRequestId", "attemptCount", "estimatedCostUSD", "actualCostUSD",
      "creditCost", "creditRefunded",
      "error", "createdAt", "updatedAt"
    ]);
    await client.query(`
      insert into generation_jobs (
        id, public_id, user_id, subject_upload_id, companion_upload_id, kind, operation,
        status, progress, idempotency_key, provider, provider_request_id, attempt_count,
        estimated_cost_usd, actual_cost_usd, credit_cost, credit_refunded,
        error_message, request_payload, response_payload,
        created_at, updated_at
      ) values (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'fal', $11, $12, $13, $14,
        $15, $16, nullif($17, ''), $18::jsonb, '{}'::jsonb, coalesce($19::timestamptz, now()), now()
      )
      on conflict (id) do update set
        status = excluded.status,
        progress = excluded.progress,
        idempotency_key = excluded.idempotency_key,
        provider_request_id = excluded.provider_request_id,
        attempt_count = excluded.attempt_count,
        estimated_cost_usd = excluded.estimated_cost_usd,
        actual_cost_usd = excluded.actual_cost_usd,
        credit_cost = excluded.credit_cost,
        credit_refunded = excluded.credit_refunded,
        error_message = excluded.error_message,
        request_payload = excluded.request_payload,
        updated_at = now()
    `, [
      job.id,
      job.jobId,
      job.userId,
      uploadIdByKey.get(job.s3Key) || null,
      uploadIdByKey.get(job.companionS3Key) || null,
      kind,
      operation,
      databaseJobStatus(job.status),
      Math.max(0, Math.min(100, Number(job.progress || 0))),
      job.idempotencyKey || null,
      job.providerRequestId || null,
      Number(job.attemptCount || 0),
      Number(job.estimatedCostUSD || 0),
      job.actualCostUSD == null ? null : Number(job.actualCostUSD),
      Number(job.creditCost || 0),
      Boolean(job.creditRefunded),
      job.error || "",
      JSON.stringify(payload),
      nullableDate(job.createdAt)
    ]);
  }

  for (const job of jobs) {
    if (job.sourceJobId) {
      await client.query(`
        update generation_jobs child
        set parent_job_id = parent.id
        from generation_jobs parent
        where child.id = $1 and parent.public_id = $2
      `, [job.id, job.sourceJobId]);
    }
  }
}

async function syncCreditAccounts(client, accounts) {
  for (const account of accounts) {
    await client.query(`
      insert into credit_accounts (user_id, balance, updated_at)
      values ($1, $2, coalesce($3::timestamptz, now()))
      on conflict (user_id) do update set balance = excluded.balance, updated_at = excluded.updated_at
    `, [account.userId, Number(account.balance || 0), nullableDate(account.updatedAt)]);
  }
}

async function syncCreditGrants(client, grants) {
  for (const grant of grants) {
    await client.query(`
      insert into credit_grants (
        id, user_id, grant_key, source_type, tier, amount, product_id,
        transaction_id, grant_period_start, created_at
      ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9::timestamptz, coalesce($10::timestamptz, now()))
      on conflict (user_id, grant_key) do nothing
    `, [
      grant.id, grant.userId, grant.grantKey, grant.sourceType, grant.tier,
      Number(grant.amount), grant.productId || null, grant.transactionId || null,
      nullableDate(grant.grantPeriodStart), nullableDate(grant.createdAt)
    ]);
  }
}

async function syncCreditLedger(client, entries) {
  for (const entry of entries) {
    await client.query(`
      insert into credit_ledger (
        id, user_id, grant_id, job_public_id, event_type, operation, amount,
        balance_after, idempotency_key, metadata, created_at
      ) values (
        $1, $2, $3, $4::uuid, $5, $6, $7, $8, $9, $10::jsonb,
        coalesce($11::timestamptz, now())
      ) on conflict (user_id, idempotency_key) do nothing
    `, [
      entry.id, entry.userId, entry.grantId || null, entry.jobId || null,
      entry.eventType, entry.operation || null, Number(entry.amount),
      Number(entry.balanceAfter), entry.idempotencyKey,
      JSON.stringify(entry.metadata || {}), nullableDate(entry.createdAt)
    ]);
  }
}

async function syncUsage(client, usageRows) {
  const keys = usageRows.map((row) => `${row.userId}:${row.month}`);
  if (keys.length === 0) {
    await client.query("delete from usage_counters");
  } else {
    await client.query(`
      delete from usage_counters
      where user_id::text || ':' || to_char(period_start, 'YYYY-MM') <> all($1::text[])
    `, [keys]);
  }

  for (const usage of usageRows) {
    await client.query(`
      insert into usage_counters (
        user_id, period_start, image_generations, video_generations,
        estimated_cost_usd, actual_cost_usd, updated_at
      ) values ($1, ($2 || '-01')::date, $3, $4, $5, $6, now())
      on conflict (user_id, period_start) do update set
        image_generations = excluded.image_generations,
        video_generations = excluded.video_generations,
        estimated_cost_usd = excluded.estimated_cost_usd,
        actual_cost_usd = excluded.actual_cost_usd,
        updated_at = now()
    `, [
      usage.userId,
      usage.month,
      Number(usage.generations || 0),
      Number(usage.videoGenerations || 0),
      Number(usage.estimatedCostUSD || 0),
      Number(usage.actualCostUSD || 0)
    ]);
  }
}

async function syncEntitlements(client, entitlements) {
  for (const entitlement of entitlements) {
    await client.query(`
      insert into subscription_entitlements (
        user_id, tier, product_id, original_transaction_id, environment, status,
        expires_at, grace_period_expires_at, last_transaction_id, last_verified_at, updated_at
      ) values ($1, $2, $3, $4, $5, $6, $7::timestamptz, $8::timestamptz, $9, $10::timestamptz, now())
      on conflict (user_id) do update set
        tier = excluded.tier,
        product_id = excluded.product_id,
        original_transaction_id = excluded.original_transaction_id,
        environment = excluded.environment,
        status = excluded.status,
        expires_at = excluded.expires_at,
        grace_period_expires_at = excluded.grace_period_expires_at,
        last_transaction_id = excluded.last_transaction_id,
        last_verified_at = excluded.last_verified_at,
        updated_at = now()
    `, [
      entitlement.userId,
      entitlement.tier || "free",
      entitlement.productId || null,
      entitlement.originalTransactionId || null,
      entitlement.environment || null,
      entitlement.status || "inactive",
      nullableDate(entitlement.expiresAt),
      nullableDate(entitlement.gracePeriodExpiresAt),
      entitlement.lastTransactionId || null,
      nullableDate(entitlement.lastVerifiedAt)
    ]);
  }
}

async function syncAppStoreTransactions(client, transactions) {
  for (const transaction of transactions) {
    await client.query(`
      insert into app_store_transactions (
        transaction_id, original_transaction_id, user_id, app_account_token, product_id,
        environment, purchased_at, expires_at, revoked_at, revocation_reason,
        is_upgraded, signed_transaction, created_at, updated_at
      ) values (
        $1, $2, $3, $4::uuid, $5, $6, $7::timestamptz, $8::timestamptz,
        $9::timestamptz, $10, $11, $12, coalesce($13::timestamptz, now()), now()
      )
      on conflict (transaction_id) do update set
        original_transaction_id = excluded.original_transaction_id,
        user_id = coalesce(excluded.user_id, app_store_transactions.user_id),
        app_account_token = coalesce(excluded.app_account_token, app_store_transactions.app_account_token),
        product_id = excluded.product_id,
        environment = excluded.environment,
        purchased_at = excluded.purchased_at,
        expires_at = excluded.expires_at,
        revoked_at = excluded.revoked_at,
        revocation_reason = excluded.revocation_reason,
        is_upgraded = excluded.is_upgraded,
        signed_transaction = excluded.signed_transaction,
        updated_at = now()
    `, [
      transaction.transactionId,
      transaction.originalTransactionId,
      transaction.userId || null,
      transaction.appAccountToken || null,
      transaction.productId,
      transaction.environment,
      nullableDate(transaction.purchasedAt),
      nullableDate(transaction.expiresAt),
      nullableDate(transaction.revokedAt),
      transaction.revocationReason ?? null,
      Boolean(transaction.isUpgraded),
      transaction.signedTransaction,
      nullableDate(transaction.createdAt)
    ]);
  }
}

async function syncAppStoreNotifications(client, notifications) {
  for (const notification of notifications) {
    await client.query(`
      insert into app_store_notifications (
        notification_uuid, notification_type, subtype, environment, signed_date,
        signed_payload, processing_status, error_message, received_at, processed_at
      ) values (
        $1::uuid, $2, $3, $4, $5::timestamptz, $6, $7, $8,
        coalesce($9::timestamptz, now()), $10::timestamptz
      )
      on conflict (notification_uuid) do update set
        processing_status = excluded.processing_status,
        error_message = excluded.error_message,
        processed_at = excluded.processed_at
    `, [
      notification.notificationUUID,
      notification.notificationType,
      notification.subtype || null,
      notification.environment || null,
      nullableDate(notification.signedDate),
      notification.signedPayload,
      notification.processingStatus || "received",
      notification.errorMessage || null,
      nullableDate(notification.receivedAt),
      nullableDate(notification.processedAt)
    ]);
  }
}

async function deleteMissing(client, table, column, values) {
  if (values.length === 0) {
    await client.query(`delete from ${table}`);
    return;
  }
  await client.query(`delete from ${table} where ${column} <> all($1::uuid[])`, [values]);
}

function withoutKeys(value, keys) {
  const copy = { ...(value || {}) };
  keys.forEach((key) => delete copy[key]);
  return copy;
}

function iso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function nullableDate(value) {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function nullableISO(value) {
  return value ? iso(value) : null;
}

function databaseUploadStatus(value) {
  return value === "uploaded" ? "validated" : value;
}

function legacyUploadStatus(value) {
  return value === "validated" ? "uploaded" : value;
}

function databaseJobStatus(value) {
  return ["pending", "processing", "completed", "failed", "cancel_requested", "cancelled", "dead_letter"]
    .includes(value) ? value : "failed";
}

function isLocalDatabase(connectionString) {
  try {
    const url = new URL(connectionString);
    return url.hostname === "localhost" || url.hostname === "127.0.0.1";
  } catch {
    return false;
  }
}
