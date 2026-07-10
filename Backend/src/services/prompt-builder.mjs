const timeMap = {
  morning: "soft morning light, golden sunrise tones, gentle long shadows",
  golden_hour: "warm golden hour light, long cinematic shadows, amber glow on skin and surfaces",
  night: "dramatic night lighting, artificial lights, rich shadow depth"
};

const weatherMap = {
  sunny: "clear blue sky, bright natural sunlight, crisp visibility",
  rainy: "rain falling, wet reflective streets, person holding an umbrella, water droplets catching the light",
  snowy: "snow falling softly, snow dusting surfaces, breath visible in the cold air",
  foggy: "atmospheric fog, moody diffused light, soft depth haze"
};

const poseMap = {
  casual: "relaxed natural standing pose, weight on one leg, at ease",
  walking: "mid-stride walking motion, candid street-photography energy",
  candid: "looking away from camera, caught in a natural unposed moment",
  sitting: "sitting naturally with relaxed posture",
  action: "dynamic action pose, energetic and full of movement"
};

export const allowedTimes = Object.keys(timeMap);
export const allowedWeather = Object.keys(weatherMap);
export const allowedPoses = Object.keys(poseMap);

const REROLL_SUFFIX = "completely different outfit than before, same scene, same face, same background";

const QUALITY_BLOCK = [
  "photorealistic",
  "ultra detailed",
  "natural skin texture with visible pores",
  "accurate color of skin, hair, and eyes matching the input photo",
  "cinematic color grading",
  "shot on a professional full-frame camera, 50mm lens, f/2.8",
  "sharp focus on the subject"
].join(", ");

const ANATOMY_BLOCK = [
  "realistic human anatomy",
  "correct hands with five fingers each",
  "no duplicated or missing limbs",
  "no cropped head, no cropped feet",
  "natural body proportions matching the input photo"
].join(", ");

export function buildPrompt({
  scene,
  timeOfDay,
  weather,
  pose,
  subjectGender = "auto",
  hasCompanion = false,
  reroll = false
}) {
  const base = scene.base_prompt;
  const outfit = outfitFor(scene, subjectGender);
  const gender = normalizeSubjectGender(subjectGender);

  // "clear blue sky, bright sunlight" contradicts night scenes, so swap in a night-safe clear-sky phrase.
  const weatherText = weather === "sunny" && timeOfDay === "night"
    ? "clear night sky, crisp air, stars faintly visible"
    : weatherMap[weather] || weatherMap.sunny;

  const parts = [
    `The exact same ${subjectNoun(gender)} from the input image, now ${base}`,
    `wearing ${outfit}, the outfit fits the body naturally with realistic fabric drape`,
    timeMap[timeOfDay] || timeMap.golden_hour,
    weatherText,
    poseMap[pose] || poseMap.casual,
    identityBlock(gender),
    hasCompanion
      ? "exactly two people together naturally in the scene, both faces preserved exactly from the input images, natural interaction between them"
      : "exactly one person in the scene",
    "the subject is the clear focal point, centered, visible from head to shoes, feet and shoes in frame",
    "vertical full-body composition, camera at chest height",
    ANATOMY_BLOCK,
    QUALITY_BLOCK,
    negativeBlock(gender)
  ];

  if (reroll) {
    parts.push(REROLL_SUFFIX);
  }

  return parts.filter(Boolean).join(", ");
}

/// Cinematic motion prompt for image-to-video, derived from the generated still.
export function buildVideoPrompt({ scene, timeOfDay, weather, pose }) {
  const ambientMotion = {
    sunny: "sunlight shimmering subtly, gentle breeze moving hair and clothing",
    rainy: "rain falling steadily, droplets splashing, reflections rippling on wet ground",
    snowy: "snowflakes drifting down slowly, soft breath fog in the cold air",
    foggy: "fog drifting slowly across the scene, light beams shifting through the haze"
  };

  const timeMotion = {
    morning: "soft morning light slowly warming the scene",
    golden_hour: "golden light flickering gently as the sun sits low",
    night: "neon and artificial lights glowing and subtly flickering"
  };

  const subjectMotion = pose === "walking"
    ? "the person walks forward slowly and confidently, natural gait"
    : pose === "action"
      ? "the person moves with subtle dynamic energy"
      : "the person stands nearly still, breathing naturally, slight head turn, hair and clothing moving gently";

  return [
    `Cinematic live scene: ${scene.base_prompt}`,
    subjectMotion,
    ambientMotion[weather] || ambientMotion.sunny,
    timeMotion[timeOfDay] || timeMotion.golden_hour,
    "background alive with subtle natural movement",
    "slow smooth cinematic camera push-in",
    "preserve the person's exact appearance, face, and outfit from the input image",
    "photorealistic, stable, no morphing, no warping of the face"
  ].join(", ");
}

