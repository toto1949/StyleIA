/**
 * Complimentary, temporary access for the *one* Apple App Review account.
 *
 * The account ID must be configured server-side, not supplied in a client
 * header, query parameter, JWT claim, or email address. This is a feature
 * preview, not an App Store purchase or a fabricated StoreKit transaction.
 * Remove either Render variable to revoke access immediately on restart.
 */
export function reviewAccessForUser(userId, {
  reviewerId = process.env.SCENEME_REVIEWER_FULL_ACCESS_USER_ID || "",
  expiresAt = process.env.SCENEME_REVIEWER_FULL_ACCESS_UNTIL || "",
  now = new Date()
} = {}) {
  const currentTime = new Date(now).getTime();
  const expiry = Date.parse(expiresAt);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(reviewerId)
    || String(userId || "").toLowerCase() !== reviewerId.toLowerCase()
    || !Number.isFinite(expiry)
    || !Number.isFinite(currentTime)
    || currentTime >= expiry
  ) return null;
  return {
    tier: "pro",
    status: "active",
    expiresAt: new Date(expiry).toISOString(),
    gracePeriodExpiresAt: null,
    productId: null,
    environment: "complimentary_review",
    lastVerifiedAt: null,
    isReviewAccess: true
  };
}
