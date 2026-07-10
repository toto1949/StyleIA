import { config } from "../config.mjs";
import { JsonStore } from "../store.mjs";

export const store = new JsonStore(config.dataPath);
