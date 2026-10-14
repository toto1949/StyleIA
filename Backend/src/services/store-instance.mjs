import { config } from "../config.mjs";
import { PostgresStore } from "../postgres-store.mjs";
import { JsonStore } from "../store.mjs";

export const store = config.databaseURL
  ? new PostgresStore(config.databaseURL, {
      sslRejectUnauthorized: config.databaseSSLRejectUnauthorized
    })
  : new JsonStore(config.dataPath);
