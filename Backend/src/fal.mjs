import { config } from "./config.mjs";

const stylePrompts = {
  casual: "realistic personal styling portrait, casual everyday outfit, clean modern fashion, natural lighting, high quality",
  professional: "realistic personal styling portrait, polished professional outfit, tailored business fashion, natural lighting, high quality",
  wedding: "realistic personal styling portrait, elegant wedding guest outfit, refined formal fashion, natural lighting, high quality",
  sporty: "realistic personal styling portrait, premium sporty outfit, active lifestyle fashion, natural lighting, high quality",
  luxury: "realistic personal styling portrait, luxury designer-inspired outfit, elevated fashion editorial, natural lighting, high quality",
  streetwear: "realistic personal styling portrait, modern streetwear outfit, layered urban fashion, natural lighting, high quality"
};

const negativePrompt = [
  "blurry",
  "low resolution",
  "distorted face",
  "extra fingers",
  "bad anatomy",
  "cartoon",
  "illustration",
  "watermark",
  "logo",
  "text"
].join(", ");

export async function generateStyleVariants({ imageURL, styleGoal, seed, onProgress }) {
  if (config.enableMockGeneration) {
    return mockVariants(imageURL);
  }

  if (!config.falKey) {
    throw new Error("FAL_KEY is not configured.");
  }

  const prompt = stylePrompts[styleGoal] || stylePrompts.casual;
  const variants = [];

  for (let index = 0; index < 4; index += 1) {
    onProgress?.(15 + index * 18);
    const result = await runFalRequest({
      prompt,
      faceImageURL: imageURL,
      seed: Number.isFinite(seed) ? seed + index : randomSeed(),
      variantIndex: index
    });
    variants.push(result);
    onProgress?.(30 + index * 18);
  }

  return variants;
}

async function runFalRequest({ prompt, faceImageURL, seed, variantIndex }) {
  const submitResponse = await fetch(`https://queue.fal.run/${config.falModel}`, {
    method: "POST",
    headers: falHeaders(),
    body: JSON.stringify({
      input: {
        prompt: `${prompt}, variant ${variantIndex + 1}`,
        face_image_url: faceImageURL,
        negative_prompt: negativePrompt,
        seed,
        model_type: "1_5-v1"
      }
    })
  });

  if (!submitResponse.ok) {
    throw new Error(await falErrorMessage(submitResponse, "submit"));
  }

  const submitted = await submitResponse.json();
  const statusURL = submitted.status_url;
  const responseURL = submitted.response_url;

  if (!statusURL || !responseURL) {
    throw new Error("fal.ai response did not include queue URLs.");
  }

  await waitForFalCompletion(statusURL);

  const resultResponse = await fetch(responseURL, {
    headers: falHeaders(false)
  });

  if (!resultResponse.ok) {
    throw new Error(await falErrorMessage(resultResponse, "result"));
  }

  const result = await resultResponse.json();
  const imageURL = extractImageURL(result);
  if (!imageURL) {
    throw new Error("fal.ai result did not include an image URL.");
  }

  return imageURL;
}

async function falErrorMessage(response, phase) {
  const body = await response.text().catch(() => "");
  if (!body) {
    return `fal.ai ${phase} failed with ${response.status}`;
  }

  try {
    const payload = JSON.parse(body);
    const detail = payload.detail || payload.message || payload.error;
    if (detail) {
      return `fal.ai ${phase} failed with ${response.status}: ${detail}`;
    }
  } catch {
  }

  return `fal.ai ${phase} failed with ${response.status}: ${body.slice(0, 300)}`;
}

async function waitForFalCompletion(statusURL) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 180_000) {
    const response = await fetch(statusURL, {
      headers: falHeaders(false)
    });

    if (!response.ok) {
      throw new Error(`fal.ai status failed with ${response.status}`);
    }

    const status = await response.json();
    if (status.status === "COMPLETED") {
      return;
    }

    if (status.status === "FAILED" || status.status === "ERROR") {
      throw new Error("fal.ai generation failed.");
    }

    await new Promise((resolve) => setTimeout(resolve, 1500));
  }

  throw new Error("fal.ai generation timed out.");
}

function extractImageURL(result) {
  if (typeof result?.image?.url === "string") {
    return result.image.url;
  }

  if (Array.isArray(result?.images)) {
    const image = result.images.find((candidate) => typeof candidate?.url === "string");
    return image?.url || "";
  }

  if (typeof result?.data?.image?.url === "string") {
    return result.data.image.url;
  }

  if (Array.isArray(result?.data?.images)) {
    const image = result.data.images.find((candidate) => typeof candidate?.url === "string");
    return image?.url || "";
  }

  return "";
}

function falHeaders(includeContentType = true) {
  const headers = {
    Authorization: `Key ${config.falKey}`
  };

  if (includeContentType) {
    headers["Content-Type"] = "application/json";
  }

  return headers;
}

function randomSeed() {
  return Math.floor(Math.random() * 1_000_000_000);
}

function mockVariants(imageURL) {
  return [imageURL, imageURL, imageURL, imageURL];
}
