import fs from "node:fs/promises";
import { fal } from "@fal-ai/client";
import { config } from "../config.mjs";

export class FalBillingError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = "FalBillingError";
    this.status = cause?.status || 403;
    this.requestId = cause?.requestId || "";
    this.body = cause?.body;
    this.cause = cause;
  }
}

// Multi-image kontext variant used when a companion photo is attached.
const MULTI_IMAGE_MODEL = process.env.FAL_MULTI_MODEL || "fal-ai/flux-pro/kontext/max/multi";

// How long an uploaded fal CDN URL stays reusable (uploads expire after 1 day).
const FAL_CDN_REUSE_MS = 20 * 60 * 60 * 1000;

export function isFalCdnURLFresh(uploadedAt) {
  if (!uploadedAt) {
    return false;
  }
  const age = Date.now() - new Date(uploadedAt).getTime();
  return Number.isFinite(age) && age >= 0 && age < FAL_CDN_REUSE_MS;
}

function imageModel() {
  return config.ecoMode ? config.falEcoModel : config.falModel;
}

export async function generateScene({
  imagePath,
  contentType = "image/jpeg",
  companionPath = null,
  companionContentType = "image/jpeg",
  originalPhotoURL,
  prompt,
  seed,
  jobId,
  cachedFalImageURL = null,
  onFalImageUploaded,
  onProgress
}) {
  if (config.enableMockGeneration) {
    logFal("mock_scene_generation", { jobId, prompt });
    await mockProgress(onProgress);
    return originalPhotoURL;
  }

  if (!config.falKey) {
    throw new Error("FAL_KEY is not configured.");
  }

  fal.config({ credentials: config.falKey });

  try {
    let userImageURL = cachedFalImageURL;
    if (userImageURL) {
      logFal("upload_reused_cdn_url", { jobId, imageHost: safeHost(userImageURL) });
    } else {
      logFal("upload_start", { jobId, contentType, hasCompanion: Boolean(companionPath) });
      userImageURL = await uploadToFalCdn({ imagePath, contentType });
      await onFalImageUploaded?.(userImageURL);
      logFal("upload_complete", { jobId, imageHost: safeHost(userImageURL) });
    }

    const companionImageURL = companionPath
      ? await uploadToFalCdn({ imagePath: companionPath, contentType: companionContentType })
      : null;
    onProgress?.(20);

    const imageURL = await runFalRequestWithFallback({
      prompt,
      userImageURL,
      companionImageURL,
      seed,
      jobId,
      onProgress
    });

    onProgress?.(95);
    return imageURL;
  } catch (error) {
    const operationalError = normalizeFalOperationalError(error);

    if (operationalError instanceof FalBillingError && config.fallbackToMockOnFalBilling) {
      logFal("mock_scene_billing_fallback", { jobId, ...serializeFalError(operationalError) });
      await mockProgress(onProgress);
      return originalPhotoURL;
    }

    throw operationalError;
  }
}

/// Animates a completed scene image into a short cinematic video.
export async function generateSceneVideo({ imageURL, prompt, jobId, onProgress }) {
  if (config.enableMockGeneration) {
    logFal("mock_video_generation", { jobId, prompt });
    await mockProgress(onProgress);
    return config.mockVideoURL;
  }

  if (!config.falKey) {
    throw new Error("FAL_KEY is not configured.");
  }

  fal.config({ credentials: config.falKey });

  try {
    return await runVideoRequest({ imageURL, prompt, jobId, onProgress });
  } catch (error) {
    const operationalError = normalizeFalOperationalError(error);

    if (operationalError instanceof FalBillingError && config.fallbackToMockOnFalBilling) {
      logFal("mock_video_billing_fallback", { jobId, ...serializeFalError(operationalError) });
      await mockProgress(onProgress);
      return config.mockVideoURL;
    }

    if (operationalError?.name === "ValidationError") {
      // Retry without optional tuning params in case the configured model
      // doesn't support duration/resolution inputs.
      logFal("video_retry_minimal_input", { jobId });
      return await runVideoRequest({ imageURL, prompt, jobId, onProgress, safeMode: true });
    }

    throw operationalError;
  }
}

