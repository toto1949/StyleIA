import assert from "node:assert/strict";
import crypto from "node:crypto";

process.env.OPENAI_API_KEY ||= "test-openai-key";
process.env.STYLEAI_ENABLE_MOCK_GENERATION = "false";

const {
  assertSafeUserImage,
  assertSafeUserText,
  setContentSafetyFetchForTesting
} = await import("../src/services/content-safety-service.mjs");
const { config } = await import("../src/config.mjs");
const { store } = await import("../src/services/store-instance.mjs");
const { ensureUploadSafeForGeneration } = await import("../src/routes/upload.mjs");
const { objectStorage } = await import("../src/services/object-storage-service.mjs");

const keyUserId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const keyUploadId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ingressKey = objectStorage.uploadKey(keyUserId, keyUploadId);
const finalizedKey = objectStorage.finalizedUploadKey(ingressKey);
assert.equal(ingressKey, `private/${keyUserId}/uploads/${keyUploadId}/incoming.jpg`);
assert.equal(finalizedKey, `private/${keyUserId}/uploads/${keyUploadId}/validated.jpg`);
assert.notEqual(ingressKey, finalizedKey);

const requests = [];
let nextPayload = {
  model: "omni-moderation-latest",
  results: [{ flagged: false, categories: { sexual: false } }]
};
let nextStatus = 200;

setContentSafetyFetchForTesting(async (url, options) => {
  requests.push({ url, options, body: JSON.parse(options.body) });
  return new Response(JSON.stringify(nextPayload), {
    status: nextStatus,
    headers: { "content-type": "application/json" }
  });
});

const allowed = await assertSafeUserImage(
  "https://private.example/photo.jpg?signature=secret",
  "11111111-1111-4111-8111-111111111111"
);
assert.equal(allowed.status, "allowed");
assert.equal(requests.length, 1);
assert.equal(requests[0].url, "https://api.openai.com/v1/moderations");
assert.equal(requests[0].body.model, "omni-moderation-latest");
assert.deepEqual(requests[0].body.input, [{
  type: "image_url",
  image_url: { url: "https://private.example/photo.jpg?signature=secret" }
}]);

if (config.databaseURL) {
  const testUserId = crypto.randomUUID();
  const testUploadId = crypto.randomUUID();
  const testIngressKey = objectStorage.uploadKey(testUserId, testUploadId);
  const testStorageKey = objectStorage.finalizedUploadKey(testIngressKey);
  await store.init();
  try {
    await store.mutate((data) => {
      data.users.push({
        id: testUserId,
        email: `content-safety-${testUserId}@example.invalid`,
        fullName: "Content Safety Test",
        createdAt: new Date().toISOString()
      });
      data.uploads.push({
        id: testUploadId,
        userId: testUserId,
        s3Key: testStorageKey,
        clientS3Key: testIngressKey,
        status: "uploaded",
        size: 1_024,
        contentType: "image/jpeg",
        createdAt: new Date().toISOString()
      });
    });

    const initial = (await store.snapshot()).uploads.find((upload) => upload.id === testUploadId);
    assert.equal(initial.clientS3Key, testIngressKey);
    const persisted = await ensureUploadSafeForGeneration(
      testUserId,
      initial,
      "https://private.example/cached.jpg?signature=secret"
    );
    assert.equal(persisted.contentSafetyStatus, "allowed");
    const requestCountAfterModeration = requests.length;
    await ensureUploadSafeForGeneration(
      testUserId,
      (await store.snapshot()).uploads.find((upload) => upload.id === testUploadId),
      "https://private.example/cached.jpg?signature=another-secret"
    );
    assert.equal(requests.length, requestCountAfterModeration, "allowed upload should not be moderated twice");
  } finally {
    await store.mutate((data) => {
      data.uploads = data.uploads.filter((upload) => upload.id !== testUploadId);
      data.users = data.users.filter((user) => user.id !== testUserId);
    }).catch(() => {});
    await store.close?.();
  }
}

nextPayload = {
  model: "omni-moderation-latest",
  results: [{ flagged: true, categories: { sexual: true } }]
};
const originalWarn = console.warn;
console.warn = () => {};
await assert.rejects(
  () => assertSafeUserImage(
    "https://private.example/blocked.jpg?signature=secret",
    "22222222-2222-4222-8222-222222222222"
  ),
  (error) => error?.statusCode === 400 && error?.code === "IMAGE_SAFETY_BLOCKED"
);
console.warn = originalWarn;

nextStatus = 500;
nextPayload = { error: { message: "provider detail must not escape" } };
await assert.rejects(
  () => assertSafeUserImage(
    "https://private.example/unavailable.jpg?signature=secret",
    "33333333-3333-4333-8333-333333333333"
  ),
  (error) => error?.statusCode === 503
    && error?.code === "CONTENT_SAFETY_UNAVAILABLE"
    && !error.message.includes("provider detail")
);

nextStatus = 200;
nextPayload = {
  model: "omni-moderation-latest",
  results: [{ flagged: false, categories: {} }]
};
await assertSafeUserText(
  ["A quiet cinematic portrait in a rainy city."],
  "44444444-4444-4444-8444-444444444444"
);
assert.equal(requests.at(-1).body.input, "A quiet cinematic portrait in a rainy city.");

setContentSafetyFetchForTesting(null);
console.log("Content-safety text/image contract OK");
