import fs from "node:fs/promises";
import { fal } from "@fal-ai/client";
import { config } from "./config.mjs";

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

const styleCatalog = {
  sporty: {
    title: "Sport Fit",
    subtitle: "Premium active layers",
    scene: "outdoor running track or modern wellness studio background, clean natural light, athletic confident pose",
    maleOutfit: "technical athletic jacket, fitted performance tee, tapered training pants, premium trainers",
    femaleOutfit: "technical cropped or fitted athletic jacket, breathable performance top, high-waist tapered training pants or sculpted leggings, premium trainers"
  },
  professional: {
    title: "Professional Fit",
    subtitle: "Tailored work polish",
    scene: "modern office background, soft window light, confident standing pose",
    maleOutfit: "tailored blazer, crisp shirt or fine knit, formal trousers, polished leather shoes",
    femaleOutfit: "tailored blazer, refined blouse or fine knit, high-waist tailored trousers or midi skirt, polished loafers or low heels"
  },
  casual: {
    title: "Casual Fit",
    subtitle: "Easy everyday style",
    scene: "sunny park or clean city sidewalk background, natural lighting, relaxed confident pose",
    maleOutfit: "premium casual tee or overshirt, relaxed straight jeans or chinos, clean low-profile sneakers",
    femaleOutfit: "premium casual tee or soft overshirt, relaxed straight jeans or tailored casual trousers, clean low-profile sneakers"
  },
  luxury: {
    title: "Night Out Fit",
    subtitle: "Editorial evening edge",
    scene: "upscale evening lounge or boutique hotel background, warm cinematic lighting, editorial standing pose",
    maleOutfit: "textured statement jacket, refined dark shirt, tailored trousers, polished dress shoes, tasteful watch",
    femaleOutfit: "textured statement jacket or structured evening top, tailored trousers or elegant skirt, polished heels or sleek dress flats, tasteful jewelry"
  },
  streetwear: {
    title: "Streetwear Fit",
    subtitle: "Layered urban mood",
    scene: "urban street background, evening city light, natural walking pose",
    maleOutfit: "layered bomber or overshirt, graphic tee, relaxed cargo pants, statement sneakers",
    femaleOutfit: "layered bomber or oversized overshirt, fitted or graphic tee, relaxed cargo pants or wide-leg denim, statement sneakers"
  },
  wedding: {
    title: "Formal Fit",
    subtitle: "Occasion-ready polish",
    scene: "elegant venue courtyard background, soft natural light, formal full-body portrait",
    maleOutfit: "refined formal suit, crisp shirt, polished dress shoes, subtle pocket square",
    femaleOutfit: "elegant wedding guest dress or tailored formal suit, refined shoes, subtle jewelry, polished occasion styling"
  }
};

const assetCatalog = {
  shoes: {
    title: "Shoes",
    prompt: (styleGoal) => [
      "The same person from the input image, preserve the outfit and face",
      shoePrompt(styleGoal),
      "full body portrait with the shoes clearly visible",
      "slightly lower camera angle but still showing the whole person",
      "premium editorial fashion photography",
      "same face, same person, preserve facial identity"
    ].join(", ")
  },
  frames: {
    title: "Frames",
    prompt: (styleGoal) => [
      "The same person from the input image now wearing stylish eyeglasses",
      framePrompt(styleGoal),
      "glasses clearly visible on the face, eyes visible through the lenses",
      "full body or three-quarter fashion portrait",
      "premium editorial fashion photography",
      "same face, same person, preserve facial identity"
    ].join(", ")
  },
  accessories: {
    title: "Accessories",
    prompt: (styleGoal) => [
      "The same person from the input image with the outfit preserved",
      accessoryPrompt(styleGoal),
      "accessory clearly visible and naturally worn or carried",
      "full body fashion portrait",
      "premium editorial fashion photography",
      "same face, same person, preserve facial identity"
    ].join(", ")
  }
};

