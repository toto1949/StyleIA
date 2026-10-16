import { reviewAccessForUser } from "../src/services/reviewer-access.mjs";
import {
  appStoreTierForRequest,
  assertCostBudgetInStore,
  consumeCreditsInStore,
  creditStatusInStore,
  generationCreditCosts,
  requireTier
} from "../src/services/app-store-service.mjs";

function assert(condition, label) {
  if (!condition) throw new Error(label);
}

const id = "0f80a6e8-a81a-4b3f-815e-a928c0973659";
const otherId = "d3281a5f-50e6-47e4-9c8d-6b4f5401cdda";
const previousId = process.env.SCENEME_REVIEWER_FULL_ACCESS_USER_ID;
const previousUntil = process.env.SCENEME_REVIEWER_FULL_ACCESS_UNTIL;
try {
  process.env.SCENEME_REVIEWER_FULL_ACCESS_USER_ID = id;
  process.env.SCENEME_REVIEWER_FULL_ACCESS_UNTIL = "2035-04-01T00:00:00.000Z";
  const status = reviewAccessForUser(id, { now: new Date("2035-03-01T00:00:00Z") });
  assert(status?.tier === "pro" && status.status === "active" && status.isReviewAccess, "Reviewer has complimentary Pro access.");
  assert(status.productId === null && status.environment === "complimentary_review", "No counterfeit StoreKit purchase data.");
  assert(!reviewAccessForUser(otherId, { now: new Date("2035-03-01T00:00:00Z") }), "Unrelated user must not get Pro.");
  assert(!reviewAccessForUser(id, { now: new Date("2035-04-01T00:00:00Z") }), "Access expires at cutoff.");

  process.env.SCENEME_REVIEWER_FULL_ACCESS_UNTIL = "2045-04-01T00:00:00Z";
  assert(await appStoreTierForRequest({ headers: {} }, id) === "pro", "Authenticated reviewer request gets Pro tier.");
  requireTier(await appStoreTierForRequest({ headers: {} }, id), "pro", "Video Director");
  assert(!reviewAccessForUser("not-a-uuid"), "Invalid client user must not get access.");
  const data = {
    creditAccounts: [],
    creditGrants: [],
    creditLedger: [],
    appStoreTransactions: [],
    jobs: []
  };
  assert(creditStatusInStore(data, id).balance === 123, "Reviewer receives finite test credits plus starter credits.");
  assert(creditStatusInStore(data, id).balance === 123, "Reviewer grant is idempotent.");
  assert(data.creditGrants.filter((g) => g.userId === id).length === 2, "Only starter and reviewer grants.");
  assert(creditStatusInStore(data, otherId).balance === 3, "Ordinary account retains only starter credits.");
  consumeCreditsInStore(data, id, {
    cost: generationCreditCosts.talkingVideo,
    jobId: "review-talking-video",
    operation: "talking_video"
  });
  assert(creditStatusInStore(data, id).balance === 100, "Real generation credit debits still apply.");
  // Even the reviewer remains subject to the provider spending safety budget.
  data.jobs.push({ userId: id, createdAt: new Date().toISOString(), estimatedCostUSD: 1.99 });
  let limited = false;
  try {
    assertCostBudgetInStore(data, id, 0.35, { user: 2, global: 5 });
  } catch (error) { limited = error.statusCode === 429; }
  assert(limited, "Reviewer may not bypass daily AI spending cap.");

  delete process.env.SCENEME_REVIEWER_FULL_ACCESS_USER_ID;
  assert(!reviewAccessForUser(id), "Removing config revokes demo access.");
  console.log("Reviewer-only Pro access, finite credits, spending cap, expiration and isolation passed.");
} finally {
  if (previousId === undefined) delete process.env.SCENEME_REVIEWER_FULL_ACCESS_USER_ID;
  else process.env.SCENEME_REVIEWER_FULL_ACCESS_USER_ID = previousId;
  if (previousUntil === undefined) delete process.env.SCENEME_REVIEWER_FULL_ACCESS_UNTIL;
  else process.env.SCENEME_REVIEWER_FULL_ACCESS_UNTIL = previousUntil;
}
