import assert from "node:assert/strict";

process.env.FAL_KEY = "test-fal-key";
process.env.STYLEAI_PROVIDER_TIMEOUT_MS = "40";
process.env.STYLEAI_ENABLE_MOCK_GENERATION = "false";

const {
  cancelFalRequest,
  generateScene,
  generateSceneVideo,
  isFalRequestPendingError,
  setFalClientForTesting
} = await import("../src/services/fal-service.mjs");

const calls = [];
let submitted = [];
let results = new Map();
let statusBehavior = async (_model, options) => {
  options.onQueueUpdate?.({ status: "IN_PROGRESS", logs: [] });
  return { status: "COMPLETED", logs: [] };
};

const fakeFal = {
  config: () => {},
  storage: {
    upload: async () => {
      throw new Error("unexpected storage upload");
    }
  },
  queue: {}
};
setFalClientForTesting(fakeFal);

fakeFal.queue.submit = async (model, options) => {
  calls.push({ operation: "submit", model, input: options.input });
  const requestId = submitted.shift();
  assert.ok(requestId, "unexpected fal queue submission");
  return { request_id: requestId };
};
fakeFal.queue.subscribeToStatus = async (model, options) => {
  calls.push({ operation: "status", model, requestId: options.requestId });
  return statusBehavior(model, options);
};
fakeFal.queue.result = async (model, options) => {
  calls.push({ operation: "result", model, requestId: options.requestId });
  assert.ok(results.has(options.requestId), `missing fake result for ${options.requestId}`);
  return results.get(options.requestId);
};
fakeFal.queue.cancel = async (model, options) => {
  calls.push({ operation: "cancel", model, requestId: options.requestId });
};

submitted = ["scene-request-1"];
results = new Map([
  ["scene-request-1", { data: { images: [{ url: "https://fal.media/scene.jpg" }] } }]
]);
const sceneStates = [];
const sceneURL = await generateScene({
  originalPhotoURL: "https://private.example/input.jpg",
  prompt: "A safe cinematic portrait",
  seed: 42,
  jobId: "11111111-1111-4111-8111-111111111111",
  onProviderState: async (state) => sceneStates.push(state)
});
assert.equal(sceneURL, "https://fal.media/scene.jpg");
assert.equal(sceneStates.length, 1);
assert.equal(sceneStates[0].requestId, "scene-request-1");
assert.equal(sceneStates[0].phase, "scene");
const sceneSubmit = calls.find((call) => call.operation === "submit");
assert.equal(sceneSubmit.input.num_inference_steps, undefined);
assert.equal(sceneSubmit.input.safety_tolerance, "2");

submitted = ["premium-scene-request"];
results = new Map([
  ["premium-scene-request", { data: { images: [{ url: "https://fal.media/premium-scene.jpg" }] } }]
]);
await generateScene({
  originalPhotoURL: "https://private.example/input.jpg",
  prompt: "A premium cinematic portrait",
  imageQuality: "premium",
  jobId: "88888888-8888-4888-8888-888888888888",
  onProviderState: async () => {}
});
const premiumSubmit = calls.find((call) =>
  call.operation === "submit" && call.input?.prompt === "A premium cinematic portrait"
);
assert.equal(premiumSubmit.model, "fal-ai/flux-pro/kontext/max");

const submitsBeforeResume = calls.filter((call) => call.operation === "submit").length;
results.set("scene-request-resume", { data: { images: [{ url: "https://fal.media/resumed.jpg" }] } });
const resumedURL = await generateScene({
  originalPhotoURL: "https://private.example/input.jpg",
  prompt: "A safe cinematic portrait",
  jobId: "22222222-2222-4222-8222-222222222222",
  resumeProvider: {
    requestId: "scene-request-resume",
    model: "fal-ai/test-image",
    phase: "scene"
  }
});
assert.equal(resumedURL, "https://fal.media/resumed.jpg");
assert.equal(calls.filter((call) => call.operation === "submit").length, submitsBeforeResume);

