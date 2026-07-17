import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const rootDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

loadDotEnv(path.join(rootDirectory, ".env"));

function bool(value, fallback = false) {
  if (value === undefined || value === "") {
    return fallback;
  }
  return ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

function number(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function resolveFromRoot(value, fallback) {
  return path.resolve(rootDirectory, value || fallback);
}

function loadDotEnv(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex <= 0) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const rawValue = trimmed.slice(separatorIndex + 1).trim();
    const value = rawValue
      .replace(/^"(.*)"$/, "$1")
      .replace(/^'(.*)'$/, "$1");

    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function jwtSecret() {
  const secret = process.env.STYLEAI_JWT_SECRET;
  if (secret && secret.length >= 32) {
    return secret;
  }

  if (process.env.NODE_ENV === "production") {
    throw new Error("STYLEAI_JWT_SECRET must be set to at least 32 characters in production.");
  }

  return "development-only-styleai-secret-change-before-production";
}

export const config = Object.freeze({
  nodeEnv: process.env.NODE_ENV || "development",
  port: number(process.env.PORT, 8080),
  // RENDER_EXTERNAL_URL is injected automatically when hosted on Render.
  publicBaseURL: (process.env.PUBLIC_BASE_URL || process.env.RENDER_EXTERNAL_URL || "http://localhost:8080").replace(/\/+$/, ""),
  jwtSecret: jwtSecret(),
  dataPath: resolveFromRoot(process.env.STYLEAI_DATA_PATH, "./data/styleai.json"),
  uploadDirectory: resolveFromRoot(process.env.STYLEAI_UPLOAD_DIR, "./uploads"),
  maxUploadBytes: number(process.env.STYLEAI_MAX_UPLOAD_BYTES, 12_000_000),
  appleClientId: process.env.APPLE_CLIENT_ID || "",
  googleClientId: process.env.GOOGLE_CLIENT_ID || "",
  googleClientIds: String(process.env.GOOGLE_CLIENT_IDS || process.env.GOOGLE_CLIENT_ID || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
  falKey: process.env.FAL_KEY || "",
  falModel: process.env.FAL_MODEL || "fal-ai/flux-pro/kontext",
  // Force a consistent vertical editorial frame regardless of the shape of
  // the user's uploaded photo — full-body head-to-shoes compositions need it.
  falImageAspectRatio: process.env.STYLEAI_IMAGE_ASPECT_RATIO || "9:16",
  enableMockGeneration: bool(process.env.STYLEAI_ENABLE_MOCK_GENERATION, false),
  fallbackToMockOnFalBilling: bool(process.env.STYLEAI_FAL_FALLBACK_TO_MOCK_ON_BILLING, false),

  // Cost controls.
  // Eco mode swaps image generation to the cheaper kontext dev endpoint and
  // drops video resolution to the lowest tier.
  ecoMode: bool(process.env.STYLEAI_ECO_MODE, false),
  falEcoModel: process.env.FAL_ECO_MODEL || "fal-ai/flux-kontext/dev",
  // Reuse a previously generated result when the same user re-requests the
  // exact same photo + prompt combination (zero fal cost on repeats).
  reuseIdenticalResults: bool(process.env.STYLEAI_REUSE_IDENTICAL_RESULTS, true),

  // Video generation (PixVerse is currently the cheapest image-to-video on fal:
  // ~$0.025/s at 360p, ~$0.045/s at 720p).
  falVideoModel: process.env.FAL_VIDEO_MODEL || "fal-ai/pixverse/v6/image-to-video",
  videoDurationSeconds: number(process.env.STYLEAI_VIDEO_DURATION_SECONDS, 5),
  videoResolution: process.env.STYLEAI_VIDEO_RESOLUTION
    || (bool(process.env.STYLEAI_ECO_MODE, false) ? "360p" : "720p"),
  videoNegativePrompt: process.env.STYLEAI_VIDEO_NEGATIVE_PROMPT
    || "blurry, low quality, low resolution, pixelated, noisy, grainy, out of focus, distorted face, face morphing, changing identity, warped features, extra fingers, deformed hands, flickering, jitter, artifacts, watermark, text",
  mockVideoURL: process.env.STYLEAI_MOCK_VIDEO_URL
    || "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",

  // Talking Video Director: TTS → lip-sync (preferred) or ffmpeg mux fallback.
  falTtsModel: process.env.FAL_TTS_MODEL || "fal-ai/elevenlabs/tts/turbo-v2.5",
  falLipsyncModel: process.env.FAL_LIPSYNC_MODEL || "fal-ai/sync-lipsync/v3",
  falMergeAudioVideoModel: process.env.FAL_MERGE_AUDIO_VIDEO_MODEL
    || "fal-ai/ffmpeg-api/merge-audio-video",
  ttsVoiceFemale: process.env.STYLEAI_TTS_VOICE_FEMALE || "Rachel",
  ttsVoiceMale: process.env.STYLEAI_TTS_VOICE_MALE || "Adam",
  ttsVoiceDefault: process.env.STYLEAI_TTS_VOICE_DEFAULT || "Aria"
});
