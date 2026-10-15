import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import { URL } from "node:url";
import {
  assertEmailPassword,
  authenticateRequest,
  hashPassword,
  signToken,
  verifyAppleIdentityToken,
  verifyGoogleIdentityToken,
  verifyPassword,
  verifyToken
} from "./auth.mjs";
import { config } from "./config.mjs";
import { corsHeaders, HttpError, readJSON, sendError, sendJSON } from "./http-utils.mjs";
import {
  cancelJobsForAccountDeletion,
  cancelSceneJob,
  createSceneJob,
  createVideoJob,
  getSceneJob,
  recoverInterruptedJobs,
  rerollSceneJob,
  sceneHistory
} from "./routes/generate.mjs";
import { servePrivacyPolicy, serveSupport, serveTermsOfUse } from "./routes/legal.mjs";
import { listScenes } from "./routes/scenes.mjs";
import { presignUpload, receiveUpload, serveUpload } from "./routes/upload.mjs";
import { store } from "./services/store-instance.mjs";
import { handleUpgrade, sendJobUpdate } from "./websocket.mjs";
import { improveSceneTemplate } from "./services/openai-template-service.mjs";
import {
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken
} from "./services/apple-account-service.mjs";
import {
  appStoreTierForRequest,
  creditStatusForUser,
  processAppStoreNotification,
  requireTier,
  subscriptionStatusForUser,
  syncAppStoreTransaction
} from "./services/app-store-service.mjs";
import { assertSafeUserText } from "./services/content-safety-service.mjs";
import { objectStorage } from "./services/object-storage-service.mjs";
import { ensureReviewerAccount } from "./services/reviewer-account.mjs";

await fs.mkdir(config.uploadDirectory, { recursive: true });
await store.init();
await ensureReviewerAccount();
const recovery = await recoverInterruptedJobs();
if (recovery.resumed || recovery.failedSafely) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event: "job_recovery_completed",
    ...recovery
  }));
}

const server = http.createServer(async (request, response) => {
  const requestId = crypto.randomUUID();
  response.setHeader("X-Request-ID", requestId);
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
      path: safePathname(request.url),
      requestId,
      error: error.message || String(error)
    });
    sendError(response, error);
  }
});

server.on("upgrade", (request, socket, head) => {
  handleUpgrade(request, socket, head, async (jobId, token) => {
    const payload = verifyToken(token, "access");
    const data = await store.snapshot();
    const job = data.jobs.find(
      (candidate) => candidate.jobId === jobId && candidate.userId === payload.sub
    );
    if (!job) {
      throw new Error("Job not found for user.");
    }
    return { userId: payload.sub };
  }, (jobId, context, socket) => {
    sendInitialJobUpdate(jobId, context.userId, socket);
  });
});

server.listen(config.port, () => {
  console.log(`SceneMe backend listening on ${config.publicBaseURL}`);
  console.log(`REST base: ${config.publicBaseURL}/v1`);
  console.log(`WebSocket base: ${config.publicBaseURL.replace(/^http/, "ws")}/ws`);
  logBackend("server_started", {
    port: config.port,
    publicBaseURL: config.publicBaseURL,
    falModel: config.ecoMode ? config.falEcoModel : config.falModel,
    falMultiModel: config.falMultiModel,
    falKontextSteps: config.falKontextSteps,
    falVideoModel: config.falVideoModel,
    videoResolution: config.videoResolution,
    ecoMode: config.ecoMode,
    reuseIdenticalResults: config.reuseIdenticalResults,
    mockGeneration: config.enableMockGeneration,
    fallbackToMockOnFalBilling: config.fallbackToMockOnFalBilling
  });
});

