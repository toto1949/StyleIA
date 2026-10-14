import crypto from "node:crypto";
import { config } from "../config.mjs";
import { HttpError } from "../http-utils.mjs";

// Fast local guard for especially clear prohibited requests. OpenAI moderation
// below provides broader semantic coverage for production user-written text.
const prohibitedPatterns = [
  /\b(child|kid|minor|underage|teen)\b.{0,40}\b(nude|naked|sexual|sex)\b/i,
  /\b(nude|naked|sexual|sex)\b.{0,40}\b(child|kid|minor|underage|teen)\b/i,
  /\b(non[- ]?consensual|revenge porn|sexual assault|rape)\b/i,
  /\b(behead|dismember|gore|graphic murder)\b/i
];

let safetyFetch = fetch;
let testingFetchInstalled = false;

export function setContentSafetyFetchForTesting(fetchImplementation) {
  if (config.nodeEnv === "production") {
    throw new Error("Content-safety test injection is disabled in production.");
  }
  safetyFetch = fetchImplementation || fetch;
  testingFetchInstalled = Boolean(fetchImplementation);
}

export async function assertSafeUserText(values, userId) {
  const input = values
    .map((value) => String(value || "").trim())
    .filter(Boolean)
    .join("\n")
    .slice(0, 2_000);
  if (!input) {
    return;
  }
  if (prohibitedPatterns.some((pattern) => pattern.test(input))) {
    throw new HttpError(400, "This request cannot be processed under SceneMe's safety rules.");
  }
  if (shouldSkipRemoteSafety()) {
    return;
  }
  const payload = await requestModeration(input);
  if (isFlagged(payload)) {
    logSafetyBlock(userId, "text");
    throw new HttpError(400, "This request cannot be processed under SceneMe's safety rules.", {
      code: "CONTENT_SAFETY_BLOCKED"
    });
  }
}

export async function assertSafeUserImage(imageURL, userId) {
  if (shouldSkipRemoteSafety()) {
    return { status: "skipped", model: null };
  }
  const parsed = new URL(String(imageURL || ""));
  if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
    throw new HttpError(503, "Image safety checks are temporarily unavailable.", {
      code: "IMAGE_SAFETY_UNAVAILABLE"
    });
  }

  const payload = await requestModeration([{
    type: "image_url",
    image_url: { url: parsed.toString() }
  }]);
  if (isFlagged(payload)) {
    logSafetyBlock(userId, "image");
    throw new HttpError(400, "This photo cannot be processed under SceneMe's safety rules.", {
      code: "IMAGE_SAFETY_BLOCKED"
    });
  }
  return { status: "allowed", model: payload.model || config.openAIModerationModel };
}

async function requestModeration(input) {
  if (!config.openAIKey) {
    throw new HttpError(503, "Content safety checks are temporarily unavailable.", {
      code: "CONTENT_SAFETY_UNAVAILABLE"
    });
  }

  let response;
  try {
    response = await safetyFetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.openAIKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ model: config.openAIModerationModel, input }),
      signal: AbortSignal.timeout(10_000)
    });
  } catch {
    throw new HttpError(503, "Content safety checks are temporarily unavailable. Please try again.", {
      code: "CONTENT_SAFETY_UNAVAILABLE"
    });
  }

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !Array.isArray(payload.results) || payload.results.length === 0) {
    throw new HttpError(503, "Content safety checks are temporarily unavailable.", {
      code: "CONTENT_SAFETY_UNAVAILABLE"
    });
  }
  return payload;
}

function isFlagged(payload) {
  return payload.results.some((result) => result?.flagged === true);
}

function shouldSkipRemoteSafety() {
  return config.enableMockGeneration && config.nodeEnv !== "production" && !testingFetchInstalled;
}

function logSafetyBlock(userId, inputType) {
  // Stable pseudonymous reference for abuse investigations without logging
  // the user's actual text, photo URL, or account identifier.
  const safetyReference = crypto
    .createHmac("sha256", config.jwtSecret)
    .update(String(userId))
    .digest("hex")
    .slice(0, 16);
  console.warn(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: "sceneme-backend",
    event: "content_safety_blocked",
    inputType,
    safetyReference
  }));
}
