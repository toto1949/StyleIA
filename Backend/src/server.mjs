import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { URL } from "node:url";
import {
  assertEmailPassword,
  authenticateRequest,
  hashPassword,
  signToken,
  signUploadToken,
  verifyAppleIdentityToken,
  verifyPassword,
  verifyToken
} from "./auth.mjs";
import { config } from "./config.mjs";
import { FalBillingError, generateStyleVariants } from "./fal.mjs";
import { corsHeaders, HttpError, readJSON, readRawBody, sendError, sendJSON } from "./http-utils.mjs";
import { JsonStore } from "./store.mjs";
import { broadcastJobUpdate, handleUpgrade, sendJobUpdate } from "./websocket.mjs";

const allowedStyleGoals = new Set(["casual", "professional", "wedding", "sporty", "luxury", "streetwear"]);
const store = new JsonStore(config.dataPath);
const cancelledJobs = new Set();

await fs.mkdir(config.uploadDirectory, { recursive: true });
await store.init();

const server = http.createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    response.writeHead(204, corsHeaders());
    response.end();
    return;
  }

  try {
    await route(request, response);
  } catch (error) {
    logBackend("request_error", {
      method: request.method,
      url: request.url,
      error: error.message || String(error)
    });
    sendError(response, error);
  }
});

server.on("upgrade", (request, socket, head) => {
  handleUpgrade(request, socket, head, (_jobId, token) => {
    const payload = verifyToken(token, "access");
    return { userId: payload.sub };
  }, (jobId, context, socket) => {
    sendInitialJobUpdate(jobId, context.userId, socket);
  });
});

server.listen(config.port, () => {
  console.log(`StyleAI backend listening on ${config.publicBaseURL}`);
  console.log(`REST base: ${config.publicBaseURL}/v1`);
  console.log(`WebSocket base: ${config.publicBaseURL.replace(/^http/, "ws")}/ws`);
  logBackend("server_started", {
    port: config.port,
    publicBaseURL: config.publicBaseURL,
    falModel: config.falModel,
    mockGeneration: config.enableMockGeneration,
    fallbackToMockOnFalBilling: config.fallbackToMockOnFalBilling
  });
});

