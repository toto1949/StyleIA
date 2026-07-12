import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { HttpError, sendJSON } from "../http-utils.mjs";

const scenesPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../data/scenes.json"
);

let cachedScenes = null;

export async function loadScenes() {
  if (!cachedScenes) {
    const raw = await fs.readFile(scenesPath, "utf8");
    const parsed = JSON.parse(raw);
    cachedScenes = Array.isArray(parsed.scenes) ? parsed.scenes : [];
  }
  return cachedScenes;
}

export async function findScene(sceneId) {
  const scenes = await loadScenes();
  const scene = scenes.find((candidate) => candidate.id === sceneId);
  if (!scene) {
    throw new HttpError(400, "Unknown scene.");
  }
  return scene;
}

/// Scenes can carry optional `available_from` / `available_until` ISO dates
/// for limited-time drops. Expired or not-yet-live scenes are hidden from the
/// list, but findScene still resolves them so in-flight jobs keep working.
function isSceneLive(scene, now) {
  const from = scene.available_from ? Date.parse(scene.available_from) : NaN;
  const until = scene.available_until ? Date.parse(scene.available_until) : NaN;

  if (Number.isFinite(from) && now < from) {
    return false;
  }
  if (Number.isFinite(until) && now > until) {
    return false;
  }
  return true;
}

export async function listScenes(_request, response) {
  const scenes = await loadScenes();
  const now = Date.now();
  sendJSON(response, 200, { scenes: scenes.filter((scene) => isSceneLive(scene, now)) });
}