async function runVideoRequest({ imageURL, prompt, jobId, onProgress, safeMode = false }) {
  const input = {
    image_url: imageURL,
    prompt
  };

  if (!safeMode) {
    input.duration = String(config.videoDurationSeconds);
    input.resolution = config.videoResolution;
  }

  logFal("video_start", {
    jobId,
    model: config.falVideoModel,
    duration: config.videoDurationSeconds,
    resolution: config.videoResolution,
    safeMode
  });

  const result = await fal.subscribe(config.falVideoModel, {
    input,
    logs: true,
    onQueueUpdate: (update) => {
      if (update.status === "IN_PROGRESS") {
        onProgress?.(60);
        logFal("video_queue_update", {
          jobId,
          status: update.status,
          log: update.logs?.at(-1)?.message || ""
        });
      }
    }
  });

  const videoURL = extractVideoURL(result?.data ?? result);
  if (!videoURL) {
    throw new Error("fal.ai video result did not include a video URL.");
  }

  return videoURL;
}

async function runFalRequest({ prompt, userImageURL, companionImageURL, seed, jobId, onProgress, safeMode = false }) {
  const isMulti = Boolean(companionImageURL);
  const model = isMulti ? MULTI_IMAGE_MODEL : imageModel();

  const input = isMulti
    ? { image_urls: [userImageURL, companionImageURL], prompt }
    : { image_url: userImageURL, prompt };

  if (!safeMode) {
    input.num_inference_steps = kontextSteps();
    input.guidance_scale = kontextGuidanceScale();
    if (Number.isFinite(seed)) {
      input.seed = seed;
    }
  }

  const result = await fal.subscribe(model, {
    input,
    logs: true,
    onQueueUpdate: (update) => {
      if (update.status === "IN_PROGRESS") {
        onProgress?.(60);
        logFal("queue_update", {
          jobId,
          model,
          status: update.status,
          log: update.logs?.at(-1)?.message || ""
        });
      }
    }
  });

  const outputImageURL = extractImageURL(result?.data ?? result);
  if (!outputImageURL) {
    throw new Error("fal.ai result did not include an image URL.");
  }

  return outputImageURL;
}

async function runFalRequestWithFallback(args) {
  try {
    return await runFalRequest(args);
  } catch (error) {
    const operationalError = normalizeFalOperationalError(error);
    logFal("scene_error", { jobId: args.jobId, ...serializeFalError(operationalError) });

    if (operationalError?.name !== "ValidationError") {
      throw operationalError;
    }

    logFal("scene_retry_minimal_input", { jobId: args.jobId });
    return await runFalRequest({ ...args, safeMode: true });
  }
}

async function uploadToFalCdn({ imagePath, contentType }) {
  const data = await fs.readFile(imagePath);
  const url = await fal.storage.upload(
    new Blob([data], { type: contentType }),
    { lifecycle: { expiresIn: "1d" } }
  );

  if (!url || typeof url !== "string") {
    throw new Error("fal.ai storage upload did not return a URL.");
  }

  return url;
}

async function mockProgress(onProgress) {
  for (const percent of [20, 45, 70, 90]) {
    onProgress?.(percent);
    await new Promise((resolve) => setTimeout(resolve, 600));
  }
}

function extractImageURL(result) {
  return result?.images?.[0]?.url || "";
}

function extractVideoURL(result) {
  return result?.video?.url || result?.videos?.[0]?.url || "";
}

function normalizeFalOperationalError(error) {
  if (isFalBillingError(error)) {
    return new FalBillingError(
      "fal.ai account is locked because the balance is exhausted. Top up your fal.ai balance, or enable STYLEAI_FAL_FALLBACK_TO_MOCK_ON_BILLING=true for local QA.",
      error
    );
  }

  return error;
}

function isFalBillingError(error) {
  const text = [
    error?.name,
    error?.message,
    typeof error?.body === "string" ? error.body : "",
    JSON.stringify(summarizeErrorBody(error?.body) || "")
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return error?.status === 403 && (
    text.includes("exhausted balance") ||
    text.includes("user is locked") ||
    text.includes("top up") ||
    text.includes("billing")
  );
}

function kontextSteps() {
  return numberFromEnv("FAL_KONTEXT_NUM_INFERENCE_STEPS", 28);
}

function kontextGuidanceScale() {
  return numberFromEnv("FAL_KONTEXT_GUIDANCE_SCALE", 3.5);
}

function numberFromEnv(key, fallback) {
  const parsed = Number(process.env[key]);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function logFal(event, details = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "fal",
    event,
    ...details
  }));
}

function safeHost(url) {
  try {
    return new URL(url).host;
  } catch {
    return "";
  }
}

export function serializeFalError(error) {
  return {
    name: error?.name || "",
    message: error?.message || String(error),
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

function summarizeErrorBody(body) {
  if (!body) {
    return undefined;
  }

  try {
    return JSON.parse(JSON.stringify(body)).detail || JSON.parse(JSON.stringify(body));
  } catch {
    return String(body).slice(0, 500);
  }
}
