// Mock-mode smoke test: gender prompt, result reuse, custom scene, video job.
import crypto from "node:crypto";

const base = process.env.SMOKE_BASE_URL || "http://localhost:8099";

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  process.exit(1);
};

const api = async (path, options = {}, token = "") => {
  const needsIdempotency = options.method === "POST" && path.includes("/scene-jobs");
  const response = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(needsIdempotency ? { "Idempotency-Key": crypto.randomUUID() } : {}),
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
if (!auth.refreshToken || auth.accessTokenExpiresIn !== 900) {
  fail("auth response missing rotating-session credentials");
}
const refreshedAuth = await api("/v1/auth/refresh", {
  method: "POST",
  body: JSON.stringify({ refreshToken: auth.refreshToken })
});
if (!refreshedAuth.refreshToken || refreshedAuth.refreshToken === auth.refreshToken) {
  fail("refresh token was not rotated");
}
const replayedRefresh = await fetch(`${base}/v1/auth/refresh`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ refreshToken: auth.refreshToken })
});
if (replayedRefresh.status !== 401) fail(`replayed refresh should be 401, got ${replayedRefresh.status}`);
const token = refreshedAuth.accessToken;
const refreshToken = refreshedAuth.refreshToken;
await api("/v1/me", {}, token);
console.log("auth and refresh rotation ok");

// OpenAI-backed template improvement uses a deterministic substitute in mock mode.
const improvedTemplate = await api("/v1/templates/improve", {
  method: "POST",
  body: JSON.stringify({
    name: "Paris Night",
    description: "walking beside the Eiffel Tower after dark",
    outfit: ""
  })
}, token);
if (!improvedTemplate.description.includes("cinematic directional lighting")) {
  fail("AI template improvement missing cinematic detail");
}
if (!improvedTemplate.outfit) fail("AI template improvement missing outfit");
console.log("AI template improvement ok");

const unsafeTemplate = await fetch(`${base}/v1/templates/improve`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  body: JSON.stringify({
    name: "Unsafe",
    description: "a sexual scene involving an underage child",
    outfit: "none"
  })
});
if (unsafeTemplate.status !== 400) {
  fail(`unsafe custom text should be 400, got ${unsafeTemplate.status}`);
}
console.log("content safety gate ok");

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

// Two simultaneous paid requests for one account must not both enter the
// provider pipeline when the configured per-user concurrency is one.
const concurrentRequests = ["paris-cafe", "tokyo-shibuya"].map((sceneId) => fetch(`${base}/v1/scene-jobs`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
    "Idempotency-Key": crypto.randomUUID()
  },
  body: JSON.stringify({
    s3Key: presign.s3Key,
    sceneId,
    subjectGender: "female",
    timeOfDay: "day",
    weather: "sunny",
    pose: "walking"
  })
}));
const concurrentResponses = await Promise.all(concurrentRequests);
const concurrentStatuses = concurrentResponses.map((response) => response.status).sort();
if (concurrentStatuses[0] !== 200 || concurrentStatuses[1] !== 429) {
  fail(`concurrency gate expected 200/429, got ${concurrentStatuses.join("/")}`);
}
const acceptedConcurrentResponse = concurrentResponses.find((response) => response.status === 200);
const acceptedConcurrentJob = await acceptedConcurrentResponse.json();
await waitForJob(acceptedConcurrentJob.jobId, token);
console.log("per-user generation concurrency gate ok");

// Upload a second reference and prove same-gender companion data survives the
// complete HTTP route, not only the prompt-builder unit regression checks.
const companionPresign = await api("/v1/upload/presign", { method: "POST", body: "{}" }, token);
const companionUpload = await fetch(companionPresign.uploadURL, {
  method: "PUT",
  headers: { "Content-Type": "image/jpeg" },
  body: jpegBytes
});
if (!companionUpload.ok) fail(`companion upload -> ${companionUpload.status}`);

const ambiguousFriend = await fetch(`${base}/v1/scene-jobs`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
    "Idempotency-Key": crypto.randomUUID()
  },
  body: JSON.stringify({
    s3Key: presign.s3Key,
    companionS3Key: companionPresign.s3Key,
    sceneId: "times-square",
    subjectGender: "male",
    companionKind: "friend",
    companionGender: "auto",
    companionConsentConfirmed: true
  })
});
if (ambiguousFriend.status !== 400) fail(`ambiguous friend gender should be 400, got ${ambiguousFriend.status}`);

const missingCompanionConsentResponse = await fetch(`${base}/v1/scene-jobs`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
    "Idempotency-Key": crypto.randomUUID()
  },
  body: JSON.stringify({
    s3Key: presign.s3Key,
    companionS3Key: companionPresign.s3Key,
    sceneId: "times-square",
    subjectGender: "male",
    companionKind: "friend",
    companionGender: "male"
  })
});
const missingCompanionConsent = await missingCompanionConsentResponse.json();
if (missingCompanionConsentResponse.status !== 400
    || missingCompanionConsent.error?.code !== "COMPANION_CONSENT_REQUIRED") {
  fail(`missing companion consent should be structured 400, got ${missingCompanionConsentResponse.status}`);
}