async function route(request, response) {
  const url = new URL(request.url, config.publicBaseURL);
  const pathname = url.pathname;

  if (pathname.startsWith("/v1")) {
    await enforceRateLimit(
      request,
      "api-ip",
      config.apiRateLimitPerMinute,
      60_000,
      clientAddress(request)
    );
    const authenticatedUserId = accessTokenSubject(request);
    if (authenticatedUserId) {
      await enforceRateLimit(
        request,
        "api-user",
        config.userRateLimitPerMinute,
        60_000,
        authenticatedUserId
      );
    }
  }

  if (request.method === "GET" && pathname === "/health") {
    await store.snapshot();
    sendJSON(response, 200, { ok: true, database: config.databaseURL ? "postgresql" : "local" });
    return;
  }

  if (
    (request.method === "GET" || request.method === "HEAD")
    && (pathname === "/privacy" || pathname === "/privacy/")
  ) {
    servePrivacyPolicy(request, response);
    return;
  }

  if (
    (request.method === "GET" || request.method === "HEAD")
    && (pathname === "/terms" || pathname === "/terms/")
  ) {
    serveTermsOfUse(request, response);
    return;
  }

  if (
    (request.method === "GET" || request.method === "HEAD")
    && (pathname === "/support" || pathname === "/support/")
  ) {
    serveSupport(request, response);
    return;
  }

  if (request.method === "GET" && pathname.startsWith("/uploads/")) {
    // Original user photos are read from disk and uploaded to fal.ai by the
    // server. They are never exposed as a public production media endpoint.
    if (config.nodeEnv === "production") {
      throw new HttpError(404, "Not found.");
    }
    await serveUpload(pathname, response);
    return;
  }

  if (!pathname.startsWith("/v1")) {
    throw new HttpError(404, "Not found.");
  }

  const routePath = pathname.slice(3) || "/";

  if (request.method === "POST" && routePath === "/app-store/notifications") {
    await enforceRateLimit(
      request,
      "app-store-notifications",
      config.appStoreNotificationRateLimitPerMinute,
      60_000,
      clientAddress(request)
    );
    const body = await readJSON(request, 200_000);
    const result = await processAppStoreNotification(body.signedPayload);
    sendJSON(response, 200, { success: true, duplicate: result.duplicate });
    return;
  }

  if (request.method === "POST" && routePath === "/auth/email") {
    await enforceRateLimit(request, "auth", config.authRateLimitPer15Minutes, 15 * 60_000, clientAddress(request));
    await authEmail(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/auth/refresh") {
    await enforceRateLimit(request, "auth", config.authRateLimitPer15Minutes, 15 * 60_000, clientAddress(request));
    await refreshSession(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/auth/logout") {
    await enforceRateLimit(request, "auth", config.authRateLimitPer15Minutes, 15 * 60_000, clientAddress(request));
    await logoutSession(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/auth/apple") {
    await enforceRateLimit(request, "auth", config.authRateLimitPer15Minutes, 15 * 60_000, clientAddress(request));
    await authApple(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/auth/google") {
    await enforceRateLimit(request, "auth", config.authRateLimitPer15Minutes, 15 * 60_000, clientAddress(request));
    await authGoogle(request, response);
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

  if (request.method === "GET" && routePath === "/scenes") {
    await listScenes(request, response);
    return;
  }

  if (request.method === "POST" && routePath === "/subscriptions/sync") {
    const auth = await authenticateRequest(request);
    const body = await readJSON(request);
    const transactionId = String(
      body.transactionId || request.headers["x-sceneme-app-store-transaction-id"] || ""
    );
    const subscription = await syncAppStoreTransaction(transactionId, auth.sub);
    sendJSON(response, 200, subscription);
    return;
  }

  if (request.method === "GET" && routePath === "/me") {
    const auth = await authenticateRequest(request);
    const credits = await creditStatusForUser(auth.sub);
    const data = await store.snapshot();
    const month = new Date().toISOString().slice(0, 7);
    const usage = data.usage.find((candidate) => candidate.userId === auth.sub && candidate.month === month);
    sendJSON(response, 200, {
      subscription: await subscriptionStatusForUser(auth.sub),
      credits,
      usage: {
        month,
        imageGenerations: Number(usage?.generations || 0),
        videoGenerations: Number(usage?.videoGenerations || 0)
      }
    });
    return;
  }

  if (request.method === "POST" && routePath === "/templates/improve") {
    const auth = await authenticateRequest(request);
    const tier = await appStoreTierForRequest(request, auth.sub);
    requireTier(tier, "creator", "AI template improvement");
    const body = await readJSON(request);
    await assertSafeUserText([body.name, body.description, body.outfit], auth.sub);
    const template = await improveSceneTemplate({ ...body, userId: auth.sub });
    sendJSON(response, 200, template);
    return;
  }

  if (request.method === "POST" && routePath === "/scene-jobs") {
    await createSceneJob(request, response);
    return;
  }

  const rerollMatch = routePath.match(/^\/scene-jobs\/([^/]+)\/reroll$/);
  if (request.method === "POST" && rerollMatch) {
    await rerollSceneJob(request, response, rerollMatch[1]);
    return;
  }

  const videoMatch = routePath.match(/^\/scene-jobs\/([^/]+)\/video$/);
  if (request.method === "POST" && videoMatch) {
    await createVideoJob(request, response, videoMatch[1]);
    return;
  }

  const sceneJobMatch = routePath.match(/^\/scene-jobs\/([^/]+)$/);
  if (sceneJobMatch && request.method === "GET") {
    await getSceneJob(request, response, sceneJobMatch[1]);
    return;
  }

  if (sceneJobMatch && request.method === "DELETE") {
    await cancelSceneJob(request, response, sceneJobMatch[1]);
    return;
  }

  if (request.method === "GET" && routePath === "/history") {
    await sceneHistory(request, response, url);
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
  // "signin" rejects unknown emails, "signup" rejects existing ones.
  // Omitted mode keeps the legacy sign-in-or-create behavior.
  const mode = String(body.mode || "").toLowerCase();
  const fullName = String(body.fullName || "").trim().slice(0, 80);

  const user = await store.mutate(async (data) => {
    const existing = data.users.find((candidate) => candidate.email === email);

    if (existing) {
      if (mode === "signup") {
        throw new HttpError(409, "An account with this email already exists. Sign in instead.");
      }

      if (!existing.passwordHash || !existing.passwordSalt) {
        throw new HttpError(409, socialSignInMessage(existing));
      }

      const isValid = await verifyPassword(password, existing.passwordSalt, existing.passwordHash);
      if (!isValid) {
        throw new HttpError(401, "Invalid email or password.");
      }

      return existing;
    }

    if (mode === "signin") {
      throw new HttpError(404, "No account found for this email. Create one instead.");
    }

    const passwordRecord = await hashPassword(password);
    const created = {
      id: crypto.randomUUID(),
      email,
      passwordHash: passwordRecord.hash,
      passwordSalt: passwordRecord.salt,
      appleSub: "",
      googleSub: "",
      fullName,
      createdAt: new Date().toISOString()
    };
    data.users.push(created);
    return created;
  });

  sendJSON(response, 200, await issueSession(user));
}

async function authApple(request, response) {
  const body = await readJSON(request);
  const apple = await verifyAppleIdentityToken(body.identityToken);
  const authorizationCode = String(body.authorizationCode || "");
  if (!authorizationCode) {
    throw new HttpError(400, "Apple authorization code is required.");
  }
  const appleRefreshToken = await exchangeAppleAuthorizationCode(authorizationCode);
  const fullName = String(body.fullName || "").trim();

  const user = await store.mutate(async (data) => {
    const existing = data.users.find((candidate) => candidate.appleSub === apple.appleSub);
    if (existing) {
      if (appleRefreshToken) {
        existing.appleRefreshToken = appleRefreshToken;
      }
      if (apple.email && !existing.email) {
        existing.email = apple.email.toLowerCase();
      }
      if (fullName && !existing.fullName) {
        existing.fullName = fullName;
      }
      return existing;
    }

    const email = String(apple.email || "").toLowerCase();
    const byEmail = apple.emailVerified && email
      ? data.users.find((candidate) => candidate.email === email)
      : undefined;
    if (byEmail) {
      byEmail.appleSub = apple.appleSub;
      if (appleRefreshToken) {
        byEmail.appleRefreshToken = appleRefreshToken;
      }
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
      appleRefreshToken,
      googleSub: "",
      fullName,
      createdAt: new Date().toISOString()
    };
    data.users.push(created);
    return created;
  });

  sendJSON(response, 200, await issueSession(user));
}

async function authGoogle(request, response) {
  const body = await readJSON(request);
  const google = await verifyGoogleIdentityToken(body.identityToken);
  const fullName = String(body.fullName || google.fullName || "").trim();

  const user = await store.mutate(async (data) => {
    const existing = data.users.find((candidate) => candidate.googleSub === google.googleSub);
    if (existing) {
      if (google.email && !existing.email) {
        existing.email = google.email.toLowerCase();
      }
      if (fullName && !existing.fullName) {
        existing.fullName = fullName;
      }
      return existing;
    }

    const email = String(google.email || "").toLowerCase();
    const byEmail = google.emailVerified && email
      ? data.users.find((candidate) => candidate.email === email)
      : undefined;
    if (byEmail) {
      byEmail.googleSub = google.googleSub;
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
      appleSub: "",
      googleSub: google.googleSub,
      fullName,
      createdAt: new Date().toISOString()
    };
    data.users.push(created);
    return created;
  });

  sendJSON(response, 200, await issueSession(user));
}

async function refreshSession(request, response) {
  const body = await readJSON(request, 20_000);
  const oldToken = validRefreshToken(body.refreshToken);
  const newToken = newRefreshToken();
  const expiresAt = refreshExpiry();
  const userId = await store.rotateRefreshSession(
    hashRefreshToken(oldToken),
    hashRefreshToken(newToken),
    expiresAt
  );
  if (!userId) {
    throw new HttpError(401, "Your session has expired. Please sign in again.", { code: "REFRESH_TOKEN_INVALID" });
  }
  const user = (await store.snapshot()).users.find((candidate) => candidate.id === userId);
  if (!user) {
    throw new HttpError(401, "Your session has expired. Please sign in again.", { code: "REFRESH_TOKEN_INVALID" });
  }
  sendJSON(response, 200, sessionResponse(user, newToken));
}

async function logoutSession(request, response) {
  const body = await readJSON(request, 20_000);
  const refreshToken = validRefreshToken(body.refreshToken);
  await store.revokeRefreshSession(hashRefreshToken(refreshToken));
  sendJSON(response, 200, { success: true });
}

function socialSignInMessage(user) {
  if (user.appleSub) {
    return "Use Sign in with Apple for this account.";
  }
  if (user.googleSub) {
    return "Use Sign in with Google for this account.";
  }
  return "Use your social sign-in provider for this account.";
}

async function deleteAccount(request, response) {
  const auth = await authenticateRequest(request);
  const beforeDeletion = await store.snapshot();
  const user = beforeDeletion.users.find((candidate) => candidate.id === auth.sub);
  if (user?.appleRefreshToken) {
    try {
      await revokeAppleRefreshToken(user.appleRefreshToken);
    } catch (error) {
      // Apple instructs developers to complete deletion even if revocation
      // cannot be completed at that moment. Never log the token itself.
      logBackend("apple_token_revocation_failed", {
        userId: auth.sub,
        error: error.message || String(error)
      });
    }
  }
  const ownedUploads = beforeDeletion.uploads.filter((upload) => upload.userId === auth.sub);
  const ownedJobs = beforeDeletion.jobs.filter((job) => job.userId === auth.sub);
  const providerCancellationFailures = await cancelJobsForAccountDeletion(ownedJobs);
  for (const failure of providerCancellationFailures) {
    logBackend("account_deletion_provider_cancel_failed", {
      userId: auth.sub,
      jobId: failure.jobId,
      error: failure.error
    });
  }
  if (objectStorage.enabled) {
    await objectStorage.deleteKeys([
      ...ownedUploads.flatMap((upload) => [upload.s3Key, upload.clientS3Key]),
      ...ownedJobs.flatMap((job) => [
        job.imageObjectKey,
        job.videoObjectKey,
        ...(Array.isArray(job.videoClips) ? job.videoClips.map((clip) => clip.videoObjectKey) : [])
      ])
    ]);
  }

  const filesToDelete = await store.mutate(async (data) => {
    const uploads = data.uploads.filter((upload) => upload.userId === auth.sub);
    data.users = data.users.filter((user) => user.id !== auth.sub);
    data.uploads = data.uploads.filter((upload) => upload.userId !== auth.sub);
    data.jobs = data.jobs.filter((job) => job.userId !== auth.sub);
    data.usage = data.usage.filter((usage) => usage.userId !== auth.sub);
    data.creditAccounts = (data.creditAccounts || []).filter((entry) => entry.userId !== auth.sub);
    data.creditGrants = (data.creditGrants || []).filter((entry) => entry.userId !== auth.sub);
    data.creditLedger = (data.creditLedger || []).filter((entry) => entry.userId !== auth.sub);
    data.entitlements = (data.entitlements || []).filter((entry) => entry.userId !== auth.sub);
    data.sessions = (data.sessions || []).filter((entry) => entry.userId !== auth.sub);
    data.appStoreTransactions = (data.appStoreTransactions || []).map((entry) =>
      entry.userId === auth.sub ? { ...entry, userId: null, appAccountToken: null } : entry
    );
    return uploads.map((upload) => upload.localPath).filter(Boolean);
  });

  await Promise.all(filesToDelete.map((filePath) => fs.unlink(filePath).catch(() => {})));
  sendJSON(response, 200, { success: true });
}

function safePathname(rawURL) {
  try {
    return new URL(rawURL, config.publicBaseURL).pathname;
  } catch {
    return "invalid-url";
  }
}

async function sendInitialJobUpdate(jobId, userId, socket) {
  const data = await store.snapshot();
  const job = data.jobs.find((candidate) => candidate.jobId === jobId && candidate.userId === userId);
  if (!job) {
    socket.destroy();
    return;
  }

  if (job.status === "completed") {
    const resultURL = objectStorage.enabled && job.imageObjectKey
      ? await objectStorage.createDownloadURL(job.imageObjectKey)
      : job.imageURL;
    sendJobUpdate(socket, { type: "completed", resultURLs: resultURL ? [resultURL] : [], looks: [] });
  } else if (job.status === "failed") {
    sendJobUpdate(socket, { type: "failed", error: job.error || "Generation failed." });
  } else {
    sendJobUpdate(socket, { type: "progress", percent: job.progress });
  }
}

async function issueSession(user) {
  const refreshToken = newRefreshToken();
  await store.createRefreshSession(user.id, hashRefreshToken(refreshToken), refreshExpiry());
  return sessionResponse(user, refreshToken);
}

function sessionResponse(user, refreshToken) {
  return {
    userId: user.id,
    email: user.email || "",
    fullName: user.fullName || "",
    accessToken: signToken({ type: "access", sub: user.id, ver: Number(user.tokenVersion || 0) }),
    accessTokenExpiresIn: config.accessTokenTTLSeconds,
    refreshToken
  };
}

function newRefreshToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function hashRefreshToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

function refreshExpiry() {
  return new Date(Date.now() + config.refreshTokenTTLDays * 24 * 60 * 60_000).toISOString();
}

function validRefreshToken(value) {
  const token = String(value || "");
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
    throw new HttpError(401, "Your session has expired. Please sign in again.", { code: "REFRESH_TOKEN_INVALID" });
  }
  return token;
}

function logBackend(event, details = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event,
    ...details
  }));
}

async function enforceRateLimit(_request, scope, limit, windowMs, subject) {
  const subjectHash = crypto
    .createHmac("sha256", config.jwtSecret)
    .update(`${scope}\0${String(subject).slice(0, 256)}`)
    .digest("hex");
  const result = await store.consumeRateLimit(scope, subjectHash, limit, windowMs);
  if (!result.allowed) {
    const retryAfter = Math.max(1, Math.ceil((result.resetAt - Date.now()) / 1_000));
    throw new HttpError(429, "Too many requests. Please wait and try again.", {
      code: "RATE_LIMITED",
      headers: { "Retry-After": String(retryAfter) }
    });
  }
}

function clientAddress(request) {
  // Render's load balancer supplies the real client address first in
  // X-Forwarded-For. The service port is not directly internet-reachable.
  const forwarded = String(request.headers["x-forwarded-for"] || "")
    .split(",")[0]
    .trim();
  return forwarded || request.socket.remoteAddress || "unknown";
}

function accessTokenSubject(request) {
  const authorization = String(request.headers.authorization || "");
  const [scheme, token] = authorization.split(" ");
  if (scheme !== "Bearer" || !token) return null;
  try {
    return verifyToken(token, "access").sub || null;
  } catch {
    return null;
  }
}
