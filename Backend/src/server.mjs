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
  cancelSceneJob,
  createSceneJob,
  createVideoJob,
  getSceneJob,
  rerollSceneJob,
  sceneHistory
} from "./routes/generate.mjs";
import { servePrivacyPolicy, serveTermsOfUse } from "./routes/legal.mjs";
import { listScenes } from "./routes/scenes.mjs";
import { presignUpload, receiveUpload, serveUpload } from "./routes/upload.mjs";
import { store } from "./services/store-instance.mjs";
import { handleUpgrade, sendJobUpdate } from "./websocket.mjs";

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
  console.log(`SceneMe backend listening on ${config.publicBaseURL}`);
  console.log(`REST base: ${config.publicBaseURL}/v1`);
  console.log(`WebSocket base: ${config.publicBaseURL.replace(/^http/, "ws")}/ws`);
  logBackend("server_started", {
    port: config.port,
    publicBaseURL: config.publicBaseURL,
    falModel: config.ecoMode ? config.falEcoModel : config.falModel,
    falVideoModel: config.falVideoModel,
    ecoMode: config.ecoMode,
    reuseIdenticalResults: config.reuseIdenticalResults,
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

  if (request.method === "POST" && routePath === "/auth/google") {
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
      googleSub: "",
      fullName,
      createdAt: new Date().toISOString()
    };
    data.users.push(created);
    return created;
  });

  sendJSON(response, 200, userResponse(user));
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
    const byEmail = email ? data.users.find((candidate) => candidate.email === email) : undefined;
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

  sendJSON(response, 200, userResponse(user));
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

async function sendInitialJobUpdate(jobId, userId, socket) {
  const data = await store.snapshot();
  const job = data.jobs.find((candidate) => candidate.jobId === jobId && candidate.userId === userId);
  if (!job) {
    socket.destroy();
    return;
  }

  if (job.status === "completed") {
    sendJobUpdate(socket, { type: "completed", resultURLs: job.imageURL ? [job.imageURL] : [], looks: [] });
  } else if (job.status === "failed") {
    sendJobUpdate(socket, { type: "failed", error: job.error || "Generation failed." });
  } else {
    sendJobUpdate(socket, { type: "progress", percent: job.progress });
  }
}

function userResponse(user) {
  return {
    userId: user.id,
    email: user.email || "",
    fullName: user.fullName || "",
    accessToken: signToken({ type: "access", sub: user.id })
  };
}

function logBackend(event, details = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event,
    ...details
  }));
}