const maleFriends = await api("/v1/scene-jobs", {
  method: "POST",
  body: JSON.stringify({
    s3Key: presign.s3Key,
    companionS3Key: companionPresign.s3Key,
    sceneId: "times-square",
    subjectGender: "male",
    companionKind: "friend",
    companionGender: "male",
    companionConsentConfirmed: true,
    timeOfDay: "night",
    weather: "sunny",
    pose: "walking"
  })
}, token);
if (!maleFriends.prompt.includes("two adult men")) fail("male+male request lost its gender pairing");
if (!maleFriends.prompt.includes("Image 2 shows an adult man")) fail("male friend identity lock missing");
const maleFriendsDone = await waitForJob(maleFriends.jobId, token);
if (!maleFriendsDone.imageURL || !maleFriendsDone.hasCompanion) fail("male+male companion job failed");
console.log("male+male companion job ok");

// 3. Gendered scene job
const job1IdempotencyKey = crypto.randomUUID();
const job1Options = {
  method: "POST",
  headers: { "Idempotency-Key": job1IdempotencyKey },
  body: JSON.stringify({
    s3Key: presign.s3Key,
    sceneId: "times-square",
    subjectGender: "female",
    timeOfDay: "night",
    weather: "sunny",
    pose: "walking"
  })
};
const job1 = await api("/v1/scene-jobs", job1Options, token);
const job1Replay = await api("/v1/scene-jobs", job1Options, token);
if (job1Replay.jobId !== job1.jobId) fail("idempotent replay created a duplicate job");

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
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
    "Idempotency-Key": crypto.randomUUID()
  },
  body: JSON.stringify({ s3Key: presign.s3Key, sceneId: "custom", customScene: { basePrompt: "" } })
});
if (badResponse.status !== 400) fail(`empty custom scene should be 400, got ${badResponse.status}`);
console.log("custom scene validation ok");

// 7. Video job from completed scene (Talking director + caption)
const video = await api(
  `/v1/scene-jobs/${done1.jobId}/video`,
  {
    method: "POST",
    body: JSON.stringify({
      motionStyle: "talking",
      spokenLine: "You're not going to believe this night."
    })
  },
  token
);
if (video.kind !== "video") fail("expected video kind");
if (!video.prompt?.includes("talk-show") && !video.prompt?.includes("mid-conversation")) {
  fail("talking video prompt missing speaking direction");
}
if (!video.prompt?.includes("You're not going to believe this night.")) {
  fail("talking video prompt missing spoken caption line");
}
if (video.motionStyle !== "talking") fail(`expected talking motionStyle, got ${video.motionStyle}`);
if (!video.spokenLine) fail("expected spokenLine on talking video job");
const videoDone = await waitForJob(video.jobId, token);
if (!videoDone.videoURL) fail("video job missing videoURL");
console.log(`video job ok -> ${videoDone.videoURL}`);

// 8. Same director settings reuse the cached video (no new generation)
const videoAgain = await api(
  `/v1/scene-jobs/${done1.jobId}/video`,
  {
    method: "POST",
    body: JSON.stringify({
      motionStyle: "talking",
      spokenLine: "You're not going to believe this night."
    })
  },
  token
);
if (videoAgain.status !== "completed" || videoAgain.videoURL !== videoDone.videoURL) {
  fail("second animate should reuse cached video instantly");
}
console.log("video reuse ok");

// 8b. Different director settings must NOT reuse the old cache key blindly
// (in mock mode a new job is created; we only assert the request is accepted)
const redirected = await api(
  `/v1/scene-jobs/${done1.jobId}/video`,
  {
    method: "POST",
    body: JSON.stringify({ motionStyle: "portrait", spokenLine: "" })
  },
  token
);
if (!redirected.jobId) fail("redirected video job missing jobId");
if (redirected.prompt && redirected.prompt.includes("talk-show")) {
  fail("portrait redirect should not keep talking prompt");
}
console.log("video redirect ok");

const portraitDone = await waitForJob(redirected.jobId, token);
const afterPortrait = await api(`/v1/scene-jobs/${done1.jobId}`, {}, token);
if (!Array.isArray(afterPortrait.videoClips) || afterPortrait.videoClips.length < 2) {
  fail(`expected >=2 videoClips after portrait, got ${JSON.stringify(afterPortrait.videoClips)}`);
}
const styles = new Set(afterPortrait.videoClips.map((clip) => clip.motionStyle));
if (!styles.has("talking") || !styles.has("portrait")) {
  fail(`videoClips missing talking/portrait: ${JSON.stringify([...styles])}`);
}
if (!portraitDone.videoURL) fail("portrait video missing videoURL");
console.log(`video library ok (${afterPortrait.videoClips.length} clips)`);

// 9. History still lists image jobs with videoURL attached
const history = await api("/v1/history?page=1&limit=10", {}, token);
if (history.items.length < 3) fail(`expected >=3 history items, got ${history.items.length}`);
const animated = history.items.find((item) => item.jobId === done1.jobId);
if (!animated?.videoURL) fail("history item missing persisted videoURL");
console.log("history ok");