export async function generateStyleVariants({
  imageURL,
  imagePath,
  contentType = "image/jpeg",
  styleGoal,
  styleGoals,
  seed,
  jobId,
  subjectGender = "male",
  styleProfile = {},
  userId = "",
  onProgress,
  onLookReady
}) {
  const lookGoals = normalizeStyleGoals(styleGoal, styleGoals);
  const profile = normalizeStyleProfile({ ...styleProfile, subjectGender });
  const styleSignature = buildStyleSignature({ userId, seed, profile });

  if (config.enableMockGeneration) {
    logFal("mock_generation", { jobId, lookGoals, profile, styleSignature });
    return mockVariants(imageURL, lookGoals, profile, styleSignature, jobId);
  }

  if (!config.falKey) {
    throw new Error("FAL_KEY is not configured.");
  }

  fal.config({ credentials: config.falKey });

  try {
    logFal("upload_start", { jobId, contentType, imagePath: imagePath ? "local-file" : "remote-url" });
    const kontextImageURL = imagePath ? await uploadToFalCdn({ imagePath, contentType }) : imageURL;
    logFal("upload_complete", { jobId, imageHost: safeHost(kontextImageURL) });
    onProgress?.(12);

    const progressStep = 82 / lookGoals.length;
    let completedLooks = 0;

    const looks = await Promise.all(lookGoals.map(async (currentGoal, index) => {
      const catalogItem = styleCatalog[currentGoal] || styleCatalog.casual;
      const startedAt = Date.now();

      logFal("look_start", {
        jobId,
        model: config.falModel,
        styleGoal: currentGoal,
        lookIndex: index + 1,
        lookCount: lookGoals.length,
        profile,
        styleSignature
      });

      const imageURL = await runFalRequestWithFallback({
        prompt: outfitPrompt(catalogItem, currentGoal, profile, styleSignature),
        imageURL: kontextImageURL,
        styleGoal: currentGoal,
        variantIndex: index,
        subjectGender: profile.subjectGender,
        profile,
        styleSignature,
        seed: variantSeed(seed, currentGoal, index, "outfit")
      });

      const look = {
        id: `${jobId}-${currentGoal}-${index + 1}`,
        styleGoal: currentGoal,
        title: catalogItem.title,
        subtitle: catalogItem.subtitle,
        imageURL,
        assetURLs: {
          outfit: imageURL
        },
        products: []
      };

      logFal("look_complete", {
        jobId,
        styleGoal: currentGoal,
        lookIndex: index + 1,
        durationMs: Date.now() - startedAt,
        imageHost: safeHost(imageURL)
      });
      completedLooks += 1;
      onProgress?.(18 + completedLooks * progressStep);
      await onLookReady?.(look);

      look.assetURLs = {
        ...look.assetURLs,
        ...(await generateLookAssets({
          baseImageURL: imageURL,
          styleGoal: currentGoal,
          variantIndex: index,
          jobId,
          subjectGender: profile.subjectGender,
          profile,
          styleSignature,
          seed
        }))
      };
      look.products = productMatches({
        styleGoal: currentGoal,
        assetURLs: look.assetURLs,
        profile
      });
      await onLookReady?.(look);

      return look;
    }));

    return looks;
  } catch (error) {
    const operationalError = normalizeFalOperationalError(error);

    if (operationalError instanceof FalBillingError && config.fallbackToMockOnFalBilling) {
      return emitBillingFallbackMocks({
        imageURL,
        lookGoals,
        profile,
        styleSignature,
        jobId,
        onProgress,
        onLookReady,
        error: operationalError
      });
    }

    throw operationalError;
  }
}

