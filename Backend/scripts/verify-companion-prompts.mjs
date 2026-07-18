/// Regression check: companion gender pairings must produce distinct, locked prompts.
/// Run: node scripts/verify-companion-prompts.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildPrompt, buildVideoPrompt } from "../src/services/prompt-builder.mjs";

const root = dirname(fileURLToPath(import.meta.url));
const scenes = JSON.parse(readFileSync(join(root, "../data/scenes.json"), "utf8")).scenes;
const scene = scenes.find((item) => item.id === "paris-cafe") || scenes[0];

function promptFor({ subjectGender, companionGender, companionKind }) {
  return buildPrompt({
    scene,
    timeOfDay: "golden_hour",
    weather: "sunny",
    pose: "casual",
    subjectGender,
    hasCompanion: true,
    companionKind,
    companionGender
  });
}

const maleMale = promptFor({ subjectGender: "male", companionGender: "male", companionKind: "friend" });
const maleFemale = promptFor({ subjectGender: "male", companionGender: "female", companionKind: "friend" });
const femaleFemale = promptFor({ subjectGender: "female", companionGender: "female", companionKind: "friend" });
const femaleMale = promptFor({ subjectGender: "female", companionGender: "male", companionKind: "friend" });
const femalePet = promptFor({ subjectGender: "female", companionGender: "auto", companionKind: "pet" });
const malePet = promptFor({ subjectGender: "male", companionGender: "auto", companionKind: "pet" });

const videoMaleMale = buildVideoPrompt({
  scene,
  timeOfDay: "golden_hour",
  weather: "sunny",
  pose: "casual",
  hasCompanion: true,
  companionKind: "friend",
  subjectGender: "male",
  companionGender: "male"
});
const videoPet = buildVideoPrompt({
  scene,
  timeOfDay: "golden_hour",
  weather: "sunny",
  pose: "casual",
  hasCompanion: true,
  companionKind: "pet",
  subjectGender: "female",
  companionGender: "auto"
});

const checks = [
  [maleMale !== maleFemale, "male+male prompt distinct from male+female"],
  [/two adult men/.test(maleMale), "male + male friend pairing"],
  [/Image 2 shows an adult man/.test(maleMale), "male friend Image 2 gender lock"],
  [/never change a man into a woman/i.test(maleMale), "anti gender-flip lock"],
  [/adult man and an adult woman/.test(maleFemale), "male + female friend pairing"],
  [/two adult women/.test(femaleFemale), "female + female friend pairing"],
  [/adult woman and an adult man/.test(femaleMale), "female + male friend pairing"],
  [/Exactly one person and one pet/.test(femalePet), "female + pet"],
  [/Exactly one person and one pet/.test(malePet), "male + pet"],
  [/never add a second human/i.test(malePet), "pet forbids second human"],
  [/two adult men/.test(videoMaleMale), "video keeps male+male"],
  [/one person and one animal/.test(videoPet), "video keeps pet"]
];

let failed = 0;
for (const [ok, label] of checks) {
  if (!ok) {
    console.error(`FAIL: ${label}`);
    failed += 1;
  } else {
    console.log(`ok: ${label}`);
  }
}

if (failed) {
  console.error(`\n${failed} companion prompt checks failed.`);
  process.exit(1);
}

console.log("\nAll companion image/video prompt cases passed.");
