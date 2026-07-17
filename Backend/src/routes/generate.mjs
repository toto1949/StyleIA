import crypto from "node:crypto";
import { authenticateRequest } from "../auth.mjs";
import { config } from "../config.mjs";
import { HttpError, readJSON, sendJSON } from "../http-utils.mjs";
import {
  FalBillingError,
  generateScene,
  generateSceneVideo,
  isFalCdnURLFresh,
  serializeFalError
} from "../services/fal-service.mjs";
import {
  buildCustomScene,
  buildPrompt,
  buildVideoPrompt,
  normalizeCompanionKind,
  normalizeMotionStyle,
  normalizePose,
  normalizeSubjectGender,
  normalizeTimeOfDay,
  normalizeWeather,
  sanitizeSpokenLine,
  videoCacheKey
} from "../services/prompt-builder.mjs";
import { store } from "../services/store-instance.mjs";
import { broadcastJobUpdate } from "../websocket.mjs";
import { findScene } from "./scenes.mjs";

const cancelledJobs = new Set();
const JOB_TYPES = new Set(["scene", "scene-video"]);

export async function createSceneJob(request, response) {
  const auth = authenticateRequest(request);
  const body = await readJSON(request);
  const job = await insertSceneJob(auth.sub, body, { reroll: false });

  startGeneration(job.jobId);
  sendJSON(response, 200, sceneJobResponse(job));
}

export async function rerollSceneJob(request, response, sourceJobId) {
  const auth = authenticateRequest(request);
  const data = await store.snapshot();
  const source = data.jobs.find(
    (candidate) => candidate.jobId === sourceJobId && candidate.userId === auth.sub && candidate.type === "scene"
  );

  if (!source) {
    throw new HttpError(404, "Job not found.");
  }

  const job = await insertSceneJob(auth.sub, {
    s3Key: source.s3Key,
    companionS3Key: source.companionS3Key || null,
    sceneId: source.sceneId,
    customScene: source.customScene || null,
    subjectGender: source.subjectGender,
    companionKind: source.companionKind,
    timeOfDay: source.timeOfDay,
    weather: source.weather,
    pose: source.pose
  }, { reroll: true });

  startGeneration(job.jobId);
  sendJSON(response, 200, sceneJobResponse(job));
}

