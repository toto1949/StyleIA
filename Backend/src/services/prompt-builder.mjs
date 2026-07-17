// Prompt builder for FLUX Kontext — an instruction-following image EDITING
// model. It responds best to clear natural-language sentences that say what
// to change and, critically, what to KEEP. Identity must lead the prompt:
// Kontext attends more strongly to early instructions. It has no negative-
// prompt input: naming unwanted concepts ("no beard", "cartoon") can make
// them MORE likely, so everything below is phrased as what to preserve.

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
  "red-carpet": "Light it with crisp paparazzi flash against the glowing step-and-repeat backdrop, glossy premiere-night glamour.",
  "studio-headshot": "Compose a clean, LinkedIn-ready studio portrait with soft key light, subtle rim separation and an uncluttered grey backdrop.",
  "executive-office": "Frame a quiet-power editorial inside the corner office, skyline soft behind the glass, warm wood and polished surfaces grounding the shot.",
  "keynote-stage": "Shoot it like a keynote still: soft stage spotlights, glowing screen behind, the auditorium falling into dark bokeh.",
  "summer-beach-club": "Keep it sun-drenched beach-club editorial, white daybeds and turquoise water filling the depth behind the subject.",
  "fireworks-night": "Compose a festive rooftop night still, fireworks bursting overhead, warm sparkler light catching the subject."
};

const categorySignatures = {
  urban: "Give it authentic street-photography energy, the subject sharp against the motion of the city.",
  luxury: "Compose it like a polished luxury-magazine editorial, aspirational and refined.",
  nature: "Frame it like epic travel photography, the landscape vast and breathtaking around the subject.",
  events: "Capture a VIP event-photography feel, the atmosphere electric around the subject.",
  professional: "Keep it polished and corporate-editorial, clean light and a confident, camera-ready presence.",
  custom: ""
};

export const allowedTimes = Object.keys(timeMap);
export const allowedWeather = Object.keys(weatherMap);
export const allowedPoses = Object.keys(poseMap);

const REALISM_SENTENCE =
  "Photorealistic full-frame photograph, 50mm lens at f/2.8: natural skin texture with visible pores, true-to-photo skin tone, anatomically correct hands with five fingers each, natural body proportions, sharp focus on the faces, cinematic color grading.";

const ANTI_BEAUTIFY =
  "Keep every unique and imperfect detail exactly as photographed — do not beautify, smooth, slim, retouch, de-age, reshape or idealize the face or body, and do not replace anyone with a generic attractive model.";

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

  if (hasCompanion && companionKind === "friend") {
    return buildFriendPrompt({ scene, timeOfDay, weather, pose, subjectGender: gender, reroll });
  }

  if (hasCompanion && companionKind === "pet") {
    return buildPetPrompt({ scene, timeOfDay, weather, pose, subjectGender: gender, reroll });
  }

  return buildSoloPrompt({ scene, timeOfDay, weather, pose, subjectGender: gender, reroll });
}

/// Solo generation: identity FIRST, then scene/outfit edit.
function buildSoloPrompt({ scene, timeOfDay, weather, pose, subjectGender, reroll }) {
  const noun = subjectNoun(subjectGender);
  const outfit = outfitFor(scene, subjectGender);
  const weatherText = weatherTextFor(weather, timeOfDay);

  const sentences = [
    // 1. Identity lock leads — Kontext weights early instructions most heavily.
    identityLead(subjectGender, noun),

    // 2. The edit: place that same person into the scene.
    `Place this exact same ${noun} ${scene.base_prompt}, under ${timeMap[timeOfDay] || timeMap.golden_hour}, with ${weatherText}.`,

    // 3. Outfit — clothes change; face and body do not.
    `Change only the clothing: dress them in ${outfit}. The clothing must fit their real body shape and weight with natural fabric drape, realistic seams and correct proportions. Keep the face, hair, skin and body completely unchanged.`,

    // 4. Pose + scene signature.
    `They are ${poseMap[pose] || poseMap.casual}. ${signatureFor(scene)}`.trim(),

    // 5. Hard identity reinforcement (gender-aware).
    identityDetails(subjectGender),

    ANTI_BEAUTIFY,

    "Exactly one person appears in the scene.",

    "Full-body vertical composition with the subject as the clear focal point, visible from head to shoes, feet and footwear inside the frame, camera at chest height.",

    REALISM_SENTENCE
  ];

  if (reroll) {
    sentences.push("Change only the outfit into a completely different style and color palette than before, while keeping the face, hair, body, pose, scene and background exactly the same.");
  }

  return sentences.filter(Boolean).join(" ");
}

