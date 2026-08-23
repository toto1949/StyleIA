import crypto from "node:crypto";
import { config } from "../config.mjs";
import { HttpError } from "../http-utils.mjs";

const TEMPLATE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    name: { type: "string", minLength: 2, maxLength: 60 },
    description: { type: "string", minLength: 20, maxLength: 900 },
    outfit: { type: "string", minLength: 10, maxLength: 400 }
  },
  required: ["name", "description", "outfit"]
};

export async function improveSceneTemplate({ name, description, outfit, userId }) {
  const input = normalizeInput({ name, description, outfit });

  if (config.enableMockGeneration) {
    return mockImprovement(input);
  }
  if (!config.openAIKey) {
    throw new HttpError(503, "AI template improvement is not configured yet.");
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.openAIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: config.openAITemplateModel,
      store: false,
      safety_identifier: crypto.createHash("sha256").update(String(userId)).digest("hex").slice(0, 64),
      instructions: [
        "You improve short user ideas into production-ready photorealistic fashion scene templates.",
        "Preserve the user's intent. Add concrete environment, lighting, depth, camera, and atmosphere details.",
        "Do not describe a person's face, identity, ethnicity, body, or gender; the generation pipeline handles identity separately.",
        "Keep the scene description compatible with a full-body vertical editorial photograph.",
        "Return an outfit appropriate to the scene without brand names, nudity, uniforms implying authority, or unsafe content."
      ].join(" "),
      input: `Scene name: ${input.name || "Untitled"}\nScene idea: ${input.description}\nOutfit idea: ${input.outfit || "Choose an appropriate editorial outfit"}`,
      max_output_tokens: 700,
      text: {
        format: {
          type: "json_schema",
          name: "scene_template",
          strict: true,
          schema: TEMPLATE_SCHEMA
        }
      }
    }),
    signal: AbortSignal.timeout(20_000)
  }).catch((error) => {
    if (error?.name === "TimeoutError") {
      throw new HttpError(504, "AI template improvement timed out. Please try again.");
    }
    throw error;
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("OpenAI template request failed", {
      status: response.status,
      code: payload?.error?.code || "unknown"
    });
    throw new HttpError(response.status === 429 ? 429 : 502,
      response.status === 429
        ? "AI template improvement is busy. Please try again shortly."
        : "Could not improve this template right now.");
  }

  const outputText = extractOutputText(payload);
  try {
    return normalizeOutput(JSON.parse(outputText));
  } catch {
    throw new HttpError(502, "AI returned an invalid template. Please try again.");
  }
}

function normalizeInput(value) {
  const name = String(value.name || "").trim().slice(0, 60);
  const description = String(value.description || "").trim().slice(0, 600);
  const outfit = String(value.outfit || "").trim().slice(0, 300);
  if (description.length < 12) {
    throw new HttpError(400, "Describe your scene in a few words first.");
  }
  return { name, description, outfit };
}

function normalizeOutput(value) {
  return {
    name: String(value.name || "My Scene").trim().slice(0, 60),
    description: String(value.description || "").trim().slice(0, 900),
    outfit: String(value.outfit || "").trim().slice(0, 400)
  };
}

function extractOutputText(payload) {
  if (typeof payload.output_text === "string") return payload.output_text;
  return (payload.output || [])
    .flatMap((item) => item?.content || [])
    .filter((content) => content?.type === "output_text")
    .map((content) => content.text || "")
    .join("");
}

function mockImprovement(input) {
  const subject = input.description.replace(/[.\s]+$/, "");
  return {
    name: input.name || "Cinematic Escape",
    description: `${subject}, layered foreground and background detail, natural atmospheric depth, cinematic directional lighting, realistic reflections and textures, photographed as a polished full-body vertical fashion editorial`,
    outfit: input.outfit || "a refined editorial outfit tailored to the location, with coordinated layers, natural fabric texture, and scene-appropriate footwear"
  };
}
