import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { PostgresStore } from "../src/postgres-store.mjs";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) {
  throw new Error("DATABASE_URL is required.");
}

const apply = process.argv.includes("--apply");
const fileArgument = process.argv.find((argument) => argument.startsWith("--file="));
const filePath = path.resolve(fileArgument?.slice("--file=".length) || process.env.STYLEAI_DATA_PATH || "./data/styleai.json");
const raw = await fs.readFile(filePath, "utf8");
const checksum = crypto.createHash("sha256").update(raw).digest("hex");
const parsed = JSON.parse(raw);
const incoming = {
  users: array(parsed.users),
  uploads: array(parsed.uploads),
  jobs: array(parsed.jobs),
  usage: array(parsed.usage)
};

validate(incoming);
console.log(JSON.stringify({
  mode: apply ? "apply" : "dry-run",
  source: filePath,
  sha256: checksum,
  counts: Object.fromEntries(Object.entries(incoming).map(([key, value]) => [key, value.length]))
}, null, 2));

if (!apply) {
  console.log("Dry run only. Re-run with --apply after taking a database backup.");
  process.exit(0);
}

const store = new PostgresStore(databaseURL, {
  sslRejectUnauthorized: process.env.DATABASE_SSL_REJECT_UNAUTHORIZED !== "false"
});

try {
  await store.init();
  await store.mutate(async (current) => {
    if (current.users.length || current.uploads.length || current.jobs.length || current.usage.length) {
      throw new Error("Refusing to import into a non-empty SceneMe database.");
    }
    Object.assign(current, incoming);
  });
  const imported = await store.snapshot();
  for (const key of Object.keys(incoming)) {
    if (imported[key].length !== incoming[key].length) {
      throw new Error(`Imported ${key} count did not match source.`);
    }
  }
  console.log("Legacy JSON import completed and row counts were verified.");
} finally {
  await store.close();
}

function array(value) {
  return Array.isArray(value) ? value : [];
}

function validate(data) {
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
  const unique = (values, label) => {
    if (new Set(values).size !== values.length) {
      throw new Error(`Source contains duplicate ${label}.`);
    }
  };

  data.users.forEach((user) => {
    if (!uuid.test(String(user.id || ""))) throw new Error("Source contains an invalid user id.");
  });
  data.uploads.forEach((upload) => {
    if (!uuid.test(String(upload.id || "")) || !uuid.test(String(upload.userId || ""))) {
      throw new Error("Source contains an invalid upload id or owner.");
    }
  });
  data.jobs.forEach((job) => {
    if (!uuid.test(String(job.id || "")) || !uuid.test(String(job.jobId || "")) || !uuid.test(String(job.userId || ""))) {
      throw new Error("Source contains an invalid job id or owner.");
    }
  });
  unique(data.users.map((item) => item.id), "user ids");
  unique(data.uploads.map((item) => item.id), "upload ids");
  unique(data.jobs.map((item) => item.jobId), "public job ids");
}