// 10. Cross-account attempts must not disclose or mutate another user's
// uploads, jobs, results, or history.
const secondAuth = await api("/v1/auth/email", {
  method: "POST",
  body: JSON.stringify({ email: `smoke-second-${Date.now()}@test.dev`, password: "Password123!" })
});
if (!secondAuth.refreshToken) fail("second account missing refresh token");
const secondToken = secondAuth.accessToken;
const foreignJobRead = await fetch(`${base}/v1/scene-jobs/${done1.jobId}`, {
  headers: { Authorization: `Bearer ${secondToken}` }
});
if (foreignJobRead.status !== 404) fail(`cross-user job read should be 404, got ${foreignJobRead.status}`);
const foreignJobCancel = await fetch(`${base}/v1/scene-jobs/${done1.jobId}`, {
  method: "DELETE",
  headers: { Authorization: `Bearer ${secondToken}` }
});
if (foreignJobCancel.status !== 404) fail(`cross-user job delete should be 404, got ${foreignJobCancel.status}`);
const foreignUploadUse = await fetch(`${base}/v1/scene-jobs`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${secondToken}`,
    "Idempotency-Key": crypto.randomUUID()
  },
  body: JSON.stringify({ s3Key: presign.s3Key, sceneId: "times-square" })
});
if (foreignUploadUse.status !== 404) fail(`cross-user upload use should be 404, got ${foreignUploadUse.status}`);
const secondHistory = await api("/v1/history", {}, secondToken);
if (secondHistory.items.length !== 0) fail("second account can see first account history");
console.log("cross-user data isolation ok");

// 11. Public legal pages (App Store / IAP requirement)
const privacy = await fetch(`${base}/privacy`);
const terms = await fetch(`${base}/terms`);
const support = await fetch(`${base}/support`);
if (!privacy.ok) fail(`privacy page -> ${privacy.status}`);
if (!terms.ok) fail(`terms page -> ${terms.status}`);
if (!support.ok) fail(`support page -> ${support.status}`);
const privacyHTML = await privacy.text();
const termsHTML = await terms.text();
const supportHTML = await support.text();
if (!privacyHTML.includes("Privacy Policy") || !privacyHTML.includes("Zevynta Labs LLC")) {
  fail("privacy page missing expected content");
}
if (!termsHTML.includes("Terms of Use") || !termsHTML.includes("Subscriptions") || !termsHTML.includes("zevyntalabs.com")) {
  fail("terms page missing expected content");
}
if (!supportHTML.includes("SceneMe Support") || !supportHTML.includes("support@sceneme.app")) {
  fail("support page missing expected content");
}
const privacyHead = await fetch(`${base}/privacy`, { method: "HEAD" });
const termsHead = await fetch(`${base}/terms`, { method: "HEAD" });
const supportHead = await fetch(`${base}/support`, { method: "HEAD" });
if (!privacyHead.ok) fail(`privacy HEAD -> ${privacyHead.status}`);
if (!termsHead.ok) fail(`terms HEAD -> ${termsHead.status}`);
if (!supportHead.ok) fail(`support HEAD -> ${supportHead.status}`);
console.log("legal pages ok");

// 12. Logout revokes the refresh credential, and account deletion revokes all
// remaining sessions while immediately invalidating access through user lookup.
await api("/v1/auth/logout", {
  method: "POST",
  body: JSON.stringify({ refreshToken: secondAuth.refreshToken })
});
const loggedOutRefresh = await fetch(`${base}/v1/auth/refresh`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ refreshToken: secondAuth.refreshToken })
});
if (loggedOutRefresh.status !== 401) fail(`logged-out refresh should be 401, got ${loggedOutRefresh.status}`);
await api("/v1/account", { method: "DELETE" }, secondToken);
await api("/v1/account", { method: "DELETE" }, token);
const deletedRefresh = await fetch(`${base}/v1/auth/refresh`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ refreshToken })
});
if (deletedRefresh.status !== 401) fail(`deleted account refresh should be 401, got ${deletedRefresh.status}`);
const afterDeletion = await fetch(`${base}/v1/history`, {
  headers: { Authorization: `Bearer ${token}` }
});
if (afterDeletion.status !== 401) {
  fail(`deleted account token should be 401, got ${afterDeletion.status}`);
}
console.log("session logout, replay protection and account revocation ok");

// 13. The endpoint returns a structured 429 and Retry-After when the durable
// auth window is exhausted. Earlier session lifecycle calls consumed part of it.
let limitedResponse = null;
for (let attempt = 0; attempt < 35; attempt += 1) {
  const candidate = await fetch(`${base}/v1/auth/email`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: "invalid", password: "short" })
  });
  if (candidate.status === 429) {
    limitedResponse = candidate;
    break;
  }
}
if (!limitedResponse) fail("auth rate limit did not return 429");
const limitedBody = await limitedResponse.json();
if (limitedBody.error?.code !== "RATE_LIMITED") fail("rate limit error code is not structured");
if (!limitedResponse.headers.get("retry-after")) fail("rate limit response missing Retry-After");
console.log("durable HTTP rate-limit response ok");

console.log("ALL SMOKE TESTS PASSED");
