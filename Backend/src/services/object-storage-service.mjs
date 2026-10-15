import crypto from "node:crypto";
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import sharp from "sharp";
import { config } from "../config.mjs";
import { HttpError } from "../http-utils.mjs";
import { objectEncryptionOptions } from "./s3-compat.mjs";

const enabled = Boolean(
  config.objectStorageBucket
  && config.objectStorageAccessKeyId
  && config.objectStorageSecretAccessKey
);

const client = enabled
  ? new S3Client({
      region: config.objectStorageRegion,
      endpoint: config.objectStorageEndpoint || undefined,
      forcePathStyle: config.objectStorageForcePathStyle,
      credentials: {
        accessKeyId: config.objectStorageAccessKeyId,
        secretAccessKey: config.objectStorageSecretAccessKey
      }
    })
  : null;

export const objectStorage = Object.freeze({
  enabled,
  uploadKey,
  finalizedUploadKey,
  resultKey,
  createUploadURL,
  createDownloadURL,
  validateAndSanitizeUpload,
  ingestProviderResult,
  deleteKeys,
  sanitizeJPEGBuffer
});

function uploadKey(userId, uploadId) {
  assertIdentifier(userId);
  assertIdentifier(uploadId);
  return `private/${userId}/uploads/${uploadId}/incoming.jpg`;
}

function finalizedUploadKey(key) {
  assertPrivateKey(key);
  if (key.endsWith("/incoming.jpg")) {
    return `${key.slice(0, -"incoming.jpg".length)}validated.jpg`;
  }
  // Compatibility for pending records created before ingress/final key
  // separation. Existing already-validated records keep their current key.
  return key.replace(/\.jpg$/i, "/validated.jpg");
}

function resultKey(userId, jobId, kind) {
  assertIdentifier(userId);
  assertIdentifier(jobId);
  const extension = kind === "video" ? "mp4" : "jpg";
  // A stable destination makes provider-result ingestion idempotent when the
  // service restarts after upload but before the database completion commit.
  return `private/${userId}/results/${jobId}/result.${extension}`;
}

async function createUploadURL(key) {
  assertEnabled();
  assertPrivateKey(key);
  return getSignedUrl(client, new PutObjectCommand({
    Bucket: config.objectStorageBucket,
    Key: key,
    ContentType: "image/jpeg"
  }), { expiresIn: config.objectStorageUploadTTLSeconds });
}

async function createDownloadURL(key) {
  if (!key) {
    return null;
  }
  assertEnabled();
  assertPrivateKey(key);
  return getSignedUrl(client, new GetObjectCommand({
    Bucket: config.objectStorageBucket,
    Key: key,
    ResponseCacheControl: "private, no-store"
  }), { expiresIn: config.objectStorageDownloadTTLSeconds });
}

async function validateAndSanitizeUpload(key) {
  assertEnabled();
  assertPrivateKey(key);

  let head;
  try {
    head = await client.send(new HeadObjectCommand({ Bucket: config.objectStorageBucket, Key: key }));
  } catch (error) {
    if (error?.$metadata?.httpStatusCode === 404 || error?.name === "NotFound") {
      throw new HttpError(404, "Uploaded image not found.");
    }
    throw error;
  }

  const size = Number(head.ContentLength || 0);
  const contentType = String(head.ContentType || "").split(";", 1)[0].trim().toLowerCase();
  if (size <= 0 || size > config.maxUploadBytes || contentType !== "image/jpeg") {
    throw new HttpError(415, "Upload must be a JPEG image within the allowed size.");
  }

  const response = await client.send(new GetObjectCommand({ Bucket: config.objectStorageBucket, Key: key }));
  const input = await boundedBody(response.Body, config.maxUploadBytes);

  const { metadata, data: sanitized, sha256 } = await sanitizeJPEGBuffer(input);
  const storageKey = finalizedUploadKey(key);
  await client.send(new PutObjectCommand({
    Bucket: config.objectStorageBucket,
    Key: storageKey,
    Body: sanitized,
    ContentType: "image/jpeg",
    ContentLength: sanitized.length,
    CacheControl: "private, no-store",
    ...objectEncryptionOptions(config.objectStorageEndpoint),
    Metadata: { sha256 }
  }));
  try {
    await client.send(new DeleteObjectCommand({
      Bucket: config.objectStorageBucket,
      Key: key
    }));
  } catch {
    // The finalized key is already durable and is the only key generation
    // will use. Account deletion and the bucket's ingress lifecycle policy
    // still cover an ingress object if this best-effort cleanup is delayed.
    console.warn(JSON.stringify({
      timestamp: new Date().toISOString(),
      service: "sceneme-backend",
      event: "upload_ingress_cleanup_deferred"
    }));
  }

  return {
    s3Key: storageKey,
    size: sanitized.length,
    contentType: "image/jpeg",
    width: metadata.width,
    height: metadata.height,
    sha256
  };
}