submitted = ["video-request-1", "tts-request-1", "lipsync-request-1"];
results = new Map([
  ["video-request-1", { data: { video: { url: "https://fal.media/base.mp4" } } }],
  ["tts-request-1", { data: { audio: { url: "https://fal.media/speech.mp3" } } }],
  ["lipsync-request-1", { data: { video: { url: "https://fal.media/talking.mp4" } } }]
]);
const videoStates = [];
const videoURL = await generateSceneVideo({
  imageURL: "https://private.example/result.jpg",
  prompt: "Subtle camera motion",
  jobId: "33333333-3333-4333-8333-333333333333",
  spokenLine: "Hello from SceneMe.",
  motionStyle: "talking",
  onProviderState: async (state) => videoStates.push(state)
});
assert.equal(videoURL, "https://fal.media/talking.mp4");
assert.deepEqual(
  videoStates.filter((state) => state.phase).map((state) => state.phase),
  ["video", "tts", "lipsync"]
);
assert.ok(videoStates.some((state) => state.intermediateVideoURL === "https://fal.media/base.mp4"));
assert.ok(videoStates.some((state) => state.intermediateAudioURL === "https://fal.media/speech.mp3"));

submitted = ["lipsync-after-resume"];
results = new Map([
  ["tts-resume", { data: { audio: { url: "https://fal.media/resumed-speech.mp3" } } }],
  ["lipsync-after-resume", { data: { video: { url: "https://fal.media/resumed-talking.mp4" } } }]
]);
const resumedVideoURL = await generateSceneVideo({
  imageURL: "https://private.example/result.jpg",
  prompt: "Subtle camera motion",
  jobId: "44444444-4444-4444-8444-444444444444",
  spokenLine: "Resume this clip.",
  motionStyle: "talking",
  resumeProvider: {
    requestId: "tts-resume",
    model: "fal-ai/test-tts",
    phase: "tts",
    intermediateVideoURL: "https://fal.media/base-resume.mp4"
  },
  onProviderState: async () => {}
});
assert.equal(resumedVideoURL, "https://fal.media/resumed-talking.mp4");

submitted = ["long-video-prompt"];
results = new Map([
  ["long-video-prompt", { data: { video: { url: "https://fal.media/bounded.mp4" } } }]
]);
const longPrompt = "cinematic 😀 ".repeat(400);
await generateSceneVideo({
  imageURL: "https://private.example/result.jpg",
  prompt: longPrompt,
  jobId: "77777777-7777-4777-8777-777777777777",
  motionStyle: "cinematic",
  onProviderState: async () => {}
});
const longPromptSubmit = calls.find((call) =>
  call.operation === "submit" && Buffer.byteLength(String(call.input?.prompt || ""), "utf8") > 1_000
);
assert.ok(longPromptSubmit);
assert.ok(Buffer.byteLength(longPromptSubmit.input.prompt, "utf8") <= 2_048);

await cancelFalRequest("fal-ai/test-image", "cancel-me");
assert.ok(calls.some((call) => call.operation === "cancel" && call.requestId === "cancel-me"));

submitted = ["unsafe-request"];
results = new Map([
  ["unsafe-request", {
    data: {
      images: [{ url: "https://fal.media/unsafe.jpg" }],
      has_nsfw_concepts: [true]
    }
  }]
]);
await assert.rejects(
  generateScene({
    originalPhotoURL: "https://private.example/input.jpg",
    prompt: "A prohibited result fixture",
    jobId: "55555555-5555-4555-8555-555555555555",
    onProviderState: async () => {}
  }),
  (error) => error?.name === "FalSafetyError"
);

submitted = ["slow-request"];
results = new Map();
statusBehavior = async (_model, options) => new Promise((resolve, reject) => {
  options.abortSignal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
});
await assert.rejects(
  generateScene({
    originalPhotoURL: "https://private.example/input.jpg",
    prompt: "A safe cinematic portrait",
    jobId: "66666666-6666-4666-8666-666666666666",
    onProviderState: async () => {}
  }),
  (error) => isFalRequestPendingError(error)
    && error.requestId === "slow-request"
    && error.phase === "scene"
);

console.log("fal durable queue contract OK");