/// Two-person prompt. image_urls arrive as [subject, companion].
/// Map them explicitly so faces are never swapped or blended.
function buildFriendPrompt({ scene, timeOfDay, weather, pose, subjectGender, reroll }) {
  const weatherText = weatherTextFor(weather, timeOfDay);
  const primaryNoun = subjectNoun(subjectGender);
  const outfitTheme = scene.default_outfit;

  const sentences = [
    "This is a multi-image identity edit using two reference photos.",

    `Image 1 is the primary ${primaryNoun === "person" ? "person" : primaryNoun}; Image 2 is their friend. Keep each face locked to its own source photo.`,

    `Place the exact same person from Image 1 and the exact same person from Image 2 together ${scene.base_prompt}, under ${timeMap[timeOfDay] || timeMap.golden_hour}, with ${weatherText}.`,

    `Dress each person individually in clothing from this theme: ${outfitTheme}. Style each outfit to match that person's own gender, body shape and proportions — never force one person's clothing style onto the other. Keep both faces, hairstyles and bodies completely unchanged.`,

    `They stand side by side, close and interacting warmly and naturally, each ${poseMap[pose] || poseMap.casual}. ${signatureFor(scene)}`.trim(),

    friendIdentitySentence(),

    ANTI_BEAUTIFY,

    "Exactly two people appear in the frame. The person on the viewer's left or as the primary subject comes only from Image 1; the other person comes only from Image 2. Both are fully visible, standing a natural distance apart — never merge them into one face or body.",

    "Full-body vertical composition with both people sharing the focal point, both visible from head to shoes, all feet and footwear inside the frame, camera at chest height.",

    REALISM_SENTENCE
  ];

  if (reroll) {
    sentences.push("Change only the outfits into a completely different style and color palette than before, while keeping both faces, hairstyles, bodies, poses, the scene and the background exactly the same.");
  }

  return sentences.filter(Boolean).join(" ");
}

/// Human + pet: keep the human identity lock as strong as solo, plus pet fidelity.
function buildPetPrompt({ scene, timeOfDay, weather, pose, subjectGender, reroll }) {
  const noun = subjectNoun(subjectGender);
  const outfit = outfitFor(scene, subjectGender);
  const weatherText = weatherTextFor(weather, timeOfDay);

  const sentences = [
    identityLead(subjectGender, noun),

    `Place this exact same ${noun} ${scene.base_prompt}, under ${timeMap[timeOfDay] || timeMap.golden_hour}, with ${weatherText}.`,

    `Dress them in ${outfit}; the clothing fits their real body shape with natural fabric drape, realistic seams and correct proportions. Keep the face, hair, skin and body completely unchanged.`,

    `They are ${poseMap[pose] || poseMap.casual}. ${signatureFor(scene)}`.trim(),

    identityDetails(subjectGender),

    "Their pet from Image 2 / the second input photo joins them naturally at their side. Keep the pet's species, breed, size, fur color, face and unique markings exactly identical to its photo.",

    ANTI_BEAUTIFY,

    "Exactly one person and one pet appear in the scene.",

    "Full-body vertical composition with the person as the clear focal point, visible from head to shoes, feet and footwear inside the frame, camera at chest height.",

    REALISM_SENTENCE
  ];

  if (reroll) {
    sentences.push("Change only the outfit into a completely different style and color palette than before, while keeping the face, pet, pose, scene and background exactly the same.");
  }

  return sentences.filter(Boolean).join(" ");
}

function weatherTextFor(weather, timeOfDay) {
  return weather === "sunny" && timeOfDay === "night"
    ? "a clear night sky, crisp air, stars faintly visible"
    : weatherMap[weather] || weatherMap.sunny;
}

export const allowedMotionStyles = ["cinematic", "talking", "portrait", "energy"];

