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

export async function listScenes(_request, response) {
  const scenes = await loadScenes();
  sendJSON(response, 200, { scenes });
}
