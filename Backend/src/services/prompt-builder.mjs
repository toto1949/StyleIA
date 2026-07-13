// Prompt builder for FLUX Kontext — an instruction-following image EDITING
// model. It responds best to clear natural-language sentences that say what
// to change and, critically, what to KEEP. It has no negative-prompt input:
// naming unwanted concepts ("no beard", "no cartoon") makes them MORE likely,
// so everything below is phrased positively.

const timeMap = {
  morning: "soft morning light with golden sunrise tones and gentle long shadows",
  golden_hour: "warm golden hour light, low sun, long cinematic shadows, amber glow on skin and surfaces",
  night: "dramatic night lighting from artificial sources with rich shadow depth"
};

const weatherMap = {
  sunny: "a clear blue sky and bright natural sunlight with crisp visibility",
  rainy: "steady rain, wet reflective streets, the person holding an umbrella, droplets catching the light",
  snowy: "snow falling softly, a light dusting of snow on surfaces, breath visible in the cold air",
  foggy: "atmospheric fog with moody diffused light and soft depth haze"
};

const poseMap = {
  casual: "standing in a relaxed natural pose, weight on one leg, at ease",
  walking: "walking mid-stride with candid street-photography energy",
  candid: "looking away from the camera, caught in a natural unposed moment",
  sitting: "sitting naturally with relaxed posture",
  action: "in a dynamic action pose, energetic and full of movement"
};

// A distinct photographic identity per scene, so a Santorini shot and a
// Shibuya shot feel like they came from two different editorial shoots
// instead of the same template with a swapped backdrop.
const sceneSignatures = {
  "times-square": "Shoot from a slightly low angle so the glowing billboards tower behind the subject, neon color spill reflecting subtly on their skin and outfit.",
  "paris-cafe": "Frame it like an intimate street-style story beside a marble bistro table, warm café glow, the boulevard melting into soft romantic bokeh.",
  "tokyo-shibuya": "Give it a cinematic Tokyo night-street look, neon signage glowing in the bokeh, wet-pavement reflections adding depth around the subject.",
  "dubai-rooftop": "Compose it as a sleek high-fashion editorial with the skyline sweeping behind, warm sunset rim light tracing the subject.",
  "santorini": "Keep the frame bright and airy like a travel editorial, white Cycladic architecture cascading behind, the sea breeze moving fabric and hair.",
  "sahara-desert": "Use an epic wide cinematic frame, a dune ridgeline leading the eye to the subject, wind lifting fine sand off the crest.",
  "northern-lights": "Style it like a long-exposure night photograph, the aurora glowing overhead, cool green rim light outlining the subject against the dark landscape.",
  "maldives-villa": "Compose a serene barefoot-luxury editorial, turquoise lagoon glowing behind, soft tropical light wrapping the subject.",
  "hotel-lobby": "Use a grand, almost symmetrical composition between the marble columns, warm chandelier light layering the depth behind the subject.",
  "f1-paddock": "Shoot it like dynamic motorsport reportage, the race car and pit garage in energetic bokeh, glossy floor reflections under the subject.",
  "yacht-mediterranean": "Frame a sun-drenched nautical editorial, the deck lines leading to the subject, sunlight sparkling off the sea behind.",
  "art-gallery": "Compose with minimalist gallery restraint, generous negative space on the white walls, a precise museum spotlight sculpting the subject.",
  "nba-courtside": "Make it feel like a candid celebrity courtside photo, arena floodlights and jumbotron glow, the game alive but blurred behind.",
  "coachella": "Bathe the frame in golden festival haze, the ferris wheel silhouetted behind, a touch of warm lens flare.",
  "red-carpet": "Light it with crisp paparazzi flash against the glowing step-and-repeat backdrop, glossy premiere-night glamour."
};

const categorySignatures = {
  urban: "Give it authentic street-photography energy, the subject sharp against the motion of the city.",
  luxury: "Compose it like a polished luxury-magazine editorial, aspirational and refined.",
  nature: "Frame it like epic travel photography, the landscape vast and breathtaking around the subject.",
  events: "Capture a VIP event-photography feel, the atmosphere electric around the subject.",
  custom: ""
};

export const allowedTimes = Object.keys(timeMap);
export const allowedWeather = Object.keys(weatherMap);
export const allowedPoses = Object.keys(poseMap);

