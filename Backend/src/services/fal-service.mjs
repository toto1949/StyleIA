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
  cachedCompanionFalImageURL = null,
  onFalImageUploaded,
  onCompanionFalImageUploaded,
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
      logFal("upload_reused_cdn_url", { jobId, role: "subject", imageHost: safeHost(userImageURL) });
    } else {
      logFal("upload_start", { jobId, role: "subject", contentType, hasCompanion: Boolean(companionPath) });
      userImageURL = await uploadToFalCdn({ imagePath, contentType });
      await onFalImageUploaded?.(userImageURL);
      logFal("upload_complete", { jobId, role: "subject", imageHost: safeHost(userImageURL) });
    }

    let companionImageURL = null;
    if (companionPath) {
      companionImageURL = cachedCompanionFalImageURL;
      if (companionImageURL) {
        logFal("upload_reused_cdn_url", { jobId, role: "companion", imageHost: safeHost(companionImageURL) });
      } else {
        logFal("upload_start", { jobId, role: "companion", contentType: companionContentType });
        companionImageURL = await uploadToFalCdn({
          imagePath: companionPath,
          contentType: companionContentType
        });
        await onCompanionFalImageUploaded?.(companionImageURL);
        logFal("upload_complete", { jobId, role: "companion", imageHost: safeHost(companionImageURL) });
      }
    }
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
/// When Talking + spokenLine are set, synthesizes speech and muxes it onto the clip.
export async function generateSceneVideo({
  imageURL,
  prompt,
  jobId,
  onProgress,
  spokenLine = "",
  subjectGender = "auto",
  motionStyle = "cinematic"
}) {
  if (config.enableMockGeneration) {
    logFal("mock_video_generation", {
      jobId,
      prompt,
      motionStyle,
      hasSpokenLine: Boolean(String(spokenLine || "").trim())
    });
    await mockProgress(onProgress);
    return config.mockVideoURL;
  }

  if (!config.falKey) {
    throw new Error("FAL_KEY is not configured.");
  }

  fal.config({ credentials: config.falKey });

  try {
    let videoURL = await runVideoRequest({ imageURL, prompt, jobId, onProgress });
    videoURL = await maybeAttachTalkingAudio({
      videoURL,
      spokenLine,
      subjectGender,
      motionStyle,
      jobId,
      onProgress
    });
    return videoURL;
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
      let videoURL = await runVideoRequest({ imageURL, prompt, jobId, onProgress, safeMode: true });
      videoURL = await maybeAttachTalkingAudio({
        videoURL,
        spokenLine,
        subjectGender,
        motionStyle,
        jobId,
        onProgress
      });
      return videoURL;
    }

    throw operationalError;
  }
}

/// For Talking clips with a spoken line: TTS → lip-sync (preferred) or mux fallback.
/// Failures are logged and the silent video is returned so animate still succeeds.
async function maybeAttachTalkingAudio({
  videoURL,
  spokenLine,
  subjectGender,
  motionStyle,
  jobId,
  onProgress
}) {
  const line = String(spokenLine || "").trim();
  if (normalizeMotionStyleLocal(motionStyle) !== "talking" || !line) {
    return videoURL;
  }

  try {
    onProgress?.(80);
    const audioURL = await synthesizeSpeech({ text: line, subjectGender, jobId });
    onProgress?.(88);
    try {
      const syncedURL = await lipsyncVideoToAudio({ videoURL, audioURL, jobId });
      onProgress?.(95);
      return syncedURL || videoURL;
    } catch (lipsyncError) {
      logFal("lipsync_failed_falling_back_to_mux", { jobId, ...serializeFalError(lipsyncError) });
      const mergedURL = await mergeAudioOntoVideo({ videoURL, audioURL, jobId });
      onProgress?.(95);
      return mergedURL || videoURL;
    }
  } catch (error) {
    logFal("talking_audio_failed", { jobId, ...serializeFalError(error) });
    return videoURL;
  }
}

async function synthesizeSpeech({ text, subjectGender, jobId }) {
  const voice = voiceForGender(subjectGender);
  const gender = String(subjectGender || "").trim().toLowerCase();
  // Conversational interview tone — slightly lower stability = more natural inflection.
  const tone = gender === "male"
    ? { stability: 0.35, similarity_boost: 0.8, style: 0.3 }
    : gender === "female"
      ? { stability: 0.4, similarity_boost: 0.78, style: 0.35 }
      : { stability: 0.4, similarity_boost: 0.75, style: 0.3 };

  logFal("tts_start", {
    jobId,
    model: config.falTtsModel,
    voice,
    subjectGender: gender || "auto",
    chars: text.length
  });

  const result = await fal.subscribe(config.falTtsModel, {
    input: {
      text,
      voice,
      ...tone
    },
    logs: true
  });

  const audioURL = extractAudioURL(result?.data ?? result);
  if (!audioURL) {
    throw new Error("fal.ai TTS result did not include an audio URL.");
  }

  logFal("tts_complete", { jobId, audioHost: safeHost(audioURL), voice });
  return audioURL;
}

