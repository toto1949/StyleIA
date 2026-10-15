import crypto from "node:crypto";
import { assertEmailPassword, hashPassword, verifyPassword } from "../auth.mjs";
import { config } from "../config.mjs";
import { store } from "./store-instance.mjs";

/**
 * Optional, one-time App Review account provisioning.
 *
 * Supply SCENEME_REVIEWER_EMAIL and SCENEME_REVIEWER_PASSWORD as Render
 * secret environment variables for the first start on persistent Postgres.
 * Remove both variables after a successful sign-in test. The account
 * remains in the database, and this function never changes an existing
 * account's password or subscription entitlements.
 */
export async function ensureReviewerAccount({
  email = process.env.SCENEME_REVIEWER_EMAIL || "",
  password = process.env.SCENEME_REVIEWER_PASSWORD || "",
  databaseURL = config.databaseURL,
  database = store
} = {}) {
  if (!email && !password) return { status: "disabled" };
  if (!email || !password) {
    throw new Error("Set both SCENEME_REVIEWER_EMAIL and SCENEME_REVIEWER_PASSWORD.");
  }
  if (!databaseURL) {
    throw new Error("Reviewer provisioning requires persistent PostgreSQL storage.");
  }
  if (password.length < 16) {
    throw new Error("The App Review password must be at least 16 characters.");
  }

  const validated = assertEmailPassword(email, password);
  const normalizedEmail = validated.email;

  const result = await database.mutate(async (data) => {
    const existing = data.users.find((user) => user.email === normalizedEmail);
    if (existing) {
      if (!existing.passwordHash || !existing.passwordSalt) {
        throw new Error("Reviewer email belongs to an account without password sign-in.");
      }
      if (!(await verifyPassword(password, existing.passwordSalt, existing.passwordHash))) {
        throw new Error("Reviewer account already exists with different credentials; refusing to reset it.");
      }
      return { status: "existing" };
    }

    const passwordRecord = await hashPassword(password);
    data.users.push({
      id: crypto.randomUUID(),
      email: normalizedEmail,
      fullName: "Apple App Review",
      passwordHash: passwordRecord.hash,
      passwordSalt: passwordRecord.salt,
      appleSub: "",
      googleSub: "",
      createdAt: new Date().toISOString()
    });
    return { status: "created" };
  });

  // Never print credentials, session tokens, or password hashes in service logs.
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event: "reviewer_account_provisioning",
    status: result.status
  }));
  return result;
}
