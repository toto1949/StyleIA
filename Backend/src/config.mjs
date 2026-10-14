import path from "node:path";
import fs from "node:fs";
import crypto from "node:crypto";
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

function positiveInteger(value, fallback) {
  const parsed = Math.floor(number(value, fallback));
  return parsed > 0 ? parsed : fallback;
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

function requiredProductionSecret(name) {
  const value = String(process.env[name] || "").replace(/\\n/g, "\n");
  if (!value && process.env.NODE_ENV === "production") {
    throw new Error(`${name} must be configured in production.`);
  }
  return value;
}

function strongProductionSecret(name) {
  const value = requiredProductionSecret(name);
  if (process.env.NODE_ENV === "production" && value.length < 32) {
    throw new Error(`${name} must be at least 32 characters in production.`);
  }
  return value;
}

function privateKeySecret(name) {
  const value = requiredProductionSecret(name);
  if (process.env.NODE_ENV === "production") {
    try {
      crypto.createPrivateKey(value);
    } catch {
      throw new Error(`${name} must contain a valid private key in production.`);
    }
  }
  return value;
}

function productionNumber(name, fallback = 0) {
  const value = number(process.env[name], fallback);
  if (process.env.NODE_ENV === "production" && value <= 0) {
    throw new Error(`${name} must be a positive number in production.`);
  }
  return value;
}

export const config = Object.freeze({
  nodeEnv: process.env.NODE_ENV || "development",
  port: number(process.env.PORT, 8080),
  // RENDER_EXTERNAL_URL is injected automatically when hosted on Render.
  publicBaseURL: (process.env.PUBLIC_BASE_URL || process.env.RENDER_EXTERNAL_URL || "http://localhost:8080").replace(/\/+$/, ""),
  jwtSecret: jwtSecret(),
  jwtIssuer: process.env.STYLEAI_JWT_ISSUER || "https://api.sceneme.app",
  jwtAudience: process.env.STYLEAI_JWT_AUDIENCE || "com.sceneme.app",
  accessTokenTTLSeconds: positiveInteger(process.env.STYLEAI_ACCESS_TOKEN_TTL_SECONDS, 15 * 60),
  refreshTokenTTLDays: positiveInteger(process.env.STYLEAI_REFRESH_TOKEN_TTL_DAYS, 30),
  dataPath: resolveFromRoot(process.env.STYLEAI_DATA_PATH, "./data/styleai.json"),
  uploadDirectory: resolveFromRoot(process.env.STYLEAI_UPLOAD_DIR, "./uploads"),
  maxUploadBytes: number(process.env.STYLEAI_MAX_UPLOAD_BYTES, 12_000_000),
  maxUploadPixels: number(process.env.STYLEAI_MAX_UPLOAD_PIXELS, 40_000_000),
  maxImageResultBytes: number(process.env.STYLEAI_MAX_IMAGE_RESULT_BYTES, 30_000_000),
  maxVideoResultBytes: number(process.env.STYLEAI_MAX_VIDEO_RESULT_BYTES, 250_000_000),
  maxConcurrentImageJobsPerUser: number(process.env.STYLEAI_MAX_CONCURRENT_IMAGE_JOBS_PER_USER, 1),
  maxConcurrentVideoJobsPerUser: number(process.env.STYLEAI_MAX_CONCURRENT_VIDEO_JOBS_PER_USER, 1),
  providerTimeoutMs: number(process.env.STYLEAI_PROVIDER_TIMEOUT_MS, 6 * 60_000),
  apiRateLimitPerMinute: positiveInteger(process.env.STYLEAI_API_RATE_LIMIT_PER_MINUTE, 300),
  userRateLimitPerMinute: positiveInteger(process.env.STYLEAI_USER_RATE_LIMIT_PER_MINUTE, 180),
  authRateLimitPer15Minutes: positiveInteger(process.env.STYLEAI_AUTH_RATE_LIMIT_PER_15_MINUTES, 30),
  appStoreNotificationRateLimitPerMinute: positiveInteger(
    process.env.STYLEAI_APP_STORE_NOTIFICATION_RATE_LIMIT_PER_MINUTE,
    300
  ),
  dailyUserBudgetUSD: productionNumber("STYLEAI_DAILY_USER_BUDGET_USD"),
  dailyGlobalBudgetUSD: productionNumber("STYLEAI_DAILY_GLOBAL_BUDGET_USD"),
  estimatedImageCostUSD: number(process.env.STYLEAI_ESTIMATED_IMAGE_COST_USD, 0.04),
  estimatedPremiumImageCostUSD: number(process.env.STYLEAI_ESTIMATED_PREMIUM_IMAGE_COST_USD, 0.08),
  estimatedVideoCostUSD: number(process.env.STYLEAI_ESTIMATED_VIDEO_COST_USD, 0.35),
  estimatedTalkingVideoCostUSD: number(process.env.STYLEAI_ESTIMATED_TALKING_VIDEO_COST_USD, 1.35),
  databaseURL: requiredProductionSecret("DATABASE_URL"),
  databaseSSLRejectUnauthorized: bool(process.env.DATABASE_SSL_REJECT_UNAUTHORIZED, true),
  objectStorageBucket: requiredProductionSecret("OBJECT_STORAGE_BUCKET"),
  objectStorageRegion: process.env.OBJECT_STORAGE_REGION || "auto",
  objectStorageEndpoint: process.env.OBJECT_STORAGE_ENDPOINT || "",
  objectStorageAccessKeyId: requiredProductionSecret("OBJECT_STORAGE_ACCESS_KEY_ID"),
  objectStorageSecretAccessKey: requiredProductionSecret("OBJECT_STORAGE_SECRET_ACCESS_KEY"),
  objectStorageForcePathStyle: bool(process.env.OBJECT_STORAGE_FORCE_PATH_STYLE, false),
  objectStorageUploadTTLSeconds: number(process.env.OBJECT_STORAGE_UPLOAD_TTL_SECONDS, 15 * 60),
  objectStorageDownloadTTLSeconds: number(process.env.OBJECT_STORAGE_DOWNLOAD_TTL_SECONDS, 10 * 60),
  appleClientId: requiredProductionSecret("APPLE_CLIENT_ID"),
  appleTeamId: requiredProductionSecret("APPLE_TEAM_ID"),
  appleKeyId: requiredProductionSecret("APPLE_KEY_ID"),
  applePrivateKey: privateKeySecret("APPLE_PRIVATE_KEY"),
  dataEncryptionKey: strongProductionSecret("STYLEAI_DATA_ENCRYPTION_KEY"),
  appStoreIssuerId: requiredProductionSecret("APP_STORE_ISSUER_ID"),
  appStoreKeyId: requiredProductionSecret("APP_STORE_KEY_ID"),
  appStorePrivateKey: privateKeySecret("APP_STORE_PRIVATE_KEY"),
  appStoreBundleId: process.env.APP_STORE_BUNDLE_ID || "com.sceneme.app",
  appStoreAppleId: productionNumber("APP_STORE_APPLE_ID"),
  appStoreRootCAPaths: requiredProductionSecret("APP_STORE_ROOT_CA_PATHS")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => resolveFromRoot(value, value)),
  appStoreEnableOnlineChecks: bool(process.env.APP_STORE_ENABLE_ONLINE_CHECKS, true),
  googleClientId: process.env.GOOGLE_CLIENT_ID || "",
  googleClientIds: String(process.env.GOOGLE_CLIENT_IDS || process.env.GOOGLE_CLIENT_ID || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
  falKey: requiredProductionSecret("FAL_KEY"),
  openAIKey: requiredProductionSecret("OPENAI_API_KEY"),
  openAITemplateModel: process.env.OPENAI_TEMPLATE_MODEL || "gpt-5-mini",
  openAIModerationModel: process.env.OPENAI_MODERATION_MODEL || "omni-moderation-latest",
  falModel: process.env.FAL_MODEL || "fal-ai/flux-pro/kontext",
  falPremiumModel: process.env.FAL_PREMIUM_MODEL || "fal-ai/flux-pro/kontext/max",
  // Companion (friend/pet): pro multi is ~$0.04 vs max/multi ~$0.08. Override with
  // fal-ai/flux-pro/kontext/max/multi only if A/B shows face lock needs it.
  falMultiModel: process.env.FAL_MULTI_MODEL || "fal-ai/flux-pro/kontext/multi",
  falPremiumMultiModel: process.env.FAL_PREMIUM_MULTI_MODEL || "fal-ai/flux-pro/kontext/max/multi",
  // Force a consistent vertical editorial frame regardless of the shape of
  // the user's uploaded photo — full-body head-to-shoes compositions need it.
  falImageAspectRatio: process.env.STYLEAI_IMAGE_ASPECT_RATIO || "9:16",
  // The dev/eco endpoint accepts an inference-step count; Kontext Pro does not.
  falKontextSteps: number(process.env.FAL_KONTEXT_NUM_INFERENCE_STEPS, 36),
  falKontextGuidance: number(process.env.FAL_KONTEXT_GUIDANCE_SCALE, 3.75),
  falMultiGuidance: number(process.env.FAL_MULTI_GUIDANCE_SCALE, 4.5),
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
  // ~$0.025/s at 360p, ~$0.035/s at 540p, ~$0.045/s at 720p).
  falVideoModel: process.env.FAL_VIDEO_MODEL || "fal-ai/pixverse/v6/image-to-video",
  videoDurationSeconds: number(process.env.STYLEAI_VIDEO_DURATION_SECONDS, 5),
  videoResolution: process.env.STYLEAI_VIDEO_RESOLUTION
    || (bool(process.env.STYLEAI_ECO_MODE, false) ? "360p" : "720p"),
  // Keep our crafted face-lock prompts intact (same idea as enhance_prompt=false).
  videoThinkingType: process.env.STYLEAI_VIDEO_THINKING_TYPE || "disabled",
  videoNegativePrompt: process.env.STYLEAI_VIDEO_NEGATIVE_PROMPT
    || "blurry, low quality, low resolution, pixelated, noisy, grainy, out of focus, distorted face, face morphing, changing identity, warped features, melted face, asymmetric eyes, extra fingers, deformed hands, flickering, jitter, temporal artifacts, watermark, text overlay, logo",
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

if (config.nodeEnv === "production" && (config.enableMockGeneration || config.fallbackToMockOnFalBilling)) {
  throw new Error("Mock generation and billing fallbacks must be disabled in production.");
}