async function generateLookAssets({ baseImageURL, styleGoal, variantIndex, jobId, subjectGender, profile, styleSignature, seed }) {
  const entries = Object.entries(assetCatalog);
  const generated = await Promise.all(entries.map(async ([assetKey, asset]) => {
    const startedAt = Date.now();
    logFal("asset_start", {
      jobId,
      styleGoal,
      assetKey,
      variantIndex: variantIndex + 1
    });

    const imageURL = await runFalRequestWithFallback({
      prompt: asset.prompt(styleGoal),
      imageURL: baseImageURL,
      styleGoal,
      variantIndex,
      assetKey,
      subjectGender,
      profile,
      styleSignature,
      seed: variantSeed(seed, styleGoal, variantIndex, assetKey)
    });

    logFal("asset_complete", {
      jobId,
      styleGoal,
      assetKey,
      variantIndex: variantIndex + 1,
      durationMs: Date.now() - startedAt,
      imageHost: safeHost(imageURL)
    });

    return [assetKey, imageURL];
  }));

  return Object.fromEntries(generated);
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

async function runFalRequest({ prompt, imageURL, styleGoal, variantIndex, assetKey, subjectGender, profile, styleSignature, seed, safeMode = false }) {
  const input = {
    image_url: imageURL,
    prompt: buildLookPrompt({ prompt, styleGoal, variantIndex, assetKey, subjectGender, profile, styleSignature })
  };

  if (!safeMode) {
    input.num_inference_steps = kontextSteps();
    input.guidance_scale = kontextGuidanceScale();
  }

  if (!safeMode && Number.isFinite(seed)) {
    input.seed = seed;
  }

  const result = await fal.subscribe(config.falModel, {
    input,
    logs: true,
    onQueueUpdate: (update) => {
      if (update.status === "IN_PROGRESS") {
        logFal("queue_update", {
          styleGoal,
          variantIndex: variantIndex + 1,
          assetKey: assetKey || "outfit",
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
    logFal("look_error", {
      styleGoal: args.styleGoal,
      variantIndex: args.variantIndex + 1,
      ...serializeFalError(operationalError)
    });

    if (operationalError?.name !== "ValidationError") {
      throw operationalError;
    }

    logFal("look_retry_minimal_input", {
      styleGoal: args.styleGoal,
      variantIndex: args.variantIndex + 1,
      assetKey: args.assetKey || "outfit"
    });

    return await runFalRequest({ ...args, safeMode: true });
  }
}

async function emitBillingFallbackMocks({ imageURL, lookGoals, profile, styleSignature, jobId, onProgress, onLookReady, error }) {
  logFal("mock_generation_billing_fallback", {
    jobId,
    lookGoals,
    profile,
    styleSignature,
    ...serializeFalError(error)
  });

  const looks = mockVariants(imageURL, lookGoals, profile, styleSignature, jobId);
  for (const [index, look] of looks.entries()) {
    onProgress?.(18 + ((index + 1) / looks.length) * 82);
    await onLookReady?.(look);
  }
  return looks;
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

function extractImageURL(result) {
  return result?.images?.[0]?.url || "";
}

function buildLookPrompt({ prompt, styleGoal, variantIndex, assetKey, subjectGender = "male", profile = {}, styleSignature = {} }) {
  const genderText = subjectGender === "female"
    ? "adult woman"
    : subjectGender === "nonbinary"
      ? "adult nonbinary person"
      : "adult man";
  const identityDetails = identityPreservationText(subjectGender);
  const negativePrompt = negativePromptForGender(subjectGender);

  return [
    prompt,
    `${styleGoal} ${assetKey || "outfit"} image ${variantIndex + 1}`,
    `the subject must remain the same ${genderText} from the input image`,
    identityDetails,
    profileDescriptor(profile),
    signatureDescriptor(styleSignature),
    "outfit must be personalized to the subject's body proportions, face, undertone, age range, lifestyle context, and selected style direction",
    "do not reuse a generic outfit template; vary color palette, layering, fabric, fit, and scene based on the user profile and style signature",
    "do not beautify into a different person, do not change ethnicity, do not change gender identity",
    "one single person only",
    "the subject is centered and visible from head to shoes",
    "vertical lock screen fashion image composition",
    "feet and shoes visible in frame",
    "hands and body anatomy must be realistic, no duplicated limbs, no cropped head, no cropped feet",
    "camera height around chest level, realistic full-body fashion editorial photo, crisp detail",
    negativePrompt,
    "premium editorial fashion photography",
    "same face, same person, preserve facial identity"
  ].filter(Boolean).join(", ");
}

function outfitPrompt(catalogItem, styleGoal, profile, styleSignature) {
  const outfit = profile.subjectGender === "female" ? catalogItem.femaleOutfit : catalogItem.maleOutfit;
  return [
    `The same person in a ${styleGoal} fashion look`,
    outfit,
    catalogItem.scene,
    `${styleSignature.palette} color direction`,
    `${styleSignature.fit} fit direction`,
    `${styleSignature.texture} texture direction`,
    `${styleSignature.layering} layering direction`,
    "full body portrait"
  ].filter(Boolean).join(", ");
}

function normalizeStyleProfile(value = {}) {
  const subjectGender = normalizeSubjectGender(value.subjectGender);
  return {
    subjectGender,
    ageRange: cleanProfileValue(value.ageRange, "adult"),
    bodyType: cleanProfileValue(value.bodyType, ""),
    heightRange: cleanProfileValue(value.heightRange, ""),
    skinTone: cleanProfileValue(value.skinTone, ""),
    undertone: cleanProfileValue(value.undertone, ""),
    hairColor: cleanProfileValue(value.hairColor, ""),
    faceShape: cleanProfileValue(value.faceShape, ""),
    fitPreference: cleanProfileValue(value.fitPreference, ""),
    colorPreference: cleanProfileValue(value.colorPreference, ""),
    modestyPreference: cleanProfileValue(value.modestyPreference, ""),
    climate: cleanProfileValue(value.climate, ""),
    occasion: cleanProfileValue(value.occasion, ""),
    budget: cleanProfileValue(value.budget, ""),
    stylePersona: cleanProfileValue(value.stylePersona, ""),
    avoid: normalizeList(value.avoid).slice(0, 8),
    favoriteColors: normalizeList(value.favoriteColors).slice(0, 6)
  };
}

function cleanProfileValue(value, fallback = "") {
  const cleaned = String(value || "").trim().replace(/[^\w\s.,&/-]/g, "").slice(0, 80);
  return cleaned || fallback;
}

function normalizeList(value) {
  if (Array.isArray(value)) {
    return value.map((item) => cleanProfileValue(item)).filter(Boolean);
  }

  return String(value || "")
    .split(",")
    .map((item) => cleanProfileValue(item))
    .filter(Boolean);
}

function normalizeSubjectGender(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["female", "woman", "women"].includes(normalized)) {
    return "female";
  }
  if (["nonbinary", "non-binary", "nb"].includes(normalized)) {
    return "nonbinary";
  }
  return "male";
}

function profileDescriptor(profile) {
  const details = [
    profile.ageRange && `age range: ${profile.ageRange}`,
    profile.bodyType && `body/build: ${profile.bodyType}`,
    profile.heightRange && `height impression: ${profile.heightRange}`,
    profile.skinTone && `skin tone: ${profile.skinTone}`,
    profile.undertone && `undertone: ${profile.undertone}`,
    profile.hairColor && `hair color: ${profile.hairColor}`,
    profile.faceShape && `face shape: ${profile.faceShape}`,
    profile.fitPreference && `fit preference: ${profile.fitPreference}`,
    profile.colorPreference && `color preference: ${profile.colorPreference}`,
    profile.favoriteColors.length ? `favorite colors: ${profile.favoriteColors.join(", ")}` : "",
    profile.modestyPreference && `coverage/modesty preference: ${profile.modestyPreference}`,
    profile.climate && `climate: ${profile.climate}`,
    profile.occasion && `occasion context: ${profile.occasion}`,
    profile.budget && `budget level: ${profile.budget}`,
    profile.stylePersona && `style persona: ${profile.stylePersona}`,
    profile.avoid.length ? `avoid: ${profile.avoid.join(", ")}` : ""
  ].filter(Boolean);

  return details.length ? `personal styling profile: ${details.join("; ")}` : "";
}

function buildStyleSignature({ userId = "", seed = 0, profile = {} }) {
  const basis = JSON.stringify({ userId, seed, profile });
  const hash = hashString(basis);
  const palettes = profile.favoriteColors.length
    ? profile.favoriteColors.map((item) => `${item} anchored palette`)
    : [
      "olive, ivory, and charcoal",
      "navy, stone, and soft white",
      "espresso, cream, and brushed gold",
      "black, mist grey, and muted green",
      "sand, denim blue, and warm white",
      "deep burgundy, graphite, and bone"
    ];
  const fits = [
    "relaxed but tailored",
    "clean structured",
    "soft drape with shape",
    "sharp vertical proportions",
    "athletic streamlined",
    "editorial oversized balance"
  ];
  const textures = [
    "matte cotton and fine knit",
    "technical fabric and smooth leather",
    "soft wool and brushed suede",
    "crisp poplin and polished leather",
    "denim texture and clean canvas",
    "satin accent and structured twill"
  ];
  const layering = [
    "single statement layer",
    "light outerwear layer",
    "tonal layered separates",
    "contrast inner and outer layer",
    "minimal no-bulk layering",
    "structured top layer"
  ];

  return {
    palette: pick(palettes, hash),
    fit: pick(fits, hash >> 3),
    texture: pick(textures, hash >> 6),
    layering: pick(layering, hash >> 9),
    signatureCode: Math.abs(hash).toString(36).slice(0, 6)
  };
}

function signatureDescriptor(signature) {
  if (!signature?.signatureCode) {
    return "";
  }

  return `unique user style signature ${signature.signatureCode}: ${signature.palette}, ${signature.fit}, ${signature.texture}, ${signature.layering}`;
}

function identityPreservationText(subjectGender) {
  const base = "preserve exact facial identity, hairline, skin tone, age, face geometry, expression, jaw, eyes, nose, mouth, and glasses if present";
  if (subjectGender === "male") {
    return `${base}, preserve beard or facial hair shape if present`;
  }
  if (subjectGender === "female") {
    return `${base}, preserve makeup-free or existing makeup appearance exactly, do not masculinize the face`;
  }
  return base;
}

function negativePromptForGender(subjectGender) {
  const common = "negative prompt: different person, changed identity, face swap failure, bad anatomy, extra limbs, missing hands, missing feet, distorted face, blurry face, cropped body, duplicate person, cartoon, illustration, mannequin";
  if (subjectGender === "female") {
    return `${common}, male, man, masculine face, beard, mustache, broad masculine jaw`;
  }
  if (subjectGender === "nonbinary") {
    return `${common}, extreme gender change, exaggerated masculine features, exaggerated feminine features`;
  }
  return `${common}, woman, female, girl, feminine face, dress unless requested, skirt unless requested, makeup`;
}

function hashString(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = ((hash << 5) - hash) + value.charCodeAt(index);
    hash |= 0;
  }
  return hash || 1;
}

function pick(items, hash) {
  return items[Math.abs(hash) % items.length];
}

function variantSeed(seed, styleGoal, variantIndex, assetKey) {
  return Math.abs(hashString(`${seed || 0}:${styleGoal}:${variantIndex}:${assetKey}`)) % 1_000_000_000;
}

function shoePrompt(styleGoal) {
  switch (styleGoal) {
  case "sporty":
    return "wearing clean technical running shoes, athletic trainers emphasized";
  case "professional":
    return "wearing polished black oxford shoes, formal leather footwear emphasized";
  case "luxury":
    return "wearing sleek polished dress shoes for a night out, elegant footwear emphasized";
  case "streetwear":
    return "wearing bold statement sneakers, urban footwear emphasized";
  default:
    return "wearing clean white low-profile sneakers, casual footwear emphasized";
  }
}

function framePrompt(styleGoal) {
  switch (styleGoal) {
  case "professional":
    return "wearing clear angular professional eyeglasses";
  case "luxury":
    return "wearing refined rounded dark eyeglasses for a night out";
  case "streetwear":
    return "wearing bold acetate fashion glasses";
  default:
    return "wearing soft rectangular eyeglasses that suit the face";
  }
}

function accessoryPrompt(styleGoal) {
  switch (styleGoal) {
  case "sporty":
    return "carrying a compact gym bag and wearing a sport watch";
  case "professional":
    return "carrying a structured leather briefcase with a subtle tie or watch";
  case "luxury":
    return "wearing an elegant watch and holding a subtle cologne bottle detail";
  case "streetwear":
    return "wearing a clean cap and compact crossbody accessory";
  default:
    return "wearing a simple everyday watch and leather belt";
  }
}

function productMatches({ styleGoal, assetURLs = {}, profile = {} }) {
  const shoes = shoeProduct(styleGoal, assetURLs.shoes || assetURLs.outfit || null, profile);
  const frames = frameProduct(styleGoal, assetURLs.frames || assetURLs.outfit || null, profile);
  return [shoes, frames];
}

function shoeProduct(styleGoal, imageURL, profile = {}) {
  const audience = profile.subjectGender === "female" ? "women" : "men";
  const base = {
    category: "shoes",
    styleGoal,
    imageURL
  };

  switch (styleGoal) {
  case "professional":
    return {
      ...base,
      id: "professional-polished-oxfords",
      name: "Polished leather oxfords",
      brand: "StyleIA Market",
      price: "$128",
      matchReason: "Structured leather shoes support the tailored office silhouette.",
      merchantURL: shopURL(`${audience} polished leather oxford shoes`)
    };
  case "luxury":
    return {
      ...base,
      id: "luxury-evening-dress-shoes",
      name: "Sleek evening dress shoes",
      brand: "StyleIA Market",
      price: "$156",
      matchReason: "A polished low-profile shape keeps the night-out look refined.",
      merchantURL: shopURL(`${audience} sleek black evening shoes`)
    };
  case "streetwear":
    return {
      ...base,
      id: "streetwear-statement-sneakers",
      name: "Statement sneakers",
      brand: "StyleIA Market",
      price: "$112",
      matchReason: "Bold soles balance the layered streetwear proportions.",
      merchantURL: shopURL(`${audience} statement sneakers streetwear`)
    };
  case "sporty":
    return {
      ...base,
      id: "sporty-technical-trainers",
      name: "Technical trainers",
      brand: "StyleIA Market",
      price: "$96",
      matchReason: "Performance shapes keep the sporty outfit intentional and clean.",
      merchantURL: shopURL(`${audience} clean performance trainers`)
    };
  default:
    return {
      ...base,
      id: "casual-low-profile-sneakers",
      name: "Streamlined sneakers",
      brand: "StyleIA Market",
      price: "$84",
      matchReason: "Simple low-profile shoes balance relaxed proportions.",
      merchantURL: shopURL(`${audience} white low profile sneakers`)
    };
  }
}

function frameProduct(styleGoal, imageURL, profile = {}) {
  const audience = profile.subjectGender === "female" ? "women" : "men";
  const base = {
    category: "frames",
    styleGoal,
    imageURL
  };

  switch (styleGoal) {
  case "professional":
    return {
      ...base,
      id: "professional-clear-angular-frames",
      name: "Clear angular frames",
      brand: "StyleIA Market",
      price: "$72",
      matchReason: "Sharper transparent lines reinforce a clean work-ready face shape.",
      merchantURL: shopURL(`${audience} clear angular eyeglasses`)
    };
  case "luxury":
    return {
      ...base,
      id: "luxury-rounded-dark-frames",
      name: "Rounded dark frames",
      brand: "StyleIA Market",
      price: "$92",
      matchReason: "Rounded dark frames soften the jaw while keeping the look elevated.",
      merchantURL: shopURL(`${audience} rounded dark eyeglasses`)
    };
  case "streetwear":
    return {
      ...base,
      id: "streetwear-bold-acetate-frames",
      name: "Bold acetate frames",
      brand: "StyleIA Market",
      price: "$88",
      matchReason: "Heavier acetate frames add visual weight to layered outfits.",
      merchantURL: shopURL(`${audience} bold acetate eyeglasses`)
    };
  default:
    return {
      ...base,
      id: "casual-soft-rectangular-frames",
      name: "Soft rectangular frames",
      brand: "StyleIA Market",
      price: "$68",
      matchReason: "Balanced proportions keep the face open and natural.",
      merchantURL: shopURL(`${audience} soft rectangular eyeglasses`)
    };
  }
}

function shopURL(query) {
  return `https://www.google.com/search?tbm=shop&q=${encodeURIComponent(query)}`;
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

function normalizeStyleGoals(primaryGoal, requestedGoals) {
  const requested = Array.isArray(requestedGoals) ? requestedGoals : [];
  const goals = [primaryGoal, ...requested]
    .map((goal) => String(goal || "").trim())
    .filter((goal) => Object.prototype.hasOwnProperty.call(styleCatalog, goal));

  const normalized = [...new Set(goals)].slice(0, 5);
  return normalized.length > 0 ? normalized : ["casual"];
}

function mockVariants(imageURL, lookGoals, profile = {}, styleSignature = {}, jobId = "mock") {
  return lookGoals.map((goal, index) => {
    const assetURLs = {
      outfit: imageURL,
      shoes: imageURL,
      frames: imageURL,
      accessories: imageURL
    };

    return {
      id: `${jobId}-${goal}-${index + 1}`,
      styleGoal: goal,
      title: styleCatalog[goal]?.title || "Style Fit",
      subtitle: styleCatalog[goal]?.subtitle || "Generated look",
      imageURL,
      assetURLs,
      products: productMatches({ styleGoal: goal, assetURLs, profile })
    };
  });
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

function serializeFalError(error) {
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