async function route(request, response) {
  const url = new URL(request.url, config.publicBaseURL);
  const pathname = url.pathname;

  if (request.method === "GET" && pathname === "/health") {
    sendJSON(response, 200, { ok: true });
    return;
  }

  if (request.method === "GET" && pathname.startsWith("/uploads/")) {
    await serveUpload(pathname, response);
    return;
  }

  if (!pathname.startsWith("/v1")) {
    throw new HttpError(404, "Not found.");
  }

  const routePath = pathname.slice(3) || "/";

  if (request.method === "POST" && routePath === "/auth/email") {
    await authEmail(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/auth/apple") {
    await authApple(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/upload/presign") {
    await presignUpload(request, response);
    return;
  }

  const uploadMatch = routePath.match(/^\/upload\/([^/]+)$/);
  if (request.method === "PUT" && uploadMatch) {
    await receiveUpload(request, response, uploadMatch[1], url.searchParams.get("token") || "");
    return;
  }

  if (request.method === "POST" && routePath === "/jobs") {
    await createJob(request, response);
    return;
  }

  const jobMatch = routePath.match(/^\/jobs\/([^/]+)$/);
  if (jobMatch && request.method === "GET") {
    await getJob(request, response, jobMatch[1]);
    return;
  }

  if (jobMatch && request.method === "DELETE") {
    await deleteJob(request, response, jobMatch[1]);
    return;
  }

  if (request.method === "GET" && routePath === "/history") {
    await history(request, response, url);
    return;
  }

  if (request.method === "DELETE" && routePath === "/account") {
    await deleteAccount(request, response);
    return;
  }

  throw new HttpError(404, "Not found.");
}

async function authEmail(request, response) {
  const body = await readJSON(request);
  const { email, password } = assertEmailPassword(body.email, body.password);

  const user = await store.mutate(async (data) => {
    const existing = data.users.find((candidate) => candidate.email === email);
    if (existing) {
      if (!existing.passwordHash || !existing.passwordSalt) {
        throw new HttpError(409, "Use Sign in with Apple for this account.");
      }

      const isValid = await verifyPassword(password, existing.passwordSalt, existing.passwordHash);
      if (!isValid) {
        throw new HttpError(401, "Invalid email or password.");
      }

      return existing;
    }

    const passwordRecord = await hashPassword(password);
    const created = {
      id: crypto.randomUUID(),
      email,
      passwordHash: passwordRecord.hash,
      passwordSalt: passwordRecord.salt,
      appleSub: "",
      fullName: "",
      createdAt: new Date().toISOString()
    };
    data.users.push(created);
    return created;
  });

  sendJSON(response, 200, userResponse(user));
}

async function authApple(request, response) {
  const body = await readJSON(request);
  const apple = await verifyAppleIdentityToken(body.identityToken);
  const fullName = String(body.fullName || "").trim();

  const user = await store.mutate(async (data) => {
    const existing = data.users.find((candidate) => candidate.appleSub === apple.appleSub);
    if (existing) {
      if (apple.email && !existing.email) {
        existing.email = apple.email.toLowerCase();
      }
      if (fullName && !existing.fullName) {
        existing.fullName = fullName;
      }
      return existing;
    }

    const email = String(apple.email || "").toLowerCase();
    const byEmail = email ? data.users.find((candidate) => candidate.email === email) : undefined;
    if (byEmail) {
      byEmail.appleSub = apple.appleSub;
      if (fullName && !byEmail.fullName) {
        byEmail.fullName = fullName;
      }
      return byEmail;
    }

    const created = {
      id: crypto.randomUUID(),
      email,
      passwordHash: "",
      passwordSalt: "",
      appleSub: apple.appleSub,
      fullName,
      createdAt: new Date().toISOString()
    };
    data.users.push(created);
    return created;
  });

  sendJSON(response, 200, userResponse(user));
}

async function presignUpload(request, response) {
  const auth = authenticateRequest(request);
  const uploadId = crypto.randomUUID();
  const s3Key = `uploads/${uploadId}.jpg`;
  const uploadToken = signUploadToken(auth.sub, uploadId);
  const uploadURL = `${config.publicBaseURL}/v1/upload/${uploadId}?token=${encodeURIComponent(uploadToken)}`;

  await store.mutate(async (data) => {
    data.uploads.push({
      id: uploadId,
      userId: auth.sub,
      s3Key,
      localPath: path.join(config.uploadDirectory, `${uploadId}.jpg`),
      publicURL: `${config.publicBaseURL}/uploads/${uploadId}.jpg`,
      status: "pending",
      size: 0,
      contentType: "image/jpeg",
      createdAt: new Date().toISOString()
    });
  });

  logBackend("upload_presigned", { userId: auth.sub, uploadId, s3Key });
  sendJSON(response, 200, { uploadURL, s3Key });
}

async function receiveUpload(request, response, uploadId, token) {
  const uploadAuth = verifyToken(token, "upload");
  if (uploadAuth.uploadId !== uploadId) {
    throw new HttpError(401, "Unauthorized.");
  }

  const body = await readRawBody(request, config.maxUploadBytes);
  if (body.length === 0) {
    throw new HttpError(400, "Upload body is empty.");
  }

  if (!String(request.headers["content-type"] || "").startsWith("image/")) {
    throw new HttpError(415, "Upload must be an image.");
  }

  const upload = await store.mutate(async (data) => {
    const candidate = data.uploads.find((item) => item.id === uploadId && item.userId === uploadAuth.sub);
    if (!candidate) {
      throw new HttpError(404, "Upload not found.");
    }

    await fs.writeFile(candidate.localPath, body);
    candidate.status = "uploaded";
    candidate.size = body.length;
    candidate.contentType = request.headers["content-type"] || "image/jpeg";
    candidate.updatedAt = new Date().toISOString();
    return candidate;
  });

  logBackend("upload_received", {
    userId: upload.userId,
    uploadId: upload.id,
    s3Key: upload.s3Key,
    bytes: upload.size,
    contentType: upload.contentType
  });
  sendJSON(response, 200, { success: true, s3Key: upload.s3Key });
}

async function createJob(request, response) {
  const auth = authenticateRequest(request);
  const body = await readJSON(request);
  const s3Key = String(body.s3Key || "");
  const styleGoal = String(body.styleGoal || "");
  const subjectGender = normalizeSubjectGender(body.subjectGender);
  const styleProfile = normalizeStyleProfile({
    ...(isPlainObject(body.styleProfile) ? body.styleProfile : {}),
    subjectGender
  });

  if (!allowedStyleGoals.has(styleGoal)) {
    throw new HttpError(400, "Invalid style goal.");
  }

  const styleGoals = normalizeStyleGoals(styleGoal, body.styleGoals);
  const seed = Number.isFinite(Number(body.seed)) ? Number(body.seed) : undefined;
  const job = await store.mutate(async (data) => {
    const upload = data.uploads.find(
      (candidate) => candidate.userId === auth.sub && candidate.s3Key === s3Key && candidate.status === "uploaded"
    );

    if (!upload) {
      throw new HttpError(404, "Uploaded image not found.");
    }

    const created = {
      id: crypto.randomUUID(),
      jobId: crypto.randomUUID(),
      userId: auth.sub,
      s3Key,
      styleGoal,
      styleGoals,
      subjectGender,
      styleProfile,
      status: "pending",
      progress: 0,
      resultURLs: [],
      looks: [],
      error: "",
      originalPhotoURL: upload.publicURL,
      localPath: upload.localPath,
      contentType: upload.contentType || "image/jpeg",
      seed: seed ?? Math.floor(Math.random() * 1_000_000_000),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    data.jobs.push(created);
    return created;
  });

  logBackend("job_created", {
    jobId: job.jobId,
    userId: auth.sub,
    styleGoal: job.styleGoal,
    styleGoals: job.styleGoals,
    subjectGender: job.subjectGender,
    styleProfile: job.styleProfile,
    seed: job.seed
  });

  runGeneration(job.jobId).catch((error) => {
    logBackend("job_background_error", { jobId: job.jobId, error: error.message || String(error) });
  });

  sendJSON(response, 200, generationJobResponse(job));
}

async function getJob(request, response, jobId) {
  const auth = authenticateRequest(request);
  const data = await store.snapshot();
  const job = data.jobs.find((candidate) => candidate.jobId === jobId && candidate.userId === auth.sub);
  if (!job) {
    throw new HttpError(404, "Job not found.");
  }

  sendJSON(response, 200, generationJobResponse(job));
}

async function deleteJob(request, response, jobId) {
  const auth = authenticateRequest(request);
  cancelledJobs.add(jobId);

  await store.mutate(async (data) => {
    const index = data.jobs.findIndex((candidate) => candidate.jobId === jobId && candidate.userId === auth.sub);
    if (index === -1) {
      throw new HttpError(404, "Job not found.");
    }
    data.jobs.splice(index, 1);
  });

  sendJSON(response, 200, { success: true });
}

async function history(request, response, url) {
  const auth = authenticateRequest(request);
  const page = Math.max(1, Number.parseInt(url.searchParams.get("page") || "1", 10));
  const limit = Math.min(50, Math.max(1, Number.parseInt(url.searchParams.get("limit") || "20", 10)));
  const data = await store.snapshot();
  const completed = data.jobs
    .filter((job) => job.userId === auth.sub && job.status === "completed")
    .sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime());
  const start = (page - 1) * limit;
  const items = completed.slice(start, start + limit).map(historyItemResponse);

  sendJSON(response, 200, { items, total: completed.length });
}

async function deleteAccount(request, response) {
  const auth = authenticateRequest(request);
  const filesToDelete = await store.mutate(async (data) => {
    const uploads = data.uploads.filter((upload) => upload.userId === auth.sub);
    data.users = data.users.filter((user) => user.id !== auth.sub);
    data.uploads = data.uploads.filter((upload) => upload.userId !== auth.sub);
    data.jobs = data.jobs.filter((job) => job.userId !== auth.sub);
    return uploads.map((upload) => upload.localPath);
  });

  await Promise.all(filesToDelete.map((filePath) => fs.unlink(filePath).catch(() => {})));
  sendJSON(response, 200, { success: true });
}

async function serveUpload(pathname, response) {
  const fileName = path.basename(decodeURIComponent(pathname));
  if (!/^[a-f0-9-]+\.jpg$/i.test(fileName)) {
    throw new HttpError(404, "Not found.");
  }

  const filePath = path.join(config.uploadDirectory, fileName);
  let body;
  try {
    body = await fs.readFile(filePath);
  } catch {
    throw new HttpError(404, "Not found.");
  }

  response.writeHead(200, {
    "Content-Type": "image/jpeg",
    "Content-Length": body.length,
    "Cache-Control": "public, max-age=31536000, immutable",
    ...corsHeaders()
  });
  response.end(body);
}

async function runGeneration(jobId) {
  const job = await transitionJob(jobId, { status: "processing", progress: 5 });
  if (!job) {
    logBackend("job_missing_on_start", { jobId });
    return;
  }

  const startedAt = Date.now();
  logBackend("job_processing_started", {
    jobId,
    styleGoal: job.styleGoal,
    styleGoals: job.styleGoals,
    subjectGender: job.subjectGender,
    mockGeneration: config.enableMockGeneration,
    fallbackToMockOnFalBilling: config.fallbackToMockOnFalBilling
  });
  broadcastJobUpdate(jobId, { type: "progress", percent: 5 });

  try {
    const looks = await generateStyleVariants({
      imageURL: job.originalPhotoURL,
      imagePath: job.localPath,
      contentType: job.contentType,
      styleGoal: job.styleGoal,
      styleGoals: job.styleGoals,
      subjectGender: job.subjectGender,
      styleProfile: job.styleProfile,
      userId: job.userId,
      seed: job.seed,
      jobId,
      onProgress: (percent) => updateProgress(jobId, percent),
      onLookReady: (look) => appendGeneratedLook(jobId, look)
    });
    const resultURLs = looks.map((look) => look.imageURL).filter(Boolean);

    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logBackend("job_cancelled_after_generation", { jobId });
      return;
    }

    await transitionJob(jobId, {
      status: "completed",
      progress: 100,
      resultURLs,
      looks,
      error: ""
    });
    logBackend("job_completed", {
      jobId,
      durationMs: Date.now() - startedAt,
      lookCount: looks.length,
      resultCount: resultURLs.length
    });
    broadcastJobUpdate(jobId, { type: "completed", resultURLs, looks });
  } catch (error) {
    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logBackend("job_cancelled_after_error", { jobId });
      return;
    }

    logBackend("job_failed", {
      jobId,
      durationMs: Date.now() - startedAt,
      ...serializeError(error)
    });
    const publicError = publicGenerationError(error);

    await transitionJob(jobId, {
      status: "failed",
      progress: 100,
      resultURLs: [],
      looks: [],
      error: publicError
    });
    broadcastJobUpdate(jobId, { type: "failed", error: publicError });
  }
}

