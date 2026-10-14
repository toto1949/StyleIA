import crypto from "node:crypto";
import { authenticateRequest } from "../auth.mjs";
import { config } from "../config.mjs";
import { HttpError, readJSON, sendJSON } from "../http-utils.mjs";
import {
  cancelFalRequest,
  FalBillingError,
  generateScene,
  generateSceneVideo,
  isFalRequestPendingError,
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
  sanitizeDirectionNote,
  sanitizeSpokenLine,
  videoCacheKey
} from "../services/prompt-builder.mjs";
import { store } from "../services/store-instance.mjs";
import {
  appStoreTierForRequest,
  assertCostBudgetInStore,
  consumeCreditsInStore,
  generationCreditCosts,
  refundCreditsInStore,
  requireTier
} from "../services/app-store-service.mjs";
import { broadcastJobUpdate } from "../websocket.mjs";
import { findScene } from "./scenes.mjs";
import { assertSafeUserText } from "../services/content-safety-service.mjs";
import { objectStorage } from "../services/object-storage-service.mjs";
import { ensureUploadReady, ensureUploadSafeForGeneration, uploadInputURL } from "./upload.mjs";

const cancelledJobs = new Set();
const JOB_TYPES = new Set(["scene", "scene-video"]);

export async function cancelJobsForAccountDeletion(jobs) {
  const failures = [];
  for (const job of jobs.filter((candidate) =>
    JOB_TYPES.has(candidate.type) && ["pending", "processing"].includes(candidate.status)
  )) {
    cancelledJobs.add(job.jobId);
    if (!job.providerRequestId || !job.providerModel || config.enableMockGeneration) {
      continue;
    }
    try {
      await cancelFalRequest(job.providerModel, job.providerRequestId);
    } catch (error) {
      failures.push({ jobId: job.jobId, error: error?.message || String(error) });
    }
  }
  return failures;
}

export async function createSceneJob(request, response) {
  const auth = await authenticateRequest(request);
  const idempotencyKey = requireIdempotencyKey(request);
  const body = await readJSON(request);
  const tier = await appStoreTierForRequest(request, auth.sub);
  if (body.customScene || String(body.sceneId || "").startsWith("custom")) {
    requireTier(tier, "creator", "Custom scenes");
    await assertSafeUserText([
      body.customScene?.name,
      body.customScene?.basePrompt,
      body.customScene?.outfit
    ], auth.sub);
  }
  if (body.companionS3Key) {
    requireTier(tier, "pro", "Companion photos");
  }
  const job = await insertSceneJob(auth.sub, body, { reroll: false, tier, idempotencyKey });

  if (!job.idempotentReplay) {
    startGeneration(job.jobId);
  }
  sendJSON(response, 200, await sceneJobResponse(job));
}

export async function rerollSceneJob(request, response, sourceJobId) {
  const auth = await authenticateRequest(request);
  const idempotencyKey = requireIdempotencyKey(request);
  const tier = await appStoreTierForRequest(request, auth.sub);
  requireTier(tier, "creator", "Outfit re-roll");
  const body = await readJSON(request).catch(() => ({}));
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
    companionGender: source.companionGender,
    companionConsentConfirmed: body.companionConsentConfirmed === true,
    timeOfDay: source.timeOfDay,
    weather: source.weather,
    pose: source.pose,
    imageQuality: source.imageQuality || "standard"
  }, { reroll: true, tier, idempotencyKey });

  if (!job.idempotentReplay) {
    startGeneration(job.jobId);
  }
  sendJSON(response, 200, await sceneJobResponse(job));
}