/// Animates a completed scene image into a short video clip.
/// Body (optional): { motionStyle, spokenLine }
/// Cache reuses only when the same director settings were used before.
export async function createVideoJob(request, response, sourceJobId) {
  const auth = authenticateRequest(request);
  const body = await readJSON(request).catch(() => ({}));
  const motionStyle = normalizeMotionStyle(body.motionStyle);
  const spokenLine = sanitizeSpokenLine(body.spokenLine);
  const cacheKey = videoCacheKey(motionStyle, spokenLine);

  const data = await store.snapshot();
  const source = data.jobs.find(
    (candidate) => candidate.jobId === sourceJobId && candidate.userId === auth.sub && candidate.type === "scene"
  );

  if (!source) {
    throw new HttpError(404, "Job not found.");
  }
  if (source.status !== "completed" || !source.imageURL) {
    throw new HttpError(409, "Scene must finish generating before it can be animated.");
  }

  // Reuse only when director settings match the cached clip.
  const cachedKey = source.videoCacheKey || videoCacheKey("cinematic", "");
  if (source.videoURL && cachedKey === cacheKey) {
    const cached = {
      ...source,
      jobId: crypto.randomUUID(),
      type: "scene-video",
      sourceJobId,
      status: "completed",
      progress: 100,
      videoURL: source.videoURL,
      motionStyle: source.videoMotionStyle || "cinematic",
      spokenLine: source.videoSpokenLine || "",
      videoCacheKey: cachedKey
    };
    sendJSON(response, 200, sceneJobResponse(cached));
    return;
  }

  const videoPrompt = buildVideoPrompt({
    scene: { base_prompt: source.basePrompt || source.sceneName || "the scene" },
    timeOfDay: source.timeOfDay,
    weather: source.weather,
    pose: source.pose,
    motionStyle,
    spokenLine
  });

  const job = await store.mutate(async (current) => {
    const created = {
      id: crypto.randomUUID(),
      jobId: crypto.randomUUID(),
      type: "scene-video",
      userId: auth.sub,
      sourceJobId,
      sceneId: source.sceneId,
      sceneName: source.sceneName,
      sceneLocation: source.sceneLocation,
      timeOfDay: source.timeOfDay,
      weather: source.weather,
      pose: source.pose,
      subjectGender: source.subjectGender || "auto",
      motionStyle,
      spokenLine,
      videoCacheKey: cacheKey,
      prompt: videoPrompt,
      sourceImageURL: source.imageURL,
      status: "pending",
      progress: 0,
      imageURL: source.imageURL,
      videoURL: "",
      error: "",
      originalPhotoURL: source.originalPhotoURL,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    current.jobs.push(created);
    return created;
  });

  logScene("video_job_created", {
    jobId: job.jobId,
    sourceJobId,
    sceneId: job.sceneId,
    motionStyle,
    hasSpokenLine: Boolean(spokenLine)
  });
  startVideoGeneration(job.jobId);
  sendJSON(response, 200, sceneJobResponse(job));
}

export async function getSceneJob(request, response, jobId) {
  const auth = authenticateRequest(request);
  const data = await store.snapshot();
  const job = data.jobs.find(
    (candidate) => candidate.jobId === jobId && candidate.userId === auth.sub && JOB_TYPES.has(candidate.type)
  );

  if (!job) {
    throw new HttpError(404, "Job not found.");
  }

  sendJSON(response, 200, sceneJobResponse(job));
}

export async function cancelSceneJob(request, response, jobId) {
  const auth = authenticateRequest(request);
  cancelledJobs.add(jobId);

  await store.mutate(async (data) => {
    const index = data.jobs.findIndex(
      (candidate) => candidate.jobId === jobId && candidate.userId === auth.sub && JOB_TYPES.has(candidate.type)
    );
    if (index === -1) {
      throw new HttpError(404, "Job not found.");
    }
    data.jobs.splice(index, 1);
  });

  sendJSON(response, 200, { success: true });
}

export async function sceneHistory(request, response, url) {
  const auth = authenticateRequest(request);
  const page = Math.max(1, Number.parseInt(url.searchParams.get("page") || "1", 10));
  const limit = Math.min(50, Math.max(1, Number.parseInt(url.searchParams.get("limit") || "20", 10)));
  const data = await store.snapshot();
  const completed = data.jobs
    .filter((job) => job.userId === auth.sub && job.type === "scene" && job.status === "completed")
    .sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime());
  const start = (page - 1) * limit;
  const items = completed.slice(start, start + limit).map(sceneJobResponse);

  sendJSON(response, 200, { items, total: completed.length });
}

