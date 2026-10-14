import {
  assertCostBudgetInStore,
  consumeCreditsInStore,
  creditStatusInStore,
  generationCreditCosts,
  refundCreditsInStore,
  requireTier
} from "../src/services/app-store-service.mjs";

function expectHttpError(action, statusCode) {
  try { action(); } catch (error) {
    if (error.statusCode === statusCode) return error;
    throw error;
  }
  throw new Error(`Expected HTTP ${statusCode}.`);
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, received ${actual}.`);
}

requireTier("creator", "creator", "Custom scenes");
requireTier("pro", "creator", "Custom scenes");
expectHttpError(() => requireTier("free", "creator", "Custom scenes"), 403);
expectHttpError(() => requireTier("creator", "pro", "Video Director"), 403);

const data = { usage: [], creditAccounts: [], creditGrants: [], creditLedger: [], appStoreTransactions: [] };
assertEqual(creditStatusInStore(data, "free-user").balance, 3, "one-time starter grant");
for (let count = 0; count < 3; count += 1) {
  consumeCreditsInStore(data, "free-user", {
    cost: generationCreditCosts.standardImage,
    jobId: `free-${count}`,
    operation: "standard_image"
  });
}
expectHttpError(() => consumeCreditsInStore(data, "free-user", {
  cost: 1, jobId: "free-over-limit", operation: "standard_image"
}), 402);

refundCreditsInStore(data, "free-user", {
  cost: 1, jobId: "free-0", operation: "standard_image", reason: "test_failure"
});
assertEqual(creditStatusInStore(data, "free-user").balance, 1, "failed-job refund");
refundCreditsInStore(data, "free-user", {
  cost: 1, jobId: "free-0", operation: "standard_image", reason: "duplicate_callback"
});
assertEqual(creditStatusInStore(data, "free-user").balance, 1, "idempotent refund");

data.appStoreTransactions.push({
  transactionId: "annual-pro-1",
  originalTransactionId: "annual-pro-1",
  userId: "annual-user",
  productId: "com.sceneme.pro.yearly",
  purchasedAt: "2026-01-31T12:00:00.000Z",
  expiresAt: "2027-01-31T12:00:00.000Z",
  revokedAt: null,
  isUpgraded: false
});
assertEqual(
  creditStatusInStore(data, "annual-user", new Date("2026-01-31T12:01:00.000Z")).balance,
  103,
  "annual subscriber first monthly grant"
);
assertEqual(
  creditStatusInStore(data, "annual-user", new Date("2026-03-31T12:01:00.000Z")).balance,
  303,
  "annual subscriber monthly anniversary grants"
);
assertEqual(
  creditStatusInStore(data, "annual-user", new Date("2027-03-01T00:00:00.000Z")).balance,
  1203,
  "annual grants cap at twelve and do not expire"
);

const before = creditStatusInStore(data, "annual-user").balance;
consumeCreditsInStore(data, "annual-user", {
  cost: generationCreditCosts.talkingVideo, jobId: "talking-video-1", operation: "talking_video"
});
assertEqual(creditStatusInStore(data, "annual-user").balance, before - 23, "talking video debit");
consumeCreditsInStore(data, "annual-user", {
  cost: generationCreditCosts.talkingVideo, jobId: "talking-video-1", operation: "talking_video"
});
assertEqual(creditStatusInStore(data, "annual-user").balance, before - 23, "idempotent debit");

const budgetData = {
  jobs: [{ userId: "budget-user", createdAt: new Date().toISOString(), estimatedCostUSD: 0.4 }]
};
assertCostBudgetInStore(budgetData, "budget-user", 0.1, { user: 0.5, global: 5 });
expectHttpError(() => assertCostBudgetInStore(
  budgetData, "budget-user", 0.11, { user: 0.5, global: 5 }
), 429);
expectHttpError(() => assertCostBudgetInStore(
  budgetData, "other-user", 0.2, { user: 5, global: 0.5 }
), 503);

console.log("Subscription feature gates, durable credit grants, debits, refunds, and budgets passed.");
