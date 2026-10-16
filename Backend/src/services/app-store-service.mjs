import crypto from "node:crypto";
import fs from "node:fs/promises";
import { Environment, SignedDataVerifier, Status } from "@apple/app-store-server-library";
import { config } from "../config.mjs";
import { base64URLEncode } from "../encoding.mjs";
import { HttpError } from "../http-utils.mjs";
import { store } from "./store-instance.mjs";
import { reviewAccessForUser } from "./reviewer-access.mjs";

const productionURL = "https://api.storekit.apple.com";
const sandboxURL = "https://api.storekit-sandbox.apple.com";
const transactionCache = new Map();
const verifierCache = new Map();
const productTiers = new Map([
  ["com.sceneme.creator.monthly", "creator"],
  ["com.sceneme.creator.yearly", "creator"],
  ["com.sceneme.pro.monthly", "pro"],
  ["com.sceneme.pro.yearly", "pro"]
]);
const planMonthlyCredits = Object.freeze({ free: 3, creator: 30, pro: 100 });

export const generationCreditCosts = Object.freeze({
  standardImage: 1,
  premiumImage: 2,
  silentVideo: 6,
  talkingVideo: 23
});

export async function appStoreTierForRequest(request, userId) {
  if (reviewAccessForUser(userId)) return "pro";
  if (config.nodeEnv !== "production" && config.enableMockGeneration) {
    return "pro";
  }

  const transactionId = String(request.headers["x-sceneme-app-store-transaction-id"] || "").trim();
  if (transactionId) {
    await syncAppStoreTransaction(transactionId, userId);
  }
  return entitlementTier(await subscriptionStatusForUser(userId));
}

export async function syncAppStoreTransaction(transactionId, userId) {
  if (!/^\d+$/.test(String(transactionId || ""))) {
    throw new HttpError(403, "The App Store purchase could not be verified.");
  }
  assertConfigured();

  const cacheKey = `${transactionId}:${userId}`;
  let verified = transactionCache.get(cacheKey);
  if (!verified || Date.now() - verified.fetchedAt > 5 * 60 * 1000) {
    const result = await fetchAndVerifyTransaction(transactionId);
    verified = { ...result, fetchedAt: Date.now() };
    transactionCache.set(cacheKey, verified);
  }

  validateTransaction(verified.transaction, transactionId, userId);
  await persistVerifiedTransaction({
    transaction: verified.transaction,
    signedTransaction: verified.signedTransaction,
    userId,
    status: statusForTransaction(verified.transaction),
    verifiedAt: new Date().toISOString()
  });
  return subscriptionStatusForUser(userId);
}

export async function processAppStoreNotification(signedPayload) {
  assertVerificationConfigured();
  const compactJWS = String(signedPayload || "").trim();
  if (!compactJWS) {
    throw new HttpError(400, "signedPayload is required.");
  }

  const { payload, verifier, environment } = await verifyNotificationInEitherEnvironment(compactJWS);
  const notificationUUID = String(payload.notificationUUID || "");
  if (!/^[0-9a-f-]{36}$/i.test(notificationUUID)) {
    throw new HttpError(400, "The App Store notification identifier is invalid.");
  }

  const existing = (await store.snapshot()).appStoreNotifications?.find(
    (notification) => notification.notificationUUID === notificationUUID
      && notification.processingStatus === "processed"
  );
  if (existing) {
    return { duplicate: true, notificationUUID };
  }

  const receivedAt = new Date().toISOString();
  const baseNotification = {
    notificationUUID,
    notificationType: String(payload.notificationType || "UNKNOWN"),
    subtype: payload.subtype ? String(payload.subtype) : null,
    environment,
    signedDate: millisISO(payload.signedDate),
    signedPayload: compactJWS,
    receivedAt
  };
  await upsertNotification({
    ...baseNotification,
    processingStatus: "received",
    errorMessage: null,
    processedAt: null
  });

  try {
    const signedTransaction = payload.data?.signedTransactionInfo;
    if (signedTransaction) {
      const transaction = await verifier.verifyAndDecodeTransaction(signedTransaction);
      const snapshot = await store.snapshot();
      const prior = snapshot.appStoreTransactions?.find((candidate) =>
        candidate.originalTransactionId === transaction.originalTransactionId
      );
      const userId = transaction.appAccountToken || prior?.userId || null;
      if (userId) {
        validateTransaction(transaction, transaction.transactionId, userId);
        let gracePeriodExpiresAt = null;
        if (payload.data?.signedRenewalInfo) {
          const renewal = await verifier.verifyAndDecodeRenewalInfo(payload.data.signedRenewalInfo);
          gracePeriodExpiresAt = millisISO(renewal.gracePeriodExpiresDate);
        }
        await persistVerifiedTransaction({
          transaction,
          signedTransaction,
          userId,
          status: statusForNotification(payload, transaction),
          gracePeriodExpiresAt,
          verifiedAt: millisISO(payload.signedDate) || receivedAt
        });
      }
    }

    await upsertNotification({
      ...baseNotification,
      processingStatus: "processed",
      errorMessage: null,
      processedAt: new Date().toISOString()
    });
    return { duplicate: false, notificationUUID };
  } catch (error) {
    await upsertNotification({
      ...baseNotification,
      processingStatus: "failed",
      errorMessage: String(error?.message || error).slice(0, 500),
      processedAt: null
    });
    throw error;
  }
}