async function insertSceneJob(userId, body, { reroll }) {
  const s3Key = String(body.s3Key || "");
  const companionS3Key = body.companionS3Key ? String(body.companionS3Key) : null;
  const customScene = resolveCustomScene(body);
  const scene = customScene || await findScene(String(body.sceneId || ""));

  const subjectGender = normalizeSubjectGender(body.subjectGender);
  const timeOfDay = normalizeTimeOfDay(body.timeOfDay, scene);
  const weather = normalizeWeather(body.weather, scene);
  const pose = normalizePose(body.pose);
  const hasCompanion = Boolean(companionS3Key);
  const companionKind = normalizeCompanionKind(body.companionKind);

  const prompt = buildPrompt({ scene, timeOfDay, weather, pose, subjectGender, hasCompanion, companionKind, reroll });
  const seed = Number.isFinite(Number(body.seed))
    ? Number(body.seed)
    : Math.floor(Math.random() * 1_000_000_000);

  const job = await store.mutate(async (data) => {
    const upload = data.uploads.find(
      (candidate) => candidate.userId === userId && candidate.s3Key === s3Key && candidate.status === "uploaded"
    );

    if (!upload) {
      throw new HttpError(404, "Uploaded image not found.");
    }

    let companionUpload = null;
    if (companionS3Key) {
      companionUpload = data.uploads.find(
        (candidate) => candidate.userId === userId && candidate.s3Key === companionS3Key && candidate.status === "uploaded"
      );
      if (!companionUpload) {
        throw new HttpError(404, "Companion image not found.");
      }
    }

    const created = {
      id: crypto.randomUUID(),
      jobId: crypto.randomUUID(),
      type: "scene",
      userId,
      s3Key,
      companionS3Key,
      sceneId: scene.id,
      sceneName: scene.name,
      sceneLocation: scene.location,
      basePrompt: scene.base_prompt,
      customScene: customScene
        ? { name: customScene.name, basePrompt: customScene.base_prompt, outfit: customScene.default_outfit }
        : null,
      subjectGender,
      companionKind,
      timeOfDay,
      weather,
      pose,
      isReroll: reroll,
      prompt,
      status: "pending",
      progress: 0,
      imageURL: "",
      videoURL: "",
      error: "",
      originalPhotoURL: upload.publicURL,
      localPath: upload.localPath,
      contentType: upload.contentType || "image/jpeg",
      companionLocalPath: companionUpload?.localPath || null,
      companionContentType: companionUpload?.contentType || "image/jpeg",
      seed: reroll ? Math.floor(Math.random() * 1_000_000_000) : seed,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    data.jobs.push(created);
    return created;
  });

  logScene("scene_job_created", {
    jobId: job.jobId,
    userId,
    sceneId: job.sceneId,
    subjectGender,
    timeOfDay,
    weather,
    pose,
    hasCompanion,
    isCustomScene: Boolean(customScene),
    reroll
  });

  return job;
}

function resolveCustomScene(body) {
  const raw = body.customScene;
  if (!raw && String(body.sceneId || "") !== "custom") {
    return null;
  }

  const scene = buildCustomScene({
    name: raw?.name,
    basePrompt: raw?.basePrompt || raw?.base_prompt,
    outfit: raw?.outfit
  });

  if (!scene) {
    throw new HttpError(400, "Custom scene needs a description of at least a few words.");
  }

  return scene;
}

function startGeneration(jobId) {
  runSceneGeneration(jobId).catch((error) => {
    logScene("scene_job_background_error", { jobId, error: error.message || String(error) });
  });
}

function startVideoGeneration(jobId) {
  runVideoGeneration(jobId).catch((error) => {
    logScene("video_job_background_error", { jobId, error: error.message || String(error) });
  });
}

async function runSceneGeneration(jobId) {
  const job = await transitionJob(jobId, { status: "processing", progress: 5 });
  if (!job) {
    logScene("scene_job_missing_on_start", { jobId });
    return;
  }

  const startedAt = Date.now();
  broadcastJobUpdate(jobId, { type: "progress", percent: 5 });

  try {
    // Cost saver: identical photo + prompt already generated for this user
    // means we can reuse the result without paying fal again. Rerolls always
    // regenerate since the point is a different output.
    const reused = !job.isReroll && config.reuseIdenticalResults
      ? await findReusableResult(job)
      : null;

    let imageURL;
    if (reused) {
      logScene("scene_job_reused_result", { jobId, reusedFromJobId: reused.jobId });
      imageURL = reused.imageURL;
    } else {
      imageURL = await generateScene({
        imagePath: job.localPath,
        contentType: job.contentType,
        companionPath: job.companionLocalPath,
        companionContentType: job.companionContentType,
        originalPhotoURL: job.originalPhotoURL,
        prompt: job.prompt,
        seed: job.seed,
        jobId,
        cachedFalImageURL: await freshFalCdnURL(job),
        onFalImageUploaded: (url) => rememberFalCdnURL(job, url),
        onProgress: (percent) => updateProgress(jobId, percent)
      });
    }

    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logScene("scene_job_cancelled_after_generation", { jobId });
      return;
    }

    await transitionJob(jobId, { status: "completed", progress: 100, imageURL, error: "" });
    logScene("scene_job_completed", { jobId, durationMs: Date.now() - startedAt, reused: Boolean(reused) });
    broadcastJobUpdate(jobId, { type: "completed", resultURLs: [imageURL], looks: [] });
  } catch (error) {
    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logScene("scene_job_cancelled_after_error", { jobId });
      return;
    }

    logScene("scene_job_failed", { jobId, durationMs: Date.now() - startedAt, ...serializeFalError(error) });
    const publicError = error instanceof FalBillingError
      ? error.message
      : error?.message || "Scene generation failed. Your credits have not been used.";

    await transitionJob(jobId, { status: "failed", progress: 100, imageURL: "", error: publicError });
    broadcastJobUpdate(jobId, { type: "failed", error: publicError });
  }
}