async function updateProgress(jobId, percent) {
  if (cancelledJobs.has(jobId)) {
    return;
  }

  const bounded = Math.max(0, Math.min(99, Math.round(percent)));
  logBackend("job_progress", { jobId, percent: bounded });
  await transitionJob(jobId, { status: "processing", progress: bounded });
  broadcastJobUpdate(jobId, { type: "progress", percent: bounded });
}

async function appendGeneratedLook(jobId, look) {
  if (cancelledJobs.has(jobId)) {
    return;
  }

  const job = await store.mutate(async (data) => {
    const candidate = data.jobs.find((item) => item.jobId === jobId);
    if (!candidate) {
      return null;
    }

    const existingLooks = Array.isArray(candidate.looks) ? candidate.looks : [];
    const nextLooks = existingLooks.filter((item) => item.id !== look.id);
    nextLooks.push(look);
    nextLooks.sort((lhs, rhs) => styleOrder(candidate.styleGoals, lhs.styleGoal) - styleOrder(candidate.styleGoals, rhs.styleGoal));

    candidate.looks = nextLooks;
    candidate.resultURLs = nextLooks.map((item) => item.imageURL).filter(Boolean);
    candidate.updatedAt = new Date().toISOString();
    return { ...candidate };
  });

  if (!job) {
    return;
  }

  logBackend("job_look_ready", {
    jobId,
    styleGoal: look.styleGoal,
    readyCount: job.looks.length,
    totalCount: job.styleGoals.length
  });
  broadcastJobUpdate(jobId, {
    type: "partial",
    resultURLs: job.resultURLs || [],
    looks: job.looks || []
  });
}