// Shared realism/craft instruction used by every generation path.
const REALISM_SENTENCE =
  "Render it as a photorealistic photograph shot on a professional full-frame camera with a 50mm lens at f/2.8: natural skin texture with visible pores, true-to-photo skin tone, anatomically correct hands with five fingers each, natural body proportions, sharp focus, cinematic color grading.";

export function buildPrompt({
  scene,
  timeOfDay,
  weather,
  pose,
  subjectGender = "auto",
  hasCompanion = false,
  companionKind = "friend",
  reroll = false
}) {
  const gender = normalizeSubjectGender(subjectGender);

  // A human companion is a fundamentally different, two-source composition and
  // needs its own prompt so faces aren't swapped/merged and each person gets
  // their own suitable outfit.
  if (hasCompanion && companionKind === "friend") {
    return buildFriendPrompt({ scene, timeOfDay, weather, pose, reroll });
  }

  const noun = subjectNoun(gender);
  const outfit = outfitFor(scene, gender);

  // "clear blue sky, bright sunlight" contradicts night scenes, so swap in a night-safe clear-sky phrase.
  const weatherText = weatherTextFor(weather, timeOfDay);

  const sentences = [
    // 1. The edit instruction: what changes.
    `Place the exact same ${noun} from the input photo ${scene.base_prompt}, under ${timeMap[timeOfDay] || timeMap.golden_hour}, with ${weatherText}.`,

    // 2. Outfit swap.
    `Dress them in ${outfit}; the clothing fits their real body shape with natural fabric drape, realistic seams and correct proportions.`,

    // 3. Pose + scene-specific photographic identity.
    `They are ${poseMap[pose] || poseMap.casual}. ${signatureFor(scene)}`.trim(),

    // 4. Identity lock: what must NOT change (phrased as what to keep).
    identitySentence(gender),

    // 5. Person count (+ pet, if any).
    companionSentence(hasCompanion, companionKind),

    // 6. Framing.
    "Full-body vertical composition with the subject as the clear focal point, visible from head to shoes, feet and footwear inside the frame, camera at chest height.",

    // 7. Realism and craft.
    REALISM_SENTENCE
  ];

  if (reroll) {
    sentences.push("Change only the outfit into a completely different style and color palette than before, while keeping the face, pose, scene and background exactly the same.");
  }

  return sentences.filter(Boolean).join(" ");
}

/// Two-person prompt for a human companion. Input images arrive as
/// [subject, companion]; the prompt maps them to "first" and "second" person,
/// styles each individually (no single gendered outfit forced on both), and
/// locks each face to its own source so they aren't blended or swapped.
function buildFriendPrompt({ scene, timeOfDay, weather, pose, reroll }) {
  const weatherText = weatherTextFor(weather, timeOfDay);
  const outfitTheme = scene.default_outfit;

  const sentences = [
    `Combine two real people into one photograph — the person from the first input image and the person from the second input image, together ${scene.base_prompt}, under ${timeMap[timeOfDay] || timeMap.golden_hour}, with ${weatherText}.`,

    `Dress each person individually in ${outfitTheme}, tailored to suit that specific person and matching their own gender and body, with natural fabric drape, realistic seams and correct proportions on each of them.`,

    `They stand together side by side, close and interacting warmly and naturally, each ${poseMap[pose] || poseMap.casual}. ${signatureFor(scene)}`.trim(),

    friendIdentitySentence(),

    "Exactly two people appear: the first person's face and body come only from the first input image, and the second person's face and body come only from the second input image, standing a natural distance apart with both fully visible.",

    "Full-body vertical composition with both people sharing the focal point, both visible from head to shoes, all feet and footwear inside the frame, camera at chest height.",

    REALISM_SENTENCE
  ];

  if (reroll) {
    sentences.push("Change only the outfits into a completely different style and color palette than before, while keeping both faces, their poses, the scene and the background exactly the same.");
  }

  return sentences.filter(Boolean).join(" ");
}

function weatherTextFor(weather, timeOfDay) {
  return weather === "sunny" && timeOfDay === "night"
    ? "a clear night sky, crisp air, stars faintly visible"
    : weatherMap[weather] || weatherMap.sunny;
}

