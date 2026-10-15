import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import sharp from "sharp";
import { objectEncryptionOptions } from "../src/services/s3-compat.mjs";

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const apply = process.argv.includes("--apply");
const allowMissing = process.argv.includes("--allow-missing");
const sourcePath = resolveArgument("--file", process.env.STYLEAI_DATA_PATH || "./data/styleai.json");
const uploadsDirectory = resolveArgument("--uploads-dir", process.env.STYLEAI_UPLOAD_DIR || "./uploads");
const outputPath = resolveArgument("--output", "./data/styleai.private-storage.json");
const source = JSON.parse(await fs.readFile(sourcePath, "utf8"));
const uploads = Array.isArray(source.uploads) ? source.uploads : [];
const jobs = Array.isArray(source.jobs) ? source.jobs : [];
const plan = [];
const resultPlan = [];

for (const upload of uploads) {
  assertUUID(upload.id, "upload id");
  assertUUID(upload.userId, "upload owner");
  const candidate = upload.localPath
    ? path.resolve(backendRoot, upload.localPath)
    : path.join(uploadsDirectory, `${upload.id}.jpg`);
  const exists = await fileExists(candidate);
  plan.push({ upload, candidate, exists });
}

for (const job of jobs) {
  assertUUID(job.jobId, "public job id");
  assertUUID(job.userId, "job owner");
  const fallbackImageURL = [
    ...(Array.isArray(job.resultURLs) ? job.resultURLs : []),
    ...(Array.isArray(job.looks) ? job.looks.map((look) => look?.imageURL) : [])
  ].find(isTrustedProviderURL);
  if (isTrustedProviderURL(job.imageURL || fallbackImageURL)) {
    resultPlan.push({ job, kind: "image", sourceURL: job.imageURL || fallbackImageURL, slot: "primary" });
  }
  if (isTrustedProviderURL(job.videoURL)) {
    resultPlan.push({ job, kind: "video", sourceURL: job.videoURL, slot: "primary" });
  }
  for (const [index, clip] of (Array.isArray(job.videoClips) ? job.videoClips : []).entries()) {
    if (isTrustedProviderURL(clip?.videoURL)) {
      resultPlan.push({ job, clip, kind: "video", sourceURL: clip.videoURL, slot: `clip-${index + 1}` });
    }
  }
}

const summary = {
  mode: apply ? "apply" : "dry-run",
  source: sourcePath,
  output: outputPath,
  uploads: uploads.length,
  recoverable: plan.filter((item) => item.exists).length,
  missing: plan.filter((item) => !item.exists).length,
  privateResultCandidates: resultPlan.length,
  excludedLegacyResultReferences: countExcludedResultReferences(jobs)
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
    ...objectEncryptionOptions(process.env.OBJECT_STORAGE_ENDPOINT),
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

let unavailableResults = 0;
for (const item of resultPlan) {
  const suffix = item.slot === "primary" ? `result.${item.kind === "video" ? "mp4" : "jpg"}` : `clips/${item.slot}.mp4`;
  const key = `private/${item.job.userId}/results/${item.job.jobId}/${suffix}`;
  try {
    const stored = await downloadProviderResult(item.sourceURL, item.kind);
    await client.send(new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: stored.body,
      ContentType: stored.contentType,
      ContentLength: stored.body.length,
      CacheControl: "private, no-store",
      ...objectEncryptionOptions(process.env.OBJECT_STORAGE_ENDPOINT),
      Metadata: { sha256: crypto.createHash("sha256").update(stored.body).digest("hex") }
    }));
    if (item.clip) item.clip.videoObjectKey = key;
    else if (item.kind === "video") item.job.videoObjectKey = key;
    else item.job.imageObjectKey = key;
  } catch (error) {
    unavailableResults += 1;
    if (!allowMissing) throw error;
    item.job.historicalResultUnavailable = true;
  }
}

for (const job of jobs) {
  if (keyChanges.has(job.s3Key)) job.s3Key = keyChanges.get(job.s3Key);
  if (keyChanges.has(job.companionS3Key)) job.companionS3Key = keyChanges.get(job.companionS3Key);
  delete job.localPath;
  delete job.companionLocalPath;
  delete job.originalPhotoURL;
  delete job.companionPhotoURL;
  delete job.sourceImageURL;
  delete job.imageURL;
  delete job.videoURL;
  delete job.resultURLs;
  delete job.looks;
  if (Array.isArray(job.videoClips)) {
    job.videoClips = job.videoClips.map((clip) => {
      const sanitized = { ...clip };
      delete sanitized.videoURL;
      return sanitized;
    });
  }
}

await fs.writeFile(outputPath, `${JSON.stringify(source, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify({ ...summary, unavailableResults, written: outputPath }, null, 2));

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

function isTrustedProviderURL(value) {
  try {
    const url = new URL(String(value || ""));
    return url.protocol === "https:" && (url.hostname === "fal.media" || url.hostname.endsWith(".fal.media"));
  } catch {
    return false;
  }
}

function countExcludedResultReferences(rows) {
  let count = 0;
  for (const job of rows) {
    const values = [
      job.imageURL,
      job.videoURL,
      ...(Array.isArray(job.resultURLs) ? job.resultURLs : []),
      ...(Array.isArray(job.looks) ? job.looks.map((look) => look?.imageURL) : []),
      ...(Array.isArray(job.videoClips) ? job.videoClips.map((clip) => clip?.videoURL) : [])
    ];
    count += values.filter((value) => value && !isTrustedProviderURL(value)).length;
  }
  return count;
}

async function downloadProviderResult(sourceURL, kind) {
  if (!isTrustedProviderURL(sourceURL)) throw new Error("Untrusted legacy result URL.");
  const maxBytes = kind === "video" ? 250_000_000 : 30_000_000;
  const response = await fetch(sourceURL, {
    redirect: "error",
    signal: AbortSignal.timeout(kind === "video" ? 120_000 : 30_000)
  });
  if (!response.ok || !response.body) throw new Error(`Legacy provider result download failed (${response.status}).`);
  const contentType = String(response.headers.get("content-type") || "").split(";", 1)[0].toLowerCase();
  const expectedPrefix = kind === "video" ? "video/" : "image/";
  if (!contentType.startsWith(expectedPrefix)) throw new Error("Legacy result had an unexpected content type.");
  const chunks = [];
  let total = 0;
  for await (const chunk of response.body) {
    const bytes = Buffer.from(chunk);
    total += bytes.length;
    if (total > maxBytes) throw new Error("Legacy result exceeded the configured size limit.");
    chunks.push(bytes);
  }
  return { body: Buffer.concat(chunks), contentType: kind === "video" ? "video/mp4" : contentType };
}

function assertUUID(value, label) {
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(String(value || ""))) {
    throw new Error(`Invalid ${label}.`);
  }
}