export async function subscriptionStatusForUser(userId) {
  const review = reviewAccessForUser(userId);
  if (review) return review;
  const data = await store.snapshot();
  const entitlement = data.entitlements?.find((candidate) => candidate.userId === userId);
  if (!entitlement) {
    return { tier: "free", status: "inactive", expiresAt: null, productId: null };
  }
  return {
    tier: entitlementTier(entitlement),
    status: entitlement.status,
    expiresAt: entitlement.expiresAt || null,
    gracePeriodExpiresAt: entitlement.gracePeriodExpiresAt || null,
    productId: entitlement.productId || null,
    environment: entitlement.environment || null,
    lastVerifiedAt: entitlement.lastVerifiedAt || null
  };
}

export function requireTier(actual, required, feature) {
  const levels = { free: 0, creator: 1, pro: 2 };
  if ((levels[actual] ?? 0) < (levels[required] ?? 0)) {
    const plan = required === "pro" ? "Pro" : "Creator";
    throw new HttpError(403, `${feature} requires the ${plan} plan.`);
  }
}

export async function creditStatusForUser(userId) {
  return store.mutate(async (data) => creditStatusInStore(data, userId));
}

export function creditStatusInStore(data, userId, now = new Date()) {
  ensureDueCreditGrantsInStore(data, userId, now);
  const account = data.creditAccounts.find((candidate) => candidate.userId === userId);
  const grants = data.creditGrants
    .filter((grant) => grant.userId === userId)
    .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt));
  return {
    balance: Number(account?.balance || 0),
    grantsNeverExpire: true,
    starterCredits: planMonthlyCredits.free,
    creatorMonthlyCredits: planMonthlyCredits.creator,
    proMonthlyCredits: planMonthlyCredits.pro,
    latestGrantAt: grants[0]?.createdAt || null
  };
}