async function lipsyncVideoToAudio({ videoURL, audioURL, jobId }) {
  logFal("lipsync_start", {
    jobId,
    model: config.falLipsyncModel,
    videoHost: safeHost(videoURL),
    audioHost: safeHost(audioURL)
  });

  const result = await fal.subscribe(config.falLipsyncModel, {
    input: {
      video_url: videoURL,
      audio_url: audioURL,
      sync_mode: "cut_off"
    },
    logs: true
  });

  const syncedURL = extractVideoURL(result?.data ?? result);
  if (!syncedURL) {
    throw new Error("fal.ai lipsync did not include a video URL.");
  }

  logFal("lipsync_complete", { jobId, videoHost: safeHost(syncedURL) });
  return syncedURL;
}

async function mergeAudioOntoVideo({ videoURL, audioURL, jobId }) {
  logFal("audio_merge_start", {
    jobId,
    model: config.falMergeAudioVideoModel,
    videoHost: safeHost(videoURL),
    audioHost: safeHost(audioURL)
  });

  const result = await fal.subscribe(config.falMergeAudioVideoModel, {
    input: {
      video_url: videoURL,
      audio_url: audioURL,
      start_offset: 0.15
    },
    logs: true
  });

  const mergedURL = extractVideoURL(result?.data ?? result);
  if (!mergedURL) {
    throw new Error("fal.ai audio merge did not include a video URL.");
  }

  logFal("audio_merge_complete", { jobId, videoHost: safeHost(mergedURL) });
  return mergedURL;
}

function voiceForGender(gender) {
  const normalized = String(gender || "").trim().toLowerCase();
  if (normalized === "male") {
    return config.ttsVoiceMale;
  }
  if (normalized === "female") {
    return config.ttsVoiceFemale;
  }
  return config.ttsVoiceDefault;
}

function normalizeMotionStyleLocal(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return ["cinematic", "talking", "portrait", "energy"].includes(normalized)
    ? normalized
    : "cinematic";
}

async function runVideoRequest({ imageURL, prompt, jobId, onProgress, safeMode = false }) {
  const input = {
    image_url: imageURL,
    prompt
  };

  if (!safeMode) {
    input.duration = String(config.videoDurationSeconds);
    input.resolution = config.videoResolution;
    // PixVerse supports negative prompts (unlike Kontext) — use one to fight
    // the classic image-to-video failure modes: face morphing and flicker.
    input.negative_prompt = config.videoNegativePrompt;
    // Don't let PixVerse rewrite our face-lock / lip-sync instructions.
    if (config.videoThinkingType) {
      input.thinking_type = config.videoThinkingType;
    }
  }

  logFal("video_start", {
    jobId,
    model: config.falVideoModel,
    duration: config.videoDurationSeconds,
    resolution: config.videoResolution,
    thinkingType: config.videoThinkingType || null,
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

/// paramMode:
///   full     — steps (solo) + guidance + aspect + enhance_prompt=false
///   reduced  — keep quality-critical params, drop steps (schema-safe for multi)
///   minimal  — prompt + images only (last resort after ValidationError)
async function runFalRequest({
  prompt,
  userImageURL,
  companionImageURL,
  seed,
  jobId,
  onProgress,
  paramMode = "full"
}) {
  const isMulti = Boolean(companionImageURL);
  const model = isMulti ? config.falMultiModel : imageModel();

  const input = isMulti
    ? { image_urls: [userImageURL, companionImageURL], prompt }
    : { image_url: userImageURL, prompt };

  if (paramMode !== "minimal") {
    // Never let fal rewrite our carefully crafted identity locks.
    input.enhance_prompt = false;
    // Vertical editorial frame for head-to-shoes compositions.
    input.aspect_ratio = config.falImageAspectRatio;
    // Slightly stronger guidance on multi so both faces stay locked to sources.
    input.guidance_scale = isMulti ? config.falMultiGuidance : config.falKontextGuidance;
    if (Number.isFinite(seed)) {
      input.seed = seed;
    }
    // Multi-image Kontext endpoints reject num_inference_steps (not in schema).
    // Sending it triggers ValidationError → quality drop. Only send steps on solo.
    if (!isMulti && paramMode === "full") {
      input.num_inference_steps = config.falKontextSteps;
    }
  }

  logFal("scene_request", {
    jobId,
    model,
    isMulti,
    paramMode,
    guidance: input.guidance_scale ?? null,
    aspectRatio: input.aspect_ratio ?? null,
    steps: input.num_inference_steps ?? null
  });

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
    return await runFalRequest({ ...args, paramMode: "full" });
  } catch (error) {
    const operationalError = normalizeFalOperationalError(error);
    logFal("scene_error", { jobId: args.jobId, ...serializeFalError(operationalError) });

    if (operationalError?.name !== "ValidationError") {
      throw operationalError;
    }

    // Prefer reduced (keep aspect/guidance) before bare minimal — avoids the
    // old safeMode path that silently tanked companion quality.
    try {
      logFal("scene_retry_reduced_input", { jobId: args.jobId });
      return await runFalRequest({ ...args, paramMode: "reduced" });
    } catch (reducedError) {
      const reducedOperational = normalizeFalOperationalError(reducedError);
      if (reducedOperational?.name !== "ValidationError") {
        throw reducedOperational;
      }
      logFal("scene_retry_minimal_input", { jobId: args.jobId });
      return await runFalRequest({ ...args, paramMode: "minimal" });
    }
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

function extractAudioURL(result) {
  return result?.audio?.url || result?.audio_url || result?.audio?.file?.url || "";
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