/// Animates a completed scene image into a short video clip.
/// Body (optional): { motionStyle, spokenLine, directionNote }
/// Cache reuses only when the same director settings were used before.
export async function createVideoJob(request, response, sourceJobId) {
  const auth = await authenticateRequest(request);
  const idempotencyKey = requireIdempotencyKey(request);
  const tier = await appStoreTierForRequest(request, auth.sub);
  requireTier(tier, "pro", "Video Director");
  const body = await readJSON(request).catch(() => ({}));
  await assertSafeUserText([body.spokenLine, body.directionNote], auth.sub);
  const motionStyle = normalizeMotionStyle(body.motionStyle);
  const spokenLine = sanitizeSpokenLine(body.spokenLine);
  if (motionStyle === "talking" && !spokenLine) {
    throw new HttpError(400, "Talking videos require a spoken line.");
  }
  const directionNote = sanitizeDirectionNote(body.directionNote);
  const cacheKey = videoCacheKey(motionStyle, spokenLine, directionNote);

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

  // Prefer a matching clip from the library; fall back to the legacy single slot.
  const cachedClip = findCachedVideoClip(source, cacheKey);
  if (cachedClip?.videoURL) {
    const cached = {
      ...source,
      jobId: crypto.randomUUID(),
      type: "scene-video",
      sourceJobId,
      status: "completed",
      progress: 100,
      videoURL: cachedClip.videoURL,
      videoObjectKey: cachedClip.videoObjectKey || null,
      motionStyle: cachedClip.motionStyle || "cinematic",
      spokenLine: cachedClip.spokenLine || "",
      directionNote: cachedClip.directionNote || "",
      videoCacheKey: cachedClip.cacheKey || cacheKey,
      videoClips: normalizeVideoClips(source)
    };
    sendJSON(response, 200, await sceneJobResponse(cached));
    return;
  }

  const videoPrompt = buildVideoPrompt({
    scene: { base_prompt: source.basePrompt || source.sceneName || "the scene" },
    timeOfDay: source.timeOfDay,
    weather: source.weather,
    pose: source.pose,
    motionStyle,
    spokenLine,
    directionNote,
    hasCompanion: Boolean(source.companionS3Key),
    companionKind: source.companionKind || "friend",
    subjectGender: source.subjectGender || "auto",
    companionGender: source.companionGender || "auto"
  });

  const job = await store.mutate(async (current) => {
    const existing = current.jobs.find((candidate) =>
      candidate.userId === auth.sub
      && candidate.type === "scene-video"
      && candidate.idempotencyKey === idempotencyKey
    );
    if (existing) {
      return { ...existing, idempotentReplay: true };
    }
    const activeCount = current.jobs.filter((candidate) =>
      candidate.userId === auth.sub
      && candidate.type === "scene-video"
      && ["pending", "processing"].includes(candidate.status)
    ).length;
    if (activeCount >= config.maxConcurrentVideoJobsPerUser) {
      throw new HttpError(429, "A video is already processing for this account.");
    }
    const creditCost = motionStyle === "talking"
      ? generationCreditCosts.talkingVideo
      : generationCreditCosts.silentVideo;
    const estimatedCostUSD = motionStyle === "talking"
      ? config.estimatedTalkingVideoCostUSD
      : config.estimatedVideoCostUSD;
    assertCostBudgetInStore(current, auth.sub, estimatedCostUSD);
    const publicJobId = crypto.randomUUID();
    consumeCreditsInStore(current, auth.sub, {
      cost: creditCost,
      jobId: publicJobId,
      operation: motionStyle === "talking" ? "talking_video" : "silent_video"
    });
    const created = {
      id: crypto.randomUUID(),
      jobId: publicJobId,
      type: "scene-video",
      userId: auth.sub,
      idempotencyKey,
      estimatedCostUSD,
      creditCost,
      creditOperation: motionStyle === "talking" ? "talking_video" : "silent_video",
      creditRefunded: false,
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
      directionNote,
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
    return { ...created, idempotentReplay: false };
  });

  logScene("video_job_created", {
    jobId: job.jobId,
    sourceJobId,
    sceneId: job.sceneId,
    motionStyle,
    hasSpokenLine: Boolean(spokenLine),
    hasDirectionNote: Boolean(directionNote)
  });
  if (!job.idempotentReplay) {
    startVideoGeneration(job.jobId);
  }
  sendJSON(response, 200, await sceneJobResponse(job));
}

export async function getSceneJob(request, response, jobId) {
  const auth = await authenticateRequest(request);
  const data = await store.snapshot();
  const job = data.jobs.find(
    (candidate) => candidate.jobId === jobId && candidate.userId === auth.sub && JOB_TYPES.has(candidate.type)
  );

  if (!job) {
    throw new HttpError(404, "Job not found.");
  }

  sendJSON(response, 200, await sceneJobResponse(job));
}

export async function cancelSceneJob(request, response, jobId) {
  const auth = await authenticateRequest(request);
  const beforeDeletion = await store.snapshot();
  const ownedJob = beforeDeletion.jobs.find(
    (candidate) => candidate.jobId === jobId && candidate.userId === auth.sub && JOB_TYPES.has(candidate.type)
  );
  if (!ownedJob) {
    throw new HttpError(404, "Job not found.");
  }
  cancelledJobs.add(jobId);
  if (
    ["pending", "processing"].includes(ownedJob.status)
    && ownedJob.providerRequestId
    && ownedJob.providerModel
    && !config.enableMockGeneration
  ) {
    try {
      await cancelFalRequest(ownedJob.providerModel, ownedJob.providerRequestId);
      logScene("provider_job_cancel_requested", {
        jobId,
        phase: ownedJob.providerPhase || null,
        providerRequestId: ownedJob.providerRequestId
      });
    } catch (error) {
      cancelledJobs.delete(jobId);
      logScene("provider_job_cancel_failed", { jobId, ...serializeFalError(error) });
      throw new HttpError(502, "The provider could not confirm cancellation. Please retry.", {
        code: "PROVIDER_CANCEL_FAILED"
      });
    }
  }
  if (objectStorage.enabled) {
    await objectStorage.deleteKeys([
      ownedJob.imageObjectKey,
      ownedJob.videoObjectKey,
      ...(Array.isArray(ownedJob.videoClips)
        ? ownedJob.videoClips.map((clip) => clip.videoObjectKey)
        : [])
    ]);
  }

  await store.mutate(async (data) => {
    const index = data.jobs.findIndex(
      (candidate) => candidate.jobId === jobId && candidate.userId === auth.sub && JOB_TYPES.has(candidate.type)
    );
    if (index === -1) {
      throw new HttpError(404, "Job not found.");
    }
    const job = data.jobs[index];
    if (job.status !== "completed" && !job.creditRefunded) {
      refundCreditsInStore(data, auth.sub, {
        cost: job.creditCost,
        jobId: job.jobId,
        operation: job.creditOperation,
        reason: "user_cancelled"
      });
      job.creditRefunded = true;
    }
    data.jobs.splice(index, 1);
  });

  sendJSON(response, 200, { success: true });
}

export async function sceneHistory(request, response, url) {
  const auth = await authenticateRequest(request);
  const page = Math.max(1, Number.parseInt(url.searchParams.get("page") || "1", 10));
  const limit = Math.min(50, Math.max(1, Number.parseInt(url.searchParams.get("limit") || "20", 10)));
  const data = await store.snapshot();
  const completed = data.jobs
    .filter((job) => job.userId === auth.sub && job.type === "scene" && job.status === "completed")
    .sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime());
  const start = (page - 1) * limit;
  const items = await Promise.all(completed.slice(start, start + limit).map(sceneJobResponse));

  sendJSON(response, 200, { items, total: completed.length });
}

