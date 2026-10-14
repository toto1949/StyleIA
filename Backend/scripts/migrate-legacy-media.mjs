import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import sharp from "sharp";

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const apply = process.argv.includes("--apply");
const allowMissing = process.argv.includes("--allow-missing");
const sourcePath = resolveArgument("--file", process.env.STYLEAI_DATA_PATH || "./data/styleai.json");
const uploadsDirectory = resolveArgument("--uploads-dir", process.env.STYLEAI_UPLOAD_DIR || "./uploads");
const outputPath = resolveArgument("--output", "./data/styleai.private-storage.json");
const source = JSON.parse(await fs.readFile(sourcePath, "utf8"));
const uploads = Array.isArray(source.uploads) ? source.uploads : [];
const plan = [];

for (const upload of uploads) {
  assertUUID(upload.id, "upload id");
  assertUUID(upload.userId, "upload owner");
  const candidate = upload.localPath
    ? path.resolve(backendRoot, upload.localPath)
    : path.join(uploadsDirectory, `${upload.id}.jpg`);
  const exists = await fileExists(candidate);
  plan.push({ upload, candidate, exists });
}

const summary = {
  mode: apply ? "apply" : "dry-run",
  source: sourcePath,
  output: outputPath,
  uploads: uploads.length,
  recoverable: plan.filter((item) => item.exists).length,
  missing: plan.filter((item) => !item.exists).length
};
console.log(JSON.stringify(summary, null, 2));

if (!apply) {
  console.log("Dry run only. Configure object-storage variables and re-run with --apply after taking a source snapshot.");
  process.exit(summary.missing > 0 ? 2 : 0);
}

if (summary.missing > 0 && !allowMissing) {
  throw new Error("Legacy upload files are missing. Recover them or explicitly pass --allow-missing after owner review.");
}

const bucket = required("OBJECT_STORAGE_BUCKET");
const client = new S3Client({
  region: process.env.OBJECT_STORAGE_REGION || "auto",
  endpoint: process.env.OBJECT_STORAGE_ENDPOINT || undefined,
  forcePathStyle: boolean(process.env.OBJECT_STORAGE_FORCE_PATH_STYLE),
  credentials: {
    accessKeyId: required("OBJECT_STORAGE_ACCESS_KEY_ID"),
    secretAccessKey: required("OBJECT_STORAGE_SECRET_ACCESS_KEY")
  }
});
const keyChanges = new Map();

for (const item of plan) {
  const oldKey = item.upload.s3Key;
  if (!item.exists) {
    Object.assign(item.upload, {
      status: "rejected",
      unavailableReason: "legacy_source_missing"
    });
    removeLegacyMediaFields(item.upload);
    continue;
  }

  const original = await fs.readFile(item.candidate);
  const pipeline = sharp(original, {
    failOn: "warning",
    limitInputPixels: 40_000_000,
    sequentialRead: true
  }).rotate();
  const metadata = await pipeline.metadata();
  if (metadata.format !== "jpeg" || !metadata.width || !metadata.height) {
    throw new Error(`Legacy upload ${item.upload.id} is not a valid JPEG.`);
  }
  const body = await pipeline.jpeg({ quality: 90, mozjpeg: true }).toBuffer();
  const key = `private/${item.upload.userId}/uploads/${item.upload.id}/validated.jpg`;
  await client.send(new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    Body: body,
    ContentType: "image/jpeg",
    ContentLength: body.length,
    CacheControl: "private, no-store",
    ServerSideEncryption: "AES256",
    Metadata: { sha256: crypto.createHash("sha256").update(body).digest("hex") }
  }));

  keyChanges.set(oldKey, key);
  Object.assign(item.upload, {
    s3Key: key,
    clientS3Key: null,
    status: "uploaded",
    size: body.length,
    contentType: "image/jpeg",
    width: metadata.width,
    height: metadata.height,
    sha256: crypto.createHash("sha256").update(body).digest("hex"),
    validatedAt: item.upload.validatedAt || new Date().toISOString(),
    updatedAt: new Date().toISOString()
  });
  removeLegacyMediaFields(item.upload);
}

for (const job of Array.isArray(source.jobs) ? source.jobs : []) {
  if (keyChanges.has(job.s3Key)) job.s3Key = keyChanges.get(job.s3Key);
  if (keyChanges.has(job.companionS3Key)) job.companionS3Key = keyChanges.get(job.companionS3Key);
  delete job.localPath;
  delete job.companionLocalPath;
  delete job.originalPhotoURL;
  delete job.companionPhotoURL;
  // Historical provider URLs are intentionally not copied into the database
  // as durable/private media. A separate result-ingestion pass must either
  // copy reachable results to object keys or mark them unavailable.
  delete job.sourceImageURL;
}

await fs.writeFile(outputPath, `${JSON.stringify(source, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify({ ...summary, written: outputPath }, null, 2));

function removeLegacyMediaFields(upload) {
  delete upload.localPath;
  delete upload.publicURL;
  delete upload.falImageURL;
  delete upload.falUploadedAt;
}

function resolveArgument(name, fallback) {
  const entry = process.argv.find((argument) => argument.startsWith(`${name}=`));
  const value = entry ? entry.slice(name.length + 1) : fallback;
  return path.isAbsolute(value) ? value : path.resolve(backendRoot, value);
}

async function fileExists(filePath) {
  try {
    const stat = await fs.stat(filePath);
    return stat.isFile();
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

function required(name) {
  const value = String(process.env[name] || "");
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function boolean(value) {
  return ["1", "true", "yes", "on"].includes(String(value || "").toLowerCase());
}

function assertUUID(value, label) {
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(String(value || ""))) {
    throw new Error(`Invalid ${label}.`);
  }
}