/// Cinematic motion prompt for image-to-video, derived from the generated still.
/// PixVerse responds best to full sentences that describe restrained, layered
/// motion; over-promising action is what causes face morphing and warping.
///
/// motionStyle:
///   cinematic — default living editorial push-in
///   talking   — interview / talk-show speaking performance (+ optional caption line)
///   portrait  — near-still beauty/portrait breathing shot
///   energy    — ambient-heavy scene life (weather, crowd, lights)
export function buildVideoPrompt({
  scene,
  timeOfDay,
  weather,
  pose,
  motionStyle = "cinematic",
  spokenLine = ""
}) {
  const style = normalizeMotionStyle(motionStyle);
  const line = sanitizeSpokenLine(spokenLine);

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

  const ambient = ambientMotion[weather] || ambientMotion.sunny;
  const time = timeMotion[timeOfDay] || timeMotion.golden_hour;
  const identity =
    "The person's face, identity, hairstyle, body and outfit remain perfectly consistent with the input image in every single frame, sharp, stable and photorealistic.";

  if (style === "talking") {
    const speech = line
      ? `They are mid-conversation, speaking these words with natural lip motion and expressive but subtle facial acting: "${line}".`
      : "They are mid-conversation, speaking with natural lip motion, soft jaw movement and expressive but subtle facial acting, as if answering a question on a talk show or interview.";

    const caption = line
      ? `Burn a clean, readable lower-third caption across the bottom of the frame with the exact text: "${line}". White sans-serif letters with a soft dark shadow or bar for contrast, television-interview style, stable and sharp for the whole clip.`
      : "No on-screen caption text.";

    return [
      `A living talk-show / interview moment ${scene.base_prompt}.`,
      speech,
      "Natural micro-gestures: a slight head nod, soft hand motion near the torso, confident eye contact toward camera or an off-camera host.",
      `Around them, ${ambient}, with ${time}.`,
      "Camera work: locked-off or very slow subtle push-in, broadcast-interview framing, no whip pans, no cuts.",
      caption,
      identity
    ].join(" ");
  }

  if (style === "portrait") {
    return [
      `An intimate living portrait ${scene.base_prompt}.`,
      "The person stays nearly still, breathing softly, with a tiny natural blink and a gentle, almost imperceptible smile.",
      `Hair and fabric move only slightly. Around them, ${ambient}, with ${time}.`,
      "Camera work: extremely slow, elegant push-in, shallow depth of field, beauty-editorial stillness.",
      identity
    ].join(" ");
  }

  if (style === "energy") {
    return [
      `A high-atmosphere living scene ${scene.base_prompt}.`,
      "The person holds a confident presence with restrained body motion while the world around them feels alive.",
      `Around them, ${ambient}, with ${time}, plus richer environmental life — distant figures, light flicker, air and atmosphere moving with realistic physics.`,
      "Camera work: smooth cinematic drift or gentle orbiting push, stabilized, no cuts.",
      identity
    ].join(" ");
  }

  // cinematic (default)
  const subjectMotion = pose === "walking"
    ? "The person walks forward slowly with a confident natural gait, arms swinging gently."
    : pose === "action"
      ? "The person moves with restrained dynamic energy, smooth and controlled."
      : "The person stands nearly still, breathing naturally, giving a slight relaxed head turn and a hint of a smile while hair and clothing sway gently.";

  return [
    `A cinematic living moment ${scene.base_prompt}.`,
    subjectMotion,
    `Around them, ${ambient}, with ${time}.`,
    "The background breathes with subtle life — distant figures, light and atmosphere shifting naturally, realistic physics.",
    "Camera work: one slow, smooth stabilized push-in toward the subject, no cuts, no whip pans, shallow cinematic depth of field.",
    identity
  ].join(" ");
}

export function normalizeMotionStyle(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return allowedMotionStyles.includes(normalized) ? normalized : "cinematic";
}

export function sanitizeSpokenLine(value) {
  return String(value || "")
    .replace(/[\r\n]+/g, " ")
    .replace(/[^\p{L}\p{N}\s.,'!?&-]/gu, "")
    .replace(/\s{2,}/g, " ")
    .trim()
    .slice(0, 120);
}

export function videoCacheKey(motionStyle, spokenLine) {
  return `${normalizeMotionStyle(motionStyle)}|${sanitizeSpokenLine(spokenLine)}`;
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

function identityLead(_gender, noun) {
  // Same face-lock language for every subject — only the noun differs (man/woman/person).
  return `This is a face-preserving edit of a real ${noun} from the input photo. Critically important: keep the person's face 100% identical to the input photo — the exact same ${noun}, instantly recognizable as this specific individual.`;
}

function identityDetails(gender) {
  // Identical identity lock for male and female. Outfit stays gender-aware elsewhere;
  // face instructions must not special-case or "enhance" women differently.
  const parts = [
    "Preserve the exact same face geometry and proportions",
    "the same eye shape and spacing, eyebrows, nose shape, mouth and lip shape",
    "the same jawline, cheekbones, chin and hairline",
    "the same skin tone, complexion and texture",
    "the same apparent age",
    "the same body shape, height impression and weight",
    "the same hair color, hair length, hairline and hairstyle",
    "and any glasses, freckles, moles, scars or facial marks in exactly the same places"
  ];

  if (gender === "male") {
    parts.push("keep any facial hair in exactly the same shape, length and density as the photo, including a clean-shaven look if that is what the photo shows");
  }

  return `${parts.join(", ")}.`;
}

function friendIdentitySentence() {
  return [
    "Critically important: keep the first person's face 100% identical to Image 1 / the first input photo",
    "and the second person's face 100% identical to Image 2 / the second input photo",
    "For each person preserve the exact same face geometry, eyes, eyebrows, nose, mouth, lips, jawline, cheekbones, skin tone, apparent age, body shape, hair color, length and hairstyle",
    "plus any glasses, freckles, moles or marks",
    "Never swap, blend, merge, average or mix the two faces",
    "never copy one person's features onto the other",
    "and never invent a third person",
    "Each must stay instantly recognizable as the specific individual from their own input photo"
  ].join(". ") + ".";
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