export function consumeCreditsInStore(data, userId, {
  cost,
  jobId,
  operation,
  now = new Date()
}) {
  ensureDueCreditGrantsInStore(data, userId, now);
  const amount = Number(cost);
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new Error("Credit cost must be a positive integer.");
  }
  const idempotencyKey = `job:${jobId}:debit`;
  const existing = data.creditLedger.find((entry) =>
    entry.userId === userId && entry.idempotencyKey === idempotencyKey
  );
  if (existing) return Number(existing.balanceAfter);

  const account = data.creditAccounts.find((candidate) => candidate.userId === userId);
  if (!account || Number(account.balance) < amount) {
    throw new HttpError(402, "You do not have enough generation credits for this request.", {
      code: "INSUFFICIENT_CREDITS",
      requiredCredits: amount,
      availableCredits: Number(account?.balance || 0)
    });
  }
  account.balance = Number(account.balance) - amount;
  account.updatedAt = now.toISOString();
  appendLedger(data, {
    userId,
    jobId,
    eventType: "debit",
    operation,
    amount: -amount,
    balanceAfter: account.balance,
    idempotencyKey,
    createdAt: now.toISOString()
  });

  const month = now.toISOString().slice(0, 7);
  data.usage = Array.isArray(data.usage) ? data.usage : [];
  let usage = data.usage.find((entry) => entry.userId === userId && entry.month === month);
  if (!usage) {
    usage = { userId, month, generations: 0, videoGenerations: 0 };
    data.usage.push(usage);
  }
  if (operation === "silent_video" || operation === "talking_video") {
    usage.videoGenerations += 1;
  } else {
    usage.generations += 1;
  }
  return account.balance;
}

export function refundCreditsInStore(data, userId, {
  cost,
  jobId,
  operation,
  reason = "generation_failed",
  now = new Date()
}) {
  data.creditAccounts = Array.isArray(data.creditAccounts) ? data.creditAccounts : [];
  data.creditLedger = Array.isArray(data.creditLedger) ? data.creditLedger : [];
  const idempotencyKey = `job:${jobId}:refund`;
  const existing = data.creditLedger.find((entry) =>
    entry.userId === userId && entry.idempotencyKey === idempotencyKey
  );
  if (existing) return Number(existing.balanceAfter);
  const debit = data.creditLedger.find((entry) =>
    entry.userId === userId && entry.idempotencyKey === `job:${jobId}:debit`
  );
  if (!debit) return Number(data.creditAccounts.find((entry) => entry.userId === userId)?.balance || 0);

  const amount = Number(cost || Math.abs(Number(debit.amount)));
  let account = data.creditAccounts.find((candidate) => candidate.userId === userId);
  if (!account) {
    account = { userId, balance: 0, updatedAt: now.toISOString() };
    data.creditAccounts.push(account);
  }
  account.balance = Number(account.balance) + amount;
  account.updatedAt = now.toISOString();
  appendLedger(data, {
    userId,
    jobId,
    eventType: "refund",
    operation,
    amount,
    balanceAfter: account.balance,
    idempotencyKey,
    metadata: { reason },
    createdAt: now.toISOString()
  });

  const month = now.toISOString().slice(0, 7);
  const usage = Array.isArray(data.usage)
    ? data.usage.find((entry) => entry.userId === userId && entry.month === month)
    : null;
  if (usage) {
    if (operation === "silent_video" || operation === "talking_video") {
      usage.videoGenerations = Math.max(0, Number(usage.videoGenerations || 0) - 1);
    } else {
      usage.generations = Math.max(0, Number(usage.generations || 0) - 1);
    }
  }
  return account.balance;
}