async function insertSceneJob(userId, body, { reroll, tier, idempotencyKey }) {
  const requestedS3Key = String(body.s3Key || "");
  const requestedCompanionS3Key = body.companionS3Key ? String(body.companionS3Key) : null;
  const requestedCompanionKind = normalizeCompanionKind(body.companionKind);
  if (
    requestedCompanionS3Key
    && requestedCompanionKind === "friend"
    && body.companionConsentConfirmed !== true
  ) {
    throw new HttpError(400, "Confirm that you have permission to use the companion photo.", {
      code: "COMPANION_CONSENT_REQUIRED"
    });
  }
  const preparedUpload = await ensureUploadReady(userId, requestedS3Key);
  const preparedCompanion = requestedCompanionS3Key
    ? await ensureUploadReady(userId, requestedCompanionS3Key)
    : null;
  const s3Key = preparedUpload.s3Key;
  const companionS3Key = preparedCompanion?.s3Key || null;
  const subjectInputURL = await uploadInputURL(preparedUpload);
  const companionInputURL = preparedCompanion
    ? await uploadInputURL(preparedCompanion)
    : null;
  await Promise.all([
    ensureUploadSafeForGeneration(userId, preparedUpload, subjectInputURL),
    preparedCompanion
      ? ensureUploadSafeForGeneration(userId, preparedCompanion, companionInputURL)
      : Promise.resolve()
  ]);
  const customScene = resolveCustomScene(body);
  const scene = customScene || await findScene(String(body.sceneId || ""));

  const subjectGender = normalizeSubjectGender(body.subjectGender);
  const timeOfDay = normalizeTimeOfDay(body.timeOfDay, scene);
  const weather = normalizeWeather(body.weather, scene);
  const pose = normalizePose(body.pose);
  const hasCompanion = Boolean(companionS3Key);
  const companionKind = requestedCompanionKind;
  // Friend gender is required for correct same-sex pairing; pets ignore this.
  const companionGender = companionKind === "pet"
    ? "auto"
    : normalizeSubjectGender(body.companionGender);

  if (hasCompanion && companionKind === "friend" && companionGender === "auto") {
    throw new HttpError(400, "Choose the friend's gender before generating.");
  }

  const prompt = buildPrompt({
    scene,
    timeOfDay,
    weather,
    pose,
    subjectGender,
    hasCompanion,
    companionKind,
    companionGender,
    reroll
  });
  const seed = Number.isFinite(Number(body.seed))
    ? Number(body.seed)
    : Math.floor(Math.random() * 1_000_000_000);

  const job = await store.mutate(async (data) => {
    const existing = data.jobs.find((candidate) =>
      candidate.userId === userId
      && candidate.type === "scene"
      && candidate.idempotencyKey === idempotencyKey
    );
    if (existing) {
      return { ...existing, idempotentReplay: true };
    }
    const activeCount = data.jobs.filter((candidate) =>
      candidate.userId === userId
      && candidate.type === "scene"
      && ["pending", "processing"].includes(candidate.status)
    ).length;
    if (activeCount >= config.maxConcurrentImageJobsPerUser) {
      throw new HttpError(429, "A scene is already processing for this account.");
    }
    const premiumImage = body.imageQuality === "premium";
    if (premiumImage) requireTier(tier, "pro", "Premium image quality");
    const creditCost = premiumImage
      ? generationCreditCosts.premiumImage
      : generationCreditCosts.standardImage;
    const estimatedCostUSD = premiumImage
      ? config.estimatedPremiumImageCostUSD
      : config.estimatedImageCostUSD;
    assertCostBudgetInStore(data, userId, estimatedCostUSD);
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

    const publicJobId = crypto.randomUUID();
    consumeCreditsInStore(data, userId, {
      cost: creditCost,
      jobId: publicJobId,
      operation: premiumImage ? "premium_image" : (reroll ? "reroll" : (hasCompanion ? "companion_image" : "standard_image"))
    });

    const created = {
      id: crypto.randomUUID(),
      jobId: publicJobId,
      type: "scene",
      userId,
      idempotencyKey,
      estimatedCostUSD,
      creditCost,
      creditOperation: premiumImage ? "premium_image" : (reroll ? "reroll" : (hasCompanion ? "companion_image" : "standard_image")),
      creditRefunded: false,
      imageQuality: premiumImage ? "premium" : "standard",
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
      companionGender,
      companionConsentConfirmed: hasCompanion && companionKind === "friend",
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
      originalPhotoURL: subjectInputURL || upload.publicURL,
      companionPhotoURL: companionInputURL,
      localPath: upload.localPath,
      contentType: upload.contentType || "image/jpeg",
      companionLocalPath: companionUpload?.localPath || null,
      companionContentType: companionUpload?.contentType || "image/jpeg",
      seed: reroll ? Math.floor(Math.random() * 1_000_000_000) : seed,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    data.jobs.push(created);
    return { ...created, idempotentReplay: false };
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

export async function recoverInterruptedJobs() {
  const data = await store.snapshot();
  const pending = data.jobs.filter((job) => job.status === "pending" && JOB_TYPES.has(job.type));
  const processing = data.jobs.filter((job) => job.status === "processing" && JOB_TYPES.has(job.type));
  const resumable = processing.filter((job) => job.providerRequestId && job.providerModel);
  const interrupted = processing.filter((job) => !job.providerRequestId || !job.providerModel);

  if (interrupted.length > 0) {
    await store.mutate(async (current) => {
      for (const interruptedJob of interrupted) {
        const job = current.jobs.find((candidate) => candidate.jobId === interruptedJob.jobId);
        if (!job || job.status !== "processing") {
          continue;
        }
        if (!job.creditRefunded) {
          refundCreditsInStore(current, job.userId, {
            cost: job.creditCost,
            jobId: job.jobId,
            operation: job.creditOperation,
            reason: "service_restart"
          });
          job.creditRefunded = true;
        }
        job.status = "failed";
        job.progress = 100;
        job.error = "Generation was interrupted by a service restart. Please retry; no credit was used.";
        job.updatedAt = new Date().toISOString();
      }
    });
  }

  for (const job of pending) {
    if (job.type === "scene-video") {
      startVideoGeneration(job.jobId);
    } else {
      startGeneration(job.jobId);
    }
  }
  for (const job of resumable) {
    if (job.type === "scene-video") {
      startVideoGeneration(job.jobId);
    } else {
      startGeneration(job.jobId);
    }
  }
  return {
    resumed: pending.length + resumable.length,
    resumedProviderRequests: resumable.length,
    failedSafely: interrupted.length
  };
}

function requireIdempotencyKey(request) {
  const value = String(request.headers["idempotency-key"] || "").trim().toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    throw new HttpError(400, "A valid Idempotency-Key header is required.");
  }
  return value;
}

function resolveCustomScene(body) {
  const raw = body.customScene;
  const sceneId = String(body.sceneId || "");
  const isCustomRequest = Boolean(raw)
    || sceneId === "custom"
    || sceneId.startsWith("custom-");

  if (!isCustomRequest) {
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

  // Keep the client's unique custom-* id so the app can reuse saved templates.
  if (sceneId.startsWith("custom-")) {
    scene.id = sceneId;
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
    const resumeProvider = providerResumeState(job);
    const reused = !resumeProvider && !job.isReroll && config.reuseIdenticalResults
      ? await findReusableResult(job)
      : null;

    let imageURL;
    let imageObjectKey = null;
    if (reused) {
      logScene("scene_job_reused_result", { jobId, reusedFromJobId: reused.jobId });
      imageObjectKey = reused.imageObjectKey || null;
      imageURL = imageObjectKey
        ? await objectStorage.createDownloadURL(imageObjectKey)
        : reused.imageURL;
    } else {
      const providerImageURL = await generateScene({
        imagePath: job.localPath,
        contentType: job.contentType,
        companionPath: job.companionLocalPath,
        companionContentType: job.companionContentType,
        originalPhotoURL: job.originalPhotoURL,
        companionPhotoURL: job.companionPhotoURL,
        prompt: job.prompt,
        seed: job.seed,
        imageQuality: job.imageQuality || "standard",
        jobId,
        cachedFalImageURL: await freshFalCdnURL(job.userId, job.s3Key),
        cachedCompanionFalImageURL: job.companionS3Key
          ? await freshFalCdnURL(job.userId, job.companionS3Key)
          : null,
        onFalImageUploaded: (url) => rememberFalCdnURL(job.userId, job.s3Key, url),
        onCompanionFalImageUploaded: job.companionS3Key
          ? (url) => rememberFalCdnURL(job.userId, job.companionS3Key, url)
          : undefined,
        onProviderState: (state) => persistProviderState(jobId, state),
        resumeProvider,
        onProgress: (percent) => updateProgress(jobId, percent)
      });
      if (cancelledJobs.has(jobId)) {
        cancelledJobs.delete(jobId);
        logScene("scene_job_cancelled_before_result_ingestion", { jobId });
        return;
      }
      if (objectStorage.enabled) {
        const stored = await objectStorage.ingestProviderResult({
          userId: job.userId,
          jobId,
          kind: "image",
          sourceURL: providerImageURL
        });
        imageObjectKey = stored.key;
        imageURL = await objectStorage.createDownloadURL(stored.key);
      } else {
        imageURL = providerImageURL;
      }
    }

    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      if (imageObjectKey) {
        await objectStorage.deleteKeys([imageObjectKey]);
      }
      logScene("scene_job_cancelled_after_generation", { jobId });
      return;
    }

    await transitionJob(jobId, {
      status: "completed",
      progress: 100,
      imageURL,
      imageObjectKey,
      actualCostUSD: reused ? 0 : job.estimatedCostUSD,
      estimatedCostUSD: reused ? 0 : job.estimatedCostUSD,
      error: ""
    });
    logScene("scene_job_completed", { jobId, durationMs: Date.now() - startedAt, reused: Boolean(reused) });
    broadcastJobUpdate(jobId, { type: "completed", resultURLs: [imageURL], looks: [] });
  } catch (error) {
    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logScene("scene_job_cancelled_after_error", { jobId });
      return;
    }

    if (isFalRequestPendingError(error)) {
      logScene("scene_job_provider_still_running", {
        jobId,
        providerRequestId: error.requestId,
        providerModel: error.model,
        providerPhase: error.phase
      });
      scheduleGenerationRetry(jobId, "scene");
      return;
    }

    logScene("scene_job_failed", { jobId, durationMs: Date.now() - startedAt, ...serializeFalError(error) });
    const publicError = error instanceof FalBillingError
      ? error.message
      : error?.message || "Scene generation failed. Your credits have not been used.";

    await store.mutate(async (data) => {
      const failed = data.jobs.find((candidate) => candidate.jobId === jobId);
      if (!failed) {
        return;
      }
      if (!failed.creditRefunded) {
        refundCreditsInStore(data, failed.userId, {
          cost: failed.creditCost,
          jobId: failed.jobId,
          operation: failed.creditOperation,
          reason: "generation_failed"
        });
        failed.creditRefunded = true;
      }
      Object.assign(failed, {
        status: "failed",
        progress: 100,
        imageURL: "",
        error: publicError,
        updatedAt: new Date().toISOString()
      });
    });
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
    const providerVideoURL = await generateSceneVideo({
      imageURL: job.sourceImageURL,
      prompt: job.prompt,
      jobId,
      spokenLine: job.spokenLine || "",
      subjectGender: job.subjectGender || "auto",
      motionStyle: job.motionStyle || "cinematic",
      onProviderState: (state) => persistProviderState(jobId, state),
      resumeProvider: providerResumeState(job),
      onProgress: (percent) => updateProgress(jobId, percent)
    });
    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      logScene("video_job_cancelled_before_result_ingestion", { jobId });
      return;
    }
    let videoURL = providerVideoURL;
    let videoObjectKey = null;
    if (objectStorage.enabled) {
      const stored = await objectStorage.ingestProviderResult({
        userId: job.userId,
        jobId,
        kind: "video",
        sourceURL: providerVideoURL
      });
      videoObjectKey = stored.key;
      videoURL = await objectStorage.createDownloadURL(stored.key);
    }

    if (cancelledJobs.has(jobId)) {
      cancelledJobs.delete(jobId);
      if (videoObjectKey) {
        await objectStorage.deleteKeys([videoObjectKey]);
      }
      logScene("video_job_cancelled_after_generation", { jobId });
      return;
    }

    await transitionJob(jobId, {
      status: "completed",
      progress: 100,
      videoURL,
      videoObjectKey,
      actualCostUSD: job.estimatedCostUSD,
      providerIntermediateVideoURL: null,
      providerIntermediateAudioURL: null,
      error: ""
    });

    // Upsert into the source scene's clip library so Talking + Cinematic + …
    // can all be replayed later without losing prior directions.
    await store.mutate(async (data) => {
      const source = data.jobs.find((candidate) => candidate.jobId === job.sourceJobId);
      if (source) {
        const clip = {
          cacheKey: job.videoCacheKey || videoCacheKey(job.motionStyle, job.spokenLine, job.directionNote),
          motionStyle: job.motionStyle || "cinematic",
          spokenLine: job.spokenLine || "",
          directionNote: job.directionNote || "",
          videoURL,
          videoObjectKey,
          createdAt: new Date().toISOString()
        };
        source.videoClips = upsertVideoClip(normalizeVideoClips(source), clip);
        source.videoURL = videoURL;
        source.videoMotionStyle = clip.motionStyle;
        source.videoSpokenLine = clip.spokenLine;
        source.videoCacheKey = clip.cacheKey;
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

    if (isFalRequestPendingError(error)) {
      logScene("video_job_provider_still_running", {
        jobId,
        providerRequestId: error.requestId,
        providerModel: error.model,
        providerPhase: error.phase
      });
      scheduleGenerationRetry(jobId, "video");
      return;
    }

    logScene("video_job_failed", { jobId, durationMs: Date.now() - startedAt, ...serializeFalError(error) });
    const publicError = error instanceof FalBillingError
      ? error.message
      : error?.message || "Video generation failed. Your credits have not been used.";

    await store.mutate(async (data) => {
      const failed = data.jobs.find((candidate) => candidate.jobId === jobId);
      if (!failed) return;
      if (!failed.creditRefunded) {
        refundCreditsInStore(data, failed.userId, {
          cost: failed.creditCost,
          jobId: failed.jobId,
          operation: failed.creditOperation,
          reason: "generation_failed"
        });
        failed.creditRefunded = true;
      }
      Object.assign(failed, {
        status: "failed",
        progress: 100,
        videoURL: "",
        error: publicError,
        updatedAt: new Date().toISOString()
      });
    });
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
    (candidate.companionKind || "friend") === (job.companionKind || "friend") &&
    (candidate.companionGender || "auto") === (job.companionGender || "auto") &&
    (candidate.subjectGender || "auto") === (job.subjectGender || "auto") &&
    candidate.prompt === job.prompt
  ) || null;
}

async function freshFalCdnURL(userId, s3Key) {
  if (!s3Key) {
    return null;
  }

  const data = await store.snapshot();
  const upload = data.uploads.find(
    (candidate) => candidate.userId === userId && candidate.s3Key === s3Key
  );

  return upload && upload.falImageURL && isFalCdnURLFresh(upload.falUploadedAt)
    ? upload.falImageURL
    : null;
}

async function rememberFalCdnURL(userId, s3Key, url) {
  if (!s3Key || !url) {
    return;
  }

  await store.mutate(async (data) => {
    const upload = data.uploads.find(
      (candidate) => candidate.userId === userId && candidate.s3Key === s3Key
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

function providerResumeState(job) {
  if (!job?.providerRequestId || !job?.providerModel) {
    return null;
  }
  return {
    requestId: job.providerRequestId,
    model: job.providerModel,
    phase: job.providerPhase || (job.type === "scene-video" ? "video" : "scene"),
    intermediateVideoURL: job.providerIntermediateVideoURL || null,
    intermediateAudioURL: job.providerIntermediateAudioURL || null
  };
}

async function persistProviderState(jobId, state) {
  const patch = {};
  if (state.requestId) patch.providerRequestId = state.requestId;
  if (state.model) patch.providerModel = state.model;
  if (state.phase) patch.providerPhase = state.phase;
  if (Object.hasOwn(state, "intermediateVideoURL")) {
    patch.providerIntermediateVideoURL = state.intermediateVideoURL;
  }
  if (Object.hasOwn(state, "intermediateAudioURL")) {
    patch.providerIntermediateAudioURL = state.intermediateAudioURL;
  }
  await transitionJob(jobId, patch);
}

function scheduleGenerationRetry(jobId, kind) {
  const timer = setTimeout(() => {
    if (kind === "video") {
      startVideoGeneration(jobId);
    } else {
      startGeneration(jobId);
    }
  }, 15_000);
  timer.unref?.();
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

async function sceneJobResponse(job) {
  const imageURL = objectStorage.enabled && job.imageObjectKey
    ? await objectStorage.createDownloadURL(job.imageObjectKey)
    : job.imageURL || null;
  const videoURL = objectStorage.enabled && job.videoObjectKey
    ? await objectStorage.createDownloadURL(job.videoObjectKey)
    : job.videoURL || null;
  const clips = await Promise.all(normalizeVideoClips(job).map(async (clip) => ({
    ...clip,
    videoURL: objectStorage.enabled && clip.videoObjectKey
      ? await objectStorage.createDownloadURL(clip.videoObjectKey)
      : clip.videoURL
  })));
  return {
    jobId: job.jobId,
    kind: job.type === "scene-video" ? "video" : "image",
    status: job.status,
    progress: job.progress,
    imageURL,
    videoURL,
    videoClips: clips,
    sourceJobId: job.sourceJobId || null,
    sceneId: job.sceneId,
    sceneName: job.sceneName || "",
    sceneLocation: job.sceneLocation || "",
    subjectGender: job.subjectGender || "auto",
    companionKind: job.companionKind || null,
    companionGender: job.companionGender || "auto",
    timeOfDay: job.timeOfDay,
    weather: job.weather,
    pose: job.pose,
    hasCompanion: Boolean(job.companionS3Key),
    isReroll: Boolean(job.isReroll),
    motionStyle: job.motionStyle || job.videoMotionStyle || null,
    spokenLine: job.spokenLine || job.videoSpokenLine || null,
    directionNote: job.directionNote || null,
    prompt: job.prompt,
    createdAt: job.createdAt,
    error: job.error || null
  };
}

const MAX_VIDEO_CLIPS = 4;

function normalizeVideoClips(job) {
  const clips = Array.isArray(job?.videoClips)
    ? job.videoClips.filter((clip) => clip?.videoURL && clip?.cacheKey)
    : [];

  if (clips.length > 0) {
    return clips.slice(0, MAX_VIDEO_CLIPS);
  }

  // Legacy single-slot scenes: surface as a one-item library.
  if (job?.videoURL) {
    return [{
      cacheKey: job.videoCacheKey || videoCacheKey(job.videoMotionStyle || "cinematic", job.videoSpokenLine || "", job.directionNote || ""),
      motionStyle: job.videoMotionStyle || job.motionStyle || "cinematic",
      spokenLine: job.videoSpokenLine || job.spokenLine || "",
      directionNote: job.directionNote || "",
      videoURL: job.videoURL,
      createdAt: job.updatedAt || job.createdAt || new Date().toISOString()
    }];
  }

  return [];
}

function findCachedVideoClip(source, cacheKey) {
  return normalizeVideoClips(source).find((clip) => clip.cacheKey === cacheKey) || null;
}

function upsertVideoClip(clips, clip) {
  const next = clips.filter((candidate) => candidate.cacheKey !== clip.cacheKey);
  next.unshift(clip);
  return next.slice(0, MAX_VIDEO_CLIPS);
}

function logScene(event, details = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event,
    ...details
  }));
}