function outfitFor(scene, subjectGender) {
  const gender = normalizeSubjectGender(subjectGender);
  if (gender === "male" && scene.male_outfit) {
    return scene.male_outfit;
  }
  if (gender === "female" && scene.female_outfit) {
    return scene.female_outfit;
  }
  return scene.default_outfit;
}

function subjectNoun(gender) {
  if (gender === "male") {
    return "adult man";
  }
  if (gender === "female") {
    return "adult woman";
  }
  return "person";
}

function identityBlock(gender) {
  const base = [
    "preserve the exact facial identity from the input photo",
    "same face geometry, same eyes, nose, mouth, jawline, and hairline",
    "same skin tone, same age, same hair color and hairstyle",
    "keep glasses, freckles, moles, or facial marks if present",
    "do not beautify into a different person, do not change ethnicity, do not change gender identity"
  ];

  if (gender === "male") {
    base.push("preserve beard or facial hair shape exactly if present");
  } else if (gender === "female") {
    base.push("preserve existing makeup or makeup-free appearance exactly, do not masculinize the face");
  }

  return base.join(", ");
}

function negativeBlock(gender) {
  const common = "negative prompt: different person, changed identity, face swap artifacts, distorted or blurry face, plastic skin, bad anatomy, extra limbs, extra fingers, fused fingers, duplicate person, cartoon, illustration, painting, 3d render, mannequin, watermark, text, logo overlay";

  if (gender === "male") {
    return `${common}, feminine face, makeup, woman, girl`;
  }
  if (gender === "female") {
    return `${common}, masculine face, beard, mustache, man, boy`;
  }
  return common;
}

export function normalizeSubjectGender(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (["male", "man", "men", "m"].includes(normalized)) {
    return "male";
  }
  if (["female", "woman", "women", "f"].includes(normalized)) {
    return "female";
  }
  return "auto";
}

export function normalizeTimeOfDay(value, scene) {
  const normalized = String(value || "").trim().toLowerCase();
  if (scene.available_times.includes(normalized)) {
    return normalized;
  }
  return scene.default_time || scene.available_times[0];
}

export function normalizeWeather(value, scene) {
  const normalized = String(value || "").trim().toLowerCase();
  if (scene.available_weather.includes(normalized)) {
    return normalized;
  }
  return scene.default_weather || scene.available_weather[0];
}

export function normalizePose(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return allowedPoses.includes(normalized) ? normalized : "casual";
}

/// Builds a sanitized scene object from a user-described custom template.
export function buildCustomScene({ name, basePrompt, outfit }) {
  const cleanName = sanitizeText(name, 60) || "Custom Scene";
  const cleanPrompt = sanitizeText(basePrompt, 400);
  const cleanOutfit = sanitizeText(outfit, 200);

  if (!cleanPrompt) {
    return null;
  }

  return {
    id: "custom",
    name: cleanName,
    location: "Custom Scene",
    category: "custom",
    description: cleanPrompt.slice(0, 80),
    base_prompt: cleanPrompt,
    default_outfit: cleanOutfit || "a stylish outfit that naturally fits the described scene, editorial fashion quality",
    available_times: allowedTimes,
    available_weather: allowedWeather,
    default_time: "golden_hour",
    default_weather: "sunny",
    badge: null
  };
}

function sanitizeText(value, maxLength) {
  return String(value || "")
    .replace(/[\r\n]+/g, " ")
    .replace(/[^\p{L}\p{N}\s.,'&/()!?-]/gu, "")
    .replace(/\s{2,}/g, " ")
    .trim()
    .slice(0, maxLength);
}
