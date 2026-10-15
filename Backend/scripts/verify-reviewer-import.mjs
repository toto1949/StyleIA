import assert from "node:assert/strict";
import { reviewerImportCarryover } from "./reviewer-import-guard.mjs";

const user = {
  id: "851d1d7e-9e9c-4352-a23f-389a74c21c67",
  email: "appreview@sceneme.app",
  passwordHash: "not-a-plaintext-password",
  passwordSalt: "a-unique-salt"
};
const empty = { users: [], uploads: [], jobs: [], usage: [] };
const incoming = { users: [{ id: "2119c8b1-ad5c-49a2-88fb-5533cc921297", email: "legacy@example.com" }] };

assert.equal(reviewerImportCarryover(empty, incoming, ""), null);
assert.equal(reviewerImportCarryover({ ...empty, users: [user] }, incoming, "APPREVIEW@SCENEME.APP").id, user.id);
assert.throws(() => reviewerImportCarryover({ ...empty, users: [user] }, incoming, ""), /non-empty/);
assert.throws(() => reviewerImportCarryover({ ...empty, users: [user, { ...user, id: "other" }] }, incoming, user.email), /non-empty/);
assert.throws(() => reviewerImportCarryover({ ...empty, users: [user], jobs: [{}] }, incoming, user.email), /non-empty/);
assert.throws(() => reviewerImportCarryover({ ...empty, users: [user] }, { users: [user] }, user.email), /conflicts/);
assert.throws(() => reviewerImportCarryover({ ...empty, users: [user] }, { users: [{ id: "other", email: user.email }] }, user.email), /conflicts/);
console.log("Legacy import carryover guard passed.");
