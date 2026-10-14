import crypto from "node:crypto";
import { store } from "../src/services/store-instance.mjs";

await store.init();

try {
  const scope = `automated-${crypto.randomUUID()}`;
  const subjectHash = crypto.createHash("sha256").update("rate-limit-test-subject").digest("hex");
  const attempts = await Promise.all(Array.from({ length: 12 }, () =>
    store.consumeRateLimit(scope, subjectHash, 5, 10 * 60_000)
  ));

  const allowed = attempts.filter((attempt) => attempt.allowed).length;
  const denied = attempts.filter((attempt) => !attempt.allowed).length;
  if (allowed !== 5 || denied !== 7) {
    throw new Error(`Rate limit was not atomic: expected 5 allowed/7 denied, got ${allowed}/${denied}.`);
  }
  if (attempts.some((attempt) => !Number.isFinite(attempt.resetAt) || attempt.remaining < 0)) {
    throw new Error("Rate limit metadata is invalid.");
  }

  console.log(`Durable rate-limit concurrency passed (${allowed} allowed, ${denied} denied).`);
} finally {
  await store.close?.();
}
