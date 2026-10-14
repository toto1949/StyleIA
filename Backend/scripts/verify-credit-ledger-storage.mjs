import crypto from "node:crypto";
import { store } from "../src/services/store-instance.mjs";
import {
  consumeCreditsInStore,
  creditStatusInStore,
  refundCreditsInStore
} from "../src/services/app-store-service.mjs";

await store.init();
const userId = crypto.randomUUID();
const jobId = crypto.randomUUID();
const rowId = crypto.randomUUID();

try {
  await store.mutate((data) => {
    data.users.push({
      id: userId,
      email: `credit-ledger-${userId}@example.invalid`,
      fullName: "Credit Ledger Test",
      createdAt: new Date().toISOString()
    });
    const status = creditStatusInStore(data, userId);
    if (status.balance !== 3) throw new Error("Starter grant was not created.");
    consumeCreditsInStore(data, userId, {
      cost: 2,
      jobId,
      operation: "premium_image"
    });
    data.jobs.push({
      id: rowId,
      jobId,
      userId,
      type: "scene",
      status: "failed",
      progress: 100,
      creditCost: 2,
      creditOperation: "premium_image",
      creditRefunded: true,
      estimatedCostUSD: 0.08,
      createdAt: new Date().toISOString()
    });
    refundCreditsInStore(data, userId, {
      cost: 2,
      jobId,
      operation: "premium_image",
      reason: "fixture_failure"
    });
  });

  const persisted = await store.snapshot();
  const account = persisted.creditAccounts.find((entry) => entry.userId === userId);
  const grants = persisted.creditGrants.filter((entry) => entry.userId === userId);
  const ledger = persisted.creditLedger.filter((entry) => entry.userId === userId);
  const job = persisted.jobs.find((entry) => entry.jobId === jobId);
  if (account?.balance !== 3 || grants.length !== 1 || ledger.length !== 3) {
    throw new Error("Credit account/grant/ledger did not round-trip.");
  }
  if (!job || job.creditCost !== 2 || !job.creditRefunded) {
    throw new Error("Per-job credit fields did not round-trip.");
  }
  console.log("Durable credit account, grant, debit, refund and job fields round-trip passed.");
} finally {
  await store.mutate((data) => {
    data.jobs = data.jobs.filter((entry) => entry.id !== rowId);
    data.creditLedger = data.creditLedger.filter((entry) => entry.userId !== userId);
    data.creditGrants = data.creditGrants.filter((entry) => entry.userId !== userId);
    data.creditAccounts = data.creditAccounts.filter((entry) => entry.userId !== userId);
    data.users = data.users.filter((entry) => entry.id !== userId);
  }).catch(() => {});
  await store.close?.();
}