async function runVideoGeneration(jobId) {
  const job = await transitionJob(jobId, { status: "processing", progress: 5 });
  if (!job) {
    logScene("video_job_missing_on_start", { jobId });
    return;
  }

  const startedAt = Date.now();
  broadcastJobUpdate(jobId, { type: "progress", percent: 5 });

  try {
    const videoURL = await generateSceneVideo({
      imageURL: job.sourceImageURL,
      prompt: job.prompt,
      jobId,
      onProgress: (percent) => updateProgress(jobId, percent)
    });

    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logScene("video_job_cancelled_after_generation", { jobId });
      return;
    }

    await transitionJob(jobId, { status: "completed", progress: 100, videoURL, error: "" });

    // Persist the video + director settings onto the source scene job so
    // matching re-animates reuse the clip (and history can show the caption).
    await store.mutate(async (data) => {
      const source = data.jobs.find((candidate) => candidate.jobId === job.sourceJobId);
      if (source) {
        source.videoURL = videoURL;
        source.videoMotionStyle = job.motionStyle || "cinematic";
        source.videoSpokenLine = job.spokenLine || "";
        source.videoCacheKey = job.videoCacheKey || videoCacheKey(job.motionStyle, job.spokenLine);
        source.updatedAt = new Date().toISOString();
      }
    });

    logScene("video_job_completed", { jobId, durationMs: Date.now() - startedAt });
    broadcastJobUpdate(jobId, { type: "completed", resultURLs: [videoURL], looks: [] });
  } catch (error) {
    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logScene("video_job_cancelled_after_error", { jobId });
      return;
    }

    logScene("video_job_failed", { jobId, durationMs: Date.now() - startedAt, ...serializeFalError(error) });
    const publicError = error instanceof FalBillingError
      ? error.message
      : error?.message || "Video generation failed. Your credits have not been used.";

    await transitionJob(jobId, { status: "failed", progress: 100, videoURL: "", error: publicError });
    broadcastJobUpdate(jobId, { type: "failed", error: publicError });
  }
}

async function findReusableResult(job) {
  const data = await store.snapshot();
  return data.jobs.find((candidate) =>
    candidate.jobId !== job.jobId &&
    candidate.userId === job.userId &&
    candidate.type === "scene" &&
    candidate.status === "completed" &&
    Boolean(candidate.imageURL) &&
    candidate.s3Key === job.s3Key &&
    (candidate.companionS3Key || null) === (job.companionS3Key || null) &&
    candidate.prompt === job.prompt
  ) || null;
}

async function freshFalCdnURL(job) {
  if (job.companionLocalPath) {
    return null;
  }

  const data = await store.snapshot();
  const upload = data.uploads.find(
    (candidate) => candidate.userId === job.userId && candidate.s3Key === job.s3Key
  );

  return upload && upload.falImageURL && isFalCdnURLFresh(upload.falUploadedAt)
    ? upload.falImageURL
    : null;
}

async function rememberFalCdnURL(job, url) {
  await store.mutate(async (data) => {
    const upload = data.uploads.find(
      (candidate) => candidate.userId === job.userId && candidate.s3Key === job.s3Key
    );
    if (upload) {
      upload.falImageURL = url;
      upload.falUploadedAt = new Date().toISOString();
    }
  });
}

async function updateProgress(jobId, percent) {
  if (cancelledJobs.has(jobId)) {
    return;
  }

  const bounded = Math.max(0, Math.min(99, Math.round(percent)));
  await transitionJob(jobId, { status: "processing", progress: bounded });
  broadcastJobUpdate(jobId, { type: "progress", percent: bounded });
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

function sceneJobResponse(job) {
  return {
    jobId: job.jobId,
    kind: job.type === "scene-video" ? "video" : "image",
    status: job.status,
    progress: job.progress,
    imageURL: job.imageURL || null,
    videoURL: job.videoURL || null,
    sourceJobId: job.sourceJobId || null,
    sceneId: job.sceneId,
    sceneName: job.sceneName || "",
    sceneLocation: job.sceneLocation || "",
    subjectGender: job.subjectGender || "auto",
    timeOfDay: job.timeOfDay,
    weather: job.weather,
    pose: job.pose,
    hasCompanion: Boolean(job.companionS3Key),
    isReroll: Boolean(job.isReroll),
    motionStyle: job.motionStyle || job.videoMotionStyle || null,
    spokenLine: job.spokenLine || job.videoSpokenLine || null,
    prompt: job.prompt,
    originalPhotoURL: job.originalPhotoURL || null,
    createdAt: job.createdAt,
    error: job.error || null
  };
}

function logScene(event, details = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event,
    ...details
  }));
}