export function ensureDueCreditGrantsInStore(data, userId, now = new Date()) {
  data.creditAccounts = Array.isArray(data.creditAccounts) ? data.creditAccounts : [];
  data.creditGrants = Array.isArray(data.creditGrants) ? data.creditGrants : [];
  data.creditLedger = Array.isArray(data.creditLedger) ? data.creditLedger : [];
  grantCredits(data, {
    userId,
    grantKey: "starter:v1",
    sourceType: "starter",
    tier: "free",
    amount: planMonthlyCredits.free,
    grantPeriodStart: null,
    now
  });
  // One-time, finite generation allowance for the sole App Review account.
  // Do not create App Store transactions or bypass actual AI cost budgets.
  if (reviewAccessForUser(userId, { now })) {
    grantCredits(data, {
      userId,
      grantKey: "apple-review:complimentary:v1",
      sourceType: "adjustment",
      tier: "pro",
      amount: 120,
      grantPeriodStart: null,
      now
    });
  }
  if (config.nodeEnv !== "production" && config.enableMockGeneration) {
    grantCredits(data, {
      userId,
      grantKey: "development:mock:v1",
      sourceType: "adjustment",
      tier: "pro",
      amount: planMonthlyCredits.pro,
      grantPeriodStart: null,
      now
    });
  }

  for (const transaction of data.appStoreTransactions || []) {
    if (
      transaction.userId !== userId
      || transaction.revokedAt
      || transaction.isUpgraded
      || !productTiers.has(transaction.productId)
    ) continue;
    const purchasedAt = new Date(transaction.purchasedAt || 0);
    const expiresAt = new Date(transaction.expiresAt || 0);
    if (!Number.isFinite(purchasedAt.getTime()) || !Number.isFinite(expiresAt.getTime())) continue;
    const periods = transaction.productId.endsWith(".yearly") ? 12 : 1;
    for (let index = 0; index < periods; index += 1) {
      const periodStart = addUTCMonthsClamped(purchasedAt, index);
      if (periodStart > now || periodStart >= expiresAt) break;
      const tier = productTiers.get(transaction.productId);
      grantCredits(data, {
        userId,
        grantKey: `subscription:${transaction.transactionId}:${index}`,
        sourceType: "subscription",
        tier,
        amount: planMonthlyCredits[tier],
        productId: transaction.productId,
        transactionId: transaction.transactionId,
        grantPeriodStart: periodStart.toISOString(),
        now
      });
    }
  }
}

function grantCredits(data, grant) {
  if (data.creditGrants.some((entry) =>
    entry.userId === grant.userId && entry.grantKey === grant.grantKey
  )) return;
  let account = data.creditAccounts.find((candidate) => candidate.userId === grant.userId);
  if (!account) {
    account = { userId: grant.userId, balance: 0, updatedAt: grant.now.toISOString() };
    data.creditAccounts.push(account);
  }
  const id = crypto.randomUUID();
  account.balance = Number(account.balance) + grant.amount;
  account.updatedAt = grant.now.toISOString();
  data.creditGrants.push({
    id,
    userId: grant.userId,
    grantKey: grant.grantKey,
    sourceType: grant.sourceType,
    tier: grant.tier,
    amount: grant.amount,
    productId: grant.productId || null,
    transactionId: grant.transactionId || null,
    grantPeriodStart: grant.grantPeriodStart,
    createdAt: grant.now.toISOString()
  });
  appendLedger(data, {
    userId: grant.userId,
    grantId: id,
    eventType: "grant",
    operation: grant.sourceType,
    amount: grant.amount,
    balanceAfter: account.balance,
    idempotencyKey: `grant:${grant.grantKey}`,
    metadata: { tier: grant.tier, productId: grant.productId || null },
    createdAt: grant.now.toISOString()
  });
}

function appendLedger(data, entry) {
  data.creditLedger.push({ id: crypto.randomUUID(), metadata: {}, ...entry });
}

function addUTCMonthsClamped(date, months) {
  const result = new Date(date);
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

export function assertCostBudgetInStore(data, userId, estimatedCostUSD, limits = {}) {
  const userLimit = Number(limits.user ?? config.dailyUserBudgetUSD);
  const globalLimit = Number(limits.global ?? config.dailyGlobalBudgetUSD);
  if (userLimit <= 0 && globalLimit <= 0) {
    return;
  }

  const today = new Date().toISOString().slice(0, 10);
  const jobs = (data.jobs || []).filter((job) => String(job.createdAt || "").startsWith(today));
  const reserved = (job) => Number(job.actualCostUSD ?? job.estimatedCostUSD ?? 0);
  const globalSpend = jobs.reduce((total, job) => total + reserved(job), 0);
  const userSpend = jobs
    .filter((job) => job.userId === userId)
    .reduce((total, job) => total + reserved(job), 0);

  if (userLimit > 0 && userSpend + estimatedCostUSD > userLimit) {
    throw new HttpError(429, "Your daily generation safety limit has been reached. Please try again tomorrow.");
  }
  if (globalLimit > 0 && globalSpend + estimatedCostUSD > globalLimit) {
    throw new HttpError(503, "Scene generation is temporarily paused. Please try again later.");
  }
}

async function fetchAndVerifyTransaction(transactionId) {
  let lastStatus = 0;
  for (const candidate of [
    { baseURL: productionURL, environment: Environment.PRODUCTION },
    { baseURL: sandboxURL, environment: Environment.SANDBOX }
  ]) {
    const response = await fetch(`${candidate.baseURL}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${appStoreJWT()}` },
      signal: AbortSignal.timeout(10_000)
    });
    lastStatus = response.status;
    if (!response.ok) {
      continue;
    }
    const body = await response.json();
    const signedTransaction = String(body.signedTransactionInfo || "");
    const transaction = await (await verifierFor(candidate.environment))
      .verifyAndDecodeTransaction(signedTransaction);
    return { transaction, signedTransaction };
  }
  throw new HttpError(403, `The App Store purchase could not be verified (${lastStatus}).`);
}