/// Cinematic motion prompt for image-to-video, derived from the generated still.
/// PixVerse responds best to full sentences that describe restrained, layered
/// motion; over-promising action is what causes face morphing and warping.
export function buildVideoPrompt({ scene, timeOfDay, weather, pose }) {
  const ambientMotion = {
    sunny: "sunlight shimmers softly and a gentle breeze moves hair and fabric",
    rainy: "steady rain falls, droplets splash and reflections ripple across the wet ground",
    snowy: "snowflakes drift down slowly and breath fogs faintly in the cold air",
    foggy: "fog drifts slowly through the frame while diffused light shifts in the haze"
  };

  const timeMotion = {
    morning: "soft morning light gradually warming the scene",
    golden_hour: "low golden sunlight glowing warmly, flaring gently across the lens",
    night: "city lights and signage glowing steadily with a subtle shimmer"
  };

  const subjectMotion = pose === "walking"
    ? "The person walks forward slowly with a confident natural gait, arms swinging gently."
    : pose === "action"
      ? "The person moves with restrained dynamic energy, smooth and controlled."
      : "The person stands nearly still, breathing naturally, giving a slight relaxed head turn and a hint of a smile while hair and clothing sway gently.";

  return [
    `A cinematic living moment ${scene.base_prompt}.`,
    subjectMotion,
    `Around them, ${ambientMotion[weather] || ambientMotion.sunny}, with ${timeMotion[timeOfDay] || timeMotion.golden_hour}.`,
    "The background breathes with subtle life — distant figures, light and atmosphere shifting naturally, realistic physics.",
    "Camera work: one slow, smooth stabilized push-in toward the subject, no cuts, no whip pans, shallow cinematic depth of field.",
    "The person's face, identity, hairstyle, body and outfit remain perfectly consistent with the input image in every single frame, sharp, stable and photorealistic."
  ].join(" ");
}

function companionSentence(hasCompanion, companionKind) {
  if (!hasCompanion) {
    return "Exactly one person appears in the scene.";
  }

  if (companionKind === "pet") {
    return "The person's pet from the second input photo joins them naturally at their side; keep the pet's species, breed, size, fur color and unique markings exactly identical to its photo. Exactly one person and one pet appear in the scene.";
  }

  return "Exactly two people share the scene naturally, interacting warmly; both faces are kept perfectly identical to their respective input photos.";
}

export function normalizeCompanionKind(value) {
  return String(value || "").trim().toLowerCase() === "pet" ? "pet" : "friend";
}

function signatureFor(scene) {
  return sceneSignatures[scene.id] || categorySignatures[scene.category] || "";
}

function outfitFor(scene, gender) {
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

function identitySentence(gender) {
  const parts = [
    "Critically important: this is a face-preserving edit — keep the person's face 100% identical to the input photo",
    "the exact same face geometry and proportions, eyes, eyebrows, nose, mouth, lips, jawline, cheekbones and hairline",
    "the same skin tone and complexion, the same apparent age, the same body shape and weight",
    "the same hair color, length and hairstyle",
    "and any glasses, freckles, moles, scars or facial marks kept exactly where they are"
  ];

  if (gender === "male") {
    parts.push("his facial hair kept in exactly the same shape, length and density as the photo");
  } else if (gender === "female") {
    parts.push("her exact same facial features and natural look preserved, with any makeup or bare-skin look kept as in the photo");
  }

  // FLUX tends to beautify/idealize faces (especially women); this clause is
  // what counteracts that drift and keeps the result recognizable.
  return `${parts.join(", ")}. Do not beautify, smooth, slim, retouch, de-age or idealize the face or body in any way, and do not turn them into a generic attractive model — keep their real, unique features exactly, even if imperfect. The face must remain instantly recognizable as this exact same person, as if they were truly photographed on location.`;
}

function friendIdentitySentence() {
  return "Critically important: keep the first person's face 100% identical to the first input photo and the second person's face 100% identical to the second input photo — for each of them the exact same face geometry, eyes, nose, mouth, jawline, cheekbones, skin tone, apparent age, body shape, hair color, length and hairstyle, plus any glasses, freckles, moles or marks. Never swap, blend, merge, average or mix up the two faces, and never copy one person's features onto the other. Do not beautify, slim or idealize either person. Each must stay instantly recognizable as the specific individual from their own input photo.";
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