function styleOrder(styleGoals = [], styleGoal) {
  const index = styleGoals.indexOf(styleGoal);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
}

async function transitionJob(jobId, patch) {
  return store.mutate(async (data) => {
    const job = data.jobs.find((candidate) => candidate.jobId === jobId);
    if (!job) {
      return null;
    }

    Object.assign(job, patch, { updatedAt: new Date().toISOString() });
    return { ...job };
  });
}

async function sendInitialJobUpdate(jobId, userId, socket) {
  const data = await store.snapshot();
  const job = data.jobs.find((candidate) => candidate.jobId === jobId && candidate.userId === userId);
  if (!job) {
    socket.destroy();
    return;
  }

  if (job.status === "completed") {
    sendJobUpdate(socket, { type: "completed", resultURLs: job.resultURLs, looks: job.looks || [] });
  } else if (job.status === "failed") {
    sendJobUpdate(socket, { type: "failed", error: "Generation failed. Your credits have not been used." });
  } else {
    sendJobUpdate(socket, { type: "progress", percent: job.progress });
  }
}

function userResponse(user) {
  return {
    userId: user.id,
    email: user.email || "",
    accessToken: signToken({ type: "access", sub: user.id })
  };
}

function generationJobResponse(job) {
  return {
    jobId: job.jobId,
    status: job.status,
    progress: job.progress,
    resultURLs: job.resultURLs || [],
    looks: job.looks || [],
    subjectGender: job.subjectGender || "male",
    styleProfile: job.styleProfile || null,
    error: job.error || null
  };
}