async function verifyNotificationInEitherEnvironment(signedPayload) {
  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const verifier = await verifierFor(environment);
      const payload = await verifier.verifyAndDecodeNotification(signedPayload);
      return { payload, verifier, environment };
    } catch {
      // A single endpoint receives both environments; try the other verifier.
    }
  }
  throw new HttpError(403, "The App Store notification signature could not be verified.");
}

async function verifierFor(environment) {
  assertVerificationConfigured();
  if (!verifierCache.has(environment)) {
    const roots = await Promise.all(config.appStoreRootCAPaths.map((filePath) => fs.readFile(filePath)));
    const appAppleId = environment === Environment.PRODUCTION ? config.appStoreAppleId : undefined;
    verifierCache.set(environment, new SignedDataVerifier(
      roots,
      config.appStoreEnableOnlineChecks,
      environment,
      config.appStoreBundleId,
      appAppleId
    ));
  }
  return verifierCache.get(environment);
}

function validateTransaction(transaction, expectedTransactionId, userId) {
  const tier = productTiers.get(transaction.productId);
  const accountToken = String(transaction.appAccountToken || "").toLowerCase();
  if (
    !tier
    || !transaction.transactionId
    || (expectedTransactionId && String(transaction.transactionId) !== String(expectedTransactionId))
    || transaction.bundleId !== config.appStoreBundleId
    || accountToken !== String(userId).toLowerCase()
  ) {
    throw new HttpError(403, "This purchase is not valid for the signed-in SceneMe account.");
  }
}

