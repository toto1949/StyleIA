import assert from "node:assert/strict";
import { ensureReviewerAccount } from "../src/services/reviewer-account.mjs";

const email = "app-review@example.com";
const password = "ExampleOnlyStrongPassword_2026!";
const users = [{
  id: "d25898c3-c978-493e-8548-129de4e1cd2d",
  email: "original@example.com",
  fullName: "Existing User",
  passwordHash: "",
  passwordSalt: "",
  createdAt: "2026-10-15T00:00:00.000Z"
}];
const mockDatabase = {
  mutate: async (callback) => callback({ users })
};
const base = {
  email: " APP-REVIEW@EXAMPLE.COM ",
  password,
  databaseURL: "postgresql://localhost/sceneme_test",
  database: mockDatabase
};

const disabled = await ensureReviewerAccount({
  email: "",
  password: "",
  databaseURL: "",
  database: mockDatabase
});
assert.equal(disabled.status, "disabled");
assert.equal(users.length, 1);

await assert.rejects(
  ensureReviewerAccount({ ...base, password: "", databaseURL: "" }),
  /Set both/
);
await assert.rejects(
  ensureReviewerAccount({ ...base, databaseURL: "" }),
  /persistent PostgreSQL/
);
await assert.rejects(
  ensureReviewerAccount({ ...base, password: "short" }),
  /at least 16/
);

const first = await ensureReviewerAccount(base);
assert.equal(first.status, "created");
assert.equal(users.length, 2);
assert.equal(users[1].email, email);
assert.equal(users[1].fullName, "Apple App Review");
assert.notEqual(users[1].passwordHash, password);
assert.ok(users[1].passwordSalt);

const second = await ensureReviewerAccount(base);
assert.equal(second.status, "existing");
assert.equal(users.length, 2);
await assert.rejects(
  ensureReviewerAccount({ ...base, password: "AnotherValidPassword_2026!" }),
  /refusing to reset/
);
assert.equal(users.length, 2);
assert.equal(users[0].email, "original@example.com");

console.log("Reviewer provisioning: validated, idempotent, secure hashing, safe mismatch handling.");