function historyItemResponse(job) {
  return {
    id: job.id,
    jobId: job.jobId,
    styleGoal: job.styleGoal,
    thumbnailURL: job.resultURLs?.[0] || null,
    resultURLs: job.resultURLs || [],
    looks: job.looks || [],
    subjectGender: job.subjectGender || "male",
    styleProfile: job.styleProfile || null,
    originalPhotoURL: job.originalPhotoURL,
    createdAt: job.createdAt,
    isSaved: false
  };
}

function normalizeStyleGoals(primaryGoal, requestedGoals) {
  const requested = Array.isArray(requestedGoals) ? requestedGoals : [];
  const goals = [primaryGoal, ...requested]
    .map((goal) => String(goal || "").trim())
    .filter((goal) => allowedStyleGoals.has(goal));

  return [...new Set(goals)].slice(0, 5);
}

function normalizeSubjectGender(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["female", "woman", "women"].includes(normalized)) {
    return "female";
  }
  if (["nonbinary", "non-binary", "nb"].includes(normalized)) {
    return "nonbinary";
  }

  return "male";
}

function normalizeStyleProfile(value = {}) {
  return {
    subjectGender: normalizeSubjectGender(value.subjectGender),
    ageRange: cleanProfileValue(value.ageRange, "adult"),
    bodyType: cleanProfileValue(value.bodyType),
    heightRange: cleanProfileValue(value.heightRange),
    skinTone: cleanProfileValue(value.skinTone),
    undertone: cleanProfileValue(value.undertone),
    hairColor: cleanProfileValue(value.hairColor),
    faceShape: cleanProfileValue(value.faceShape),
    fitPreference: cleanProfileValue(value.fitPreference),
    colorPreference: cleanProfileValue(value.colorPreference),
    modestyPreference: cleanProfileValue(value.modestyPreference),
    climate: cleanProfileValue(value.climate),
    occasion: cleanProfileValue(value.occasion),
    budget: cleanProfileValue(value.budget),
    stylePersona: cleanProfileValue(value.stylePersona),
    favoriteColors: normalizeProfileList(value.favoriteColors).slice(0, 6),
    avoid: normalizeProfileList(value.avoid).slice(0, 8)
  };
}

function cleanProfileValue(value, fallback = "") {
  const cleaned = String(value || "").trim().replace(/[^\w\s.,&/-]/g, "").slice(0, 80);
  return cleaned || fallback;
}

function normalizeProfileList(value) {
  if (Array.isArray(value)) {
    return value.map((item) => cleanProfileValue(item)).filter(Boolean);
  }

  return String(value || "")
    .split(",")
    .map((item) => cleanProfileValue(item))
    .filter(Boolean);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function logBackend(event, details = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "styleai-backend",
    event,
    ...details
  }));
}

function serializeError(error) {
  return {
    error: error?.message || String(error),
    errorName: error?.name || "",
    status: error?.status || null,
    requestId: error?.requestId || "",
    fieldErrors: Array.isArray(error?.fieldErrors)
      ? error.fieldErrors.map((item) => ({
        loc: item.loc,
        msg: item.msg,
        type: item.type
      }))
      : undefined,
    body: summarizeErrorBody(error?.body)
  };
}

function publicGenerationError(error) {
  if (error instanceof FalBillingError) {
    return error.message;
  }

  return error?.message || "Generation failed. Your credits have not been used.";
}

function summarizeErrorBody(body) {
  if (!body) {
    return undefined;
  }

  try {
    const cloned = JSON.parse(JSON.stringify(body));
    return cloned.detail || cloned;
  } catch {
    return String(body).slice(0, 500);
  }
}
