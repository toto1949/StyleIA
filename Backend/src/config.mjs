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
  publicBaseURL: (process.env.PUBLIC_BASE_URL || "http://localhost:8080").replace(/\/+$/, ""),
  jwtSecret: jwtSecret(),
  dataPath: resolveFromRoot(process.env.STYLEAI_DATA_PATH, "./data/styleai.json"),
  uploadDirectory: resolveFromRoot(process.env.STYLEAI_UPLOAD_DIR, "./uploads"),
  maxUploadBytes: number(process.env.STYLEAI_MAX_UPLOAD_BYTES, 12_000_000),
  appleClientId: process.env.APPLE_CLIENT_ID || "",
  falKey: process.env.FAL_KEY || "",
  falModel: process.env.FAL_MODEL || "fal-ai/flux-pro/kontext",
  enableMockGeneration: bool(process.env.STYLEAI_ENABLE_MOCK_GENERATION, false),
  fallbackToMockOnFalBilling: bool(process.env.STYLEAI_FAL_FALLBACK_TO_MOCK_ON_BILLING, false)
});