async function persistVerifiedTransaction({
  transaction,
  signedTransaction,
  userId,
  status,
  gracePeriodExpiresAt = null,
  verifiedAt
}) {
  const tier = productTiers.get(transaction.productId);
  if (!tier) {
    throw new HttpError(403, "The App Store product is not recognized.");
  }

  await store.mutate(async (data) => {
    data.appStoreTransactions = Array.isArray(data.appStoreTransactions) ? data.appStoreTransactions : [];
    data.entitlements = Array.isArray(data.entitlements) ? data.entitlements : [];
    const conflicting = data.appStoreTransactions.find((candidate) =>
      candidate.originalTransactionId === transaction.originalTransactionId
      && candidate.userId
      && candidate.userId !== userId
    );
    if (conflicting) {
      throw new HttpError(409, "This App Store subscription is linked to another SceneMe account.");
    }

    const record = {
      transactionId: String(transaction.transactionId),
      originalTransactionId: String(transaction.originalTransactionId || transaction.transactionId),
      userId,
      appAccountToken: transaction.appAccountToken || null,
      productId: transaction.productId,
      environment: String(transaction.environment),
      purchasedAt: millisISO(transaction.purchaseDate),
      expiresAt: millisISO(transaction.expiresDate),
      revokedAt: millisISO(transaction.revocationDate),
      revocationReason: transaction.revocationReason ?? null,
      isUpgraded: Boolean(transaction.isUpgraded),
      signedTransaction,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    const transactionIndex = data.appStoreTransactions.findIndex(
      (candidate) => candidate.transactionId === record.transactionId
    );
    if (transactionIndex >= 0) {
      record.createdAt = data.appStoreTransactions[transactionIndex].createdAt || record.createdAt;
      data.appStoreTransactions[transactionIndex] = record;
    } else {
      data.appStoreTransactions.push(record);
    }

    const entitlement = {
      userId,
      tier,
      productId: transaction.productId,
      originalTransactionId: record.originalTransactionId,
      environment: record.environment,
      status,
      expiresAt: record.expiresAt,
      gracePeriodExpiresAt,
      lastTransactionId: record.transactionId,
      lastVerifiedAt: verifiedAt,
      updatedAt: new Date().toISOString()
    };
    const entitlementIndex = data.entitlements.findIndex((candidate) => candidate.userId === userId);
    const current = entitlementIndex >= 0 ? data.entitlements[entitlementIndex] : null;
    if (!current || Date.parse(verifiedAt) >= Date.parse(current.lastVerifiedAt || 0)) {
      if (entitlementIndex >= 0) {
        data.entitlements[entitlementIndex] = entitlement;
      } else {
        data.entitlements.push(entitlement);
      }
    }
  });
}

async function upsertNotification(notification) {
  await store.mutate(async (data) => {
    data.appStoreNotifications = Array.isArray(data.appStoreNotifications)
      ? data.appStoreNotifications
      : [];
    const index = data.appStoreNotifications.findIndex(
      (candidate) => candidate.notificationUUID === notification.notificationUUID
    );
    if (index >= 0) {
      data.appStoreNotifications[index] = { ...data.appStoreNotifications[index], ...notification };
    } else {
      data.appStoreNotifications.push(notification);
    }
  });
}

function statusForTransaction(transaction) {
  if (transaction.revocationDate) {
    return "revoked";
  }
  if (transaction.isUpgraded || Number(transaction.expiresDate || 0) <= Date.now()) {
    return "expired";
  }
  return "active";
}

function statusForNotification(payload, transaction) {
  switch (Number(payload.data?.status)) {
  case Status.ACTIVE: return statusForTransaction(transaction);
  case Status.EXPIRED: return "expired";
  case Status.BILLING_RETRY: return "billing_retry";
  case Status.BILLING_GRACE_PERIOD: return "grace_period";
  case Status.REVOKED: return transaction.revocationDate ? "refunded" : "revoked";
  default: return statusForTransaction(transaction);
  }
}

function entitlementTier(entitlement) {
  const now = Date.now();
  if (entitlement.status === "active" && Date.parse(entitlement.expiresAt || 0) > now) {
    return entitlement.tier;
  }
  if (
    entitlement.status === "grace_period"
    && Date.parse(entitlement.gracePeriodExpiresAt || entitlement.expiresAt || 0) > now
  ) {
    return entitlement.tier;
  }
  return "free";
}

function millisISO(value) {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric > 0 ? new Date(numeric).toISOString() : null;
}

function appStoreJWT() {
  const now = Math.floor(Date.now() / 1000);
  const header = base64URLEncode(JSON.stringify({ alg: "ES256", kid: config.appStoreKeyId, typ: "JWT" }));
  const payload = base64URLEncode(JSON.stringify({
    iss: config.appStoreIssuerId,
    iat: now,
    exp: now + 5 * 60,
    aud: "appstoreconnect-v1",
    bid: config.appStoreBundleId
  }));
  const input = `${header}.${payload}`;
  const signature = crypto.sign("sha256", Buffer.from(input), {
    key: config.appStorePrivateKey,
    dsaEncoding: "ieee-p1363"
  });
  return `${input}.${base64URLEncode(signature)}`;
}

function assertVerificationConfigured() {
  if (!config.appStoreBundleId || !config.appStoreAppleId || config.appStoreRootCAPaths.length === 0) {
    throw new HttpError(503, "App Store verification is not configured yet.");
  }
}

function assertConfigured() {
  assertVerificationConfigured();
  if (!config.appStoreIssuerId || !config.appStoreKeyId || !config.appStorePrivateKey) {
    throw new HttpError(503, "App Store Server API credentials are incomplete.");
  }
}
