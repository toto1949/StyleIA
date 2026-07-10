// Mock-mode smoke test: gender prompt, result reuse, custom scene, video job.
const base = process.env.SMOKE_BASE_URL || "http://localhost:8099";

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  process.exit(1);
};

const api = async (path, options = {}, token = "") => {
  const response = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers
    }
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    fail(`${path} -> ${response.status} ${JSON.stringify(body)}`);
  }
  return body;
};

const waitForJob = async (jobId, token) => {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const job = await api(`/v1/scene-jobs/${jobId}`, {}, token);
    if (job.status === "completed") {
      return job;
    }
    if (job.status === "failed") {
      fail(`job ${jobId} failed: ${job.error}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  fail(`job ${jobId} timed out`);
};

// 1. Auth
const auth = await api("/v1/auth/email", {
  method: "POST",
  body: JSON.stringify({ email: `smoke-${Date.now()}@test.dev`, password: "Password123!" })
});
const token = auth.accessToken;
console.log("auth ok");

// 2. Upload a tiny jpeg
const presign = await api("/v1/upload/presign", { method: "POST", body: "{}" }, token);
const jpegBytes = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q==",
  "base64"
);
const uploadResponse = await fetch(presign.uploadURL, {
  method: "PUT",
  headers: { "Content-Type": "image/jpeg" },
  body: jpegBytes
});
if (!uploadResponse.ok) {
  fail(`upload -> ${uploadResponse.status}`);
}
console.log("upload ok");

// 3. Gendered scene job
const job1 = await api("/v1/scene-jobs", {
  method: "POST",
  body: JSON.stringify({
    s3Key: presign.s3Key,
    sceneId: "times-square",
    subjectGender: "female",
    timeOfDay: "night",
    weather: "sunny",
    pose: "walking"
  })
}, token);

if (!job1.prompt.includes("adult woman")) fail("prompt missing female subject");
if (!job1.prompt.includes("heeled boots")) fail("prompt missing female outfit");
if (!job1.prompt.includes("keep the person's face 100% identical")) fail("prompt missing identity lock");
if (!job1.prompt.includes("billboards tower behind")) fail("prompt missing scene signature");
if (job1.kind !== "image") fail("expected image kind");
const done1 = await waitForJob(job1.jobId, token);
if (!done1.imageURL) fail("job1 missing imageURL");
console.log("gendered scene job ok");

// 4. Identical request again -> should reuse result (completes near-instantly)
const startedAt = Date.now();
const job2 = await api("/v1/scene-jobs", {
  method: "POST",
  body: JSON.stringify({
    s3Key: presign.s3Key,
    sceneId: "times-square",
    subjectGender: "female",
    timeOfDay: "night",
    weather: "sunny",
    pose: "walking"
  })
}, token);
const done2 = await waitForJob(job2.jobId, token);
const reuseMs = Date.now() - startedAt;
if (done2.imageURL !== done1.imageURL) fail("reused job should return the same imageURL");
if (reuseMs > 2000) fail(`reuse took ${reuseMs}ms, expected cache hit (<2000ms)`);
console.log(`result reuse ok (${reuseMs}ms, no fal call)`);

// 5. Custom scene job
const job3 = await api("/v1/scene-jobs", {
  method: "POST",
  body: JSON.stringify({
    s3Key: presign.s3Key,
    sceneId: "custom",
    customScene: {
      name: "Marrakech Rooftop",
      basePrompt: "standing on a traditional riad rooftop in Marrakech with mosaic tiles and the Atlas mountains behind",
      outfit: "flowing linen outfit in warm desert tones"
    },
    subjectGender: "male",
    timeOfDay: "golden_hour",
    weather: "sunny",
    pose: "casual"
  })
}, token);
if (job3.sceneId !== "custom") fail("custom scene id mismatch");
if (!job3.prompt.includes("Marrakech")) fail("custom prompt missing scene text");
if (!job3.prompt.includes("adult man")) fail("custom prompt missing male subject");
const done3 = await waitForJob(job3.jobId, token);
if (!done3.imageURL) fail("custom job missing imageURL");
console.log("custom scene job ok");

// 6. Bad custom scene rejected
const badResponse = await fetch(`${base}/v1/scene-jobs`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  body: JSON.stringify({ s3Key: presign.s3Key, sceneId: "custom", customScene: { basePrompt: "" } })
});
if (badResponse.status !== 400) fail(`empty custom scene should be 400, got ${badResponse.status}`);
console.log("custom scene validation ok");

// 7. Video job from completed scene
const video = await api(`/v1/scene-jobs/${done1.jobId}/video`, { method: "POST", body: "{}" }, token);
if (video.kind !== "video") fail("expected video kind");
const videoDone = await waitForJob(video.jobId, token);
if (!videoDone.videoURL) fail("video job missing videoURL");
console.log(`video job ok -> ${videoDone.videoURL}`);

// 8. Second animate tap reuses the cached video (no new generation)
const videoAgain = await api(`/v1/scene-jobs/${done1.jobId}/video`, { method: "POST", body: "{}" }, token);
if (videoAgain.status !== "completed" || videoAgain.videoURL !== videoDone.videoURL) {
  fail("second animate should reuse cached video instantly");
}
console.log("video reuse ok");

// 9. History still lists image jobs with videoURL attached
const history = await api("/v1/history?page=1&limit=10", {}, token);
if (history.items.length < 3) fail(`expected >=3 history items, got ${history.items.length}`);
const animated = history.items.find((item) => item.jobId === done1.jobId);
if (!animated?.videoURL) fail("history item missing persisted videoURL");
console.log("history ok");

console.log("ALL SMOKE TESTS PASSED");