async function sanitizeJPEGBuffer(input) {
  let metadata;
  let sanitized;
  try {
    const pipeline = sharp(input, {
      failOn: "warning",
      limitInputPixels: config.maxUploadPixels,
      sequentialRead: true
    }).rotate();
    metadata = await pipeline.metadata();
    if (metadata.format !== "jpeg" || !metadata.width || !metadata.height) {
      throw new Error("Unsupported image format.");
    }
    sanitized = await pipeline.jpeg({ quality: 90, mozjpeg: true }).toBuffer();
  } catch {
    throw new HttpError(415, "Upload must be a valid, supported JPEG image.");
  }

  if (sanitized.length > config.maxUploadBytes) {
    throw new HttpError(413, "Optimized upload is too large.");
  }

  return {
    metadata,
    data: sanitized,
    sha256: crypto.createHash("sha256").update(sanitized).digest("hex")
  };
}

async function ingestProviderResult({ userId, jobId, kind, sourceURL }) {
  assertEnabled();
  assertProviderMediaURL(sourceURL);
  const maxBytes = kind === "video" ? config.maxVideoResultBytes : config.maxImageResultBytes;
  const response = await fetch(sourceURL, {
    redirect: "error",
    signal: AbortSignal.timeout(kind === "video" ? 120_000 : 30_000)
  });
  if (!response.ok || !response.body) {
    throw new Error(`Provider result download failed (${response.status}).`);
  }

  const declaredLength = Number(response.headers.get("content-length") || 0);
  if (declaredLength > maxBytes) {
    throw new Error("Provider result exceeded the configured size limit.");
  }

  const expectedPrefix = kind === "video" ? "video/" : "image/";
  const contentType = String(response.headers.get("content-type") || "").split(";", 1)[0].toLowerCase();
  if (!contentType.startsWith(expectedPrefix)) {
    throw new Error("Provider result had an unexpected content type.");
  }

  const body = await boundedBody(response.body, maxBytes);
  const key = resultKey(userId, jobId, kind);
  await client.send(new PutObjectCommand({
    Bucket: config.objectStorageBucket,
    Key: key,
    Body: body,
    ContentType: kind === "video" ? "video/mp4" : contentType,
    ContentLength: body.length,
    CacheControl: "private, no-store",
    ...objectEncryptionOptions(config.objectStorageEndpoint)
  }));
  return { key, size: body.length, contentType };
}

async function deleteKeys(keys) {
  if (!enabled || !Array.isArray(keys) || keys.length === 0) {
    return;
  }
  const uniqueKeys = [...new Set(keys.filter(Boolean))];
  for (let index = 0; index < uniqueKeys.length; index += 1_000) {
    const batch = uniqueKeys.slice(index, index + 1_000);
    batch.forEach(assertPrivateKey);
    const result = await client.send(new DeleteObjectsCommand({
      Bucket: config.objectStorageBucket,
      Delete: { Quiet: true, Objects: batch.map((Key) => ({ Key })) }
    }));
    if (Array.isArray(result.Errors) && result.Errors.length > 0) {
      throw new Error(`Object deletion failed for ${result.Errors.length} object(s).`);
    }
  }
}

async function boundedBody(body, maxBytes) {
  const chunks = [];
  let total = 0;
  for await (const chunk of body) {
    const bytes = Buffer.from(chunk);
    total += bytes.length;
    if (total > maxBytes) {
      throw new HttpError(413, "Media exceeds the allowed size.");
    }
    chunks.push(bytes);
  }
  return Buffer.concat(chunks);
}

function assertEnabled() {
  if (!client) {
    throw new Error("Private object storage is not configured.");
  }
}

function assertIdentifier(value) {
  if (!/^[a-f0-9-]{16,64}$/i.test(String(value || ""))) {
    throw new Error("Invalid storage identifier.");
  }
}

function assertPrivateKey(key) {
  if (!/^private\/[a-f0-9-]{16,64}\/(uploads|results)\/[a-zA-Z0-9./_-]+$/.test(String(key || ""))) {
    throw new Error("Invalid private object key.");
  }
}

function assertProviderMediaURL(value) {
  const url = new URL(String(value || ""));
  const host = url.hostname.toLowerCase();
  const allowed = host === "fal.media"
    || host.endsWith(".fal.media")
    || host === "storage.googleapis.com";
  if (url.protocol !== "https:" || !allowed || url.username || url.password) {
    throw new Error("Provider returned an untrusted media URL.");
  }
}
