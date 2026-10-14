import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { authenticateRequest, signUploadToken, verifyToken } from "../auth.mjs";
import { config } from "../config.mjs";
import { corsHeaders, HttpError, readRawBody, sendJSON } from "../http-utils.mjs";
import { store } from "../services/store-instance.mjs";
import { objectStorage } from "../services/object-storage-service.mjs";
import { assertSafeUserImage } from "../services/content-safety-service.mjs";

export async function presignUpload(request, response) {
  const auth = await authenticateRequest(request);
  const uploadId = crypto.randomUUID();
  const s3Key = objectStorage.enabled
    ? objectStorage.uploadKey(auth.sub, uploadId)
    : `uploads/${uploadId}.jpg`;
  const uploadURL = objectStorage.enabled
    ? await objectStorage.createUploadURL(s3Key)
    : localUploadURL(auth.sub, uploadId);
  const expiresAt = new Date(Date.now() + config.objectStorageUploadTTLSeconds * 1_000).toISOString();

  await store.mutate(async (data) => {
    data.uploads.push({
      id: uploadId,
      userId: auth.sub,
      s3Key,
      clientS3Key: objectStorage.enabled ? s3Key : null,
      localPath: objectStorage.enabled ? null : path.join(config.uploadDirectory, `${uploadId}.jpg`),
      publicURL: objectStorage.enabled ? null : `${config.publicBaseURL}/uploads/${uploadId}.jpg`,
      status: "pending",
      size: 0,
      contentType: "image/jpeg",
      createdAt: new Date().toISOString(),
      expiresAt
    });
  });

  sendJSON(response, 200, { uploadURL, s3Key });
}

export async function receiveUpload(request, response, uploadId, token) {
  if (objectStorage.enabled) {
    throw new HttpError(404, "Not found.");
  }
  const uploadAuth = verifyToken(token, "upload");
  if (uploadAuth.uploadId !== uploadId) {
    throw new HttpError(401, "Unauthorized.");
  }

  const body = await readRawBody(request, config.maxUploadBytes);
  if (body.length === 0) {
    throw new HttpError(400, "Upload body is empty.");
  }

  if (
    String(request.headers["content-type"] || "").split(";")[0].trim() !== "image/jpeg"
    || body.length < 3
    || body[0] !== 0xff
    || body[1] !== 0xd8
    || body[2] !== 0xff
  ) {
    throw new HttpError(415, "Upload must be a valid JPEG image.");
  }

  const sanitized = await objectStorage.sanitizeJPEGBuffer(body);
  const upload = await store.mutate(async (data) => {
    const candidate = data.uploads.find((item) => item.id === uploadId && item.userId === uploadAuth.sub);
    if (!candidate) {
      throw new HttpError(404, "Upload not found.");
    }

    await fs.writeFile(candidate.localPath, sanitized.data);
    candidate.status = "uploaded";
    candidate.size = sanitized.data.length;
    candidate.contentType = "image/jpeg";
    candidate.width = sanitized.metadata.width;
    candidate.height = sanitized.metadata.height;
    candidate.sha256 = sanitized.sha256;
    candidate.validatedAt = new Date().toISOString();
    candidate.updatedAt = new Date().toISOString();
    return candidate;
  });

  sendJSON(response, 200, { success: true, s3Key: upload.s3Key });
}

export async function ensureUploadReady(userId, s3Key) {
  const snapshot = await store.snapshot();
  const upload = snapshot.uploads.find(
    (candidate) => candidate.userId === userId
      && (candidate.s3Key === s3Key || candidate.clientS3Key === s3Key)
  );
  if (!upload) {
    throw new HttpError(404, "Uploaded image not found.");
  }
  if (!objectStorage.enabled) {
    if (upload.status !== "uploaded") {
      throw new HttpError(409, "Upload has not finished.");
    }
    return upload;
  }
  if (upload.status === "uploaded" && upload.validatedAt) {
    return upload;
  }
  if (upload.status !== "pending") {
    throw new HttpError(409, "Upload is not available for generation.");
  }

  const ingressKey = upload.clientS3Key || upload.s3Key;
  const validated = await objectStorage.validateAndSanitizeUpload(ingressKey);
  return store.mutate(async (data) => {
    const current = data.uploads.find(
      (candidate) => candidate.id === upload.id && candidate.userId === userId
    );
    if (!current) {
      throw new HttpError(404, "Uploaded image not found.");
    }
    Object.assign(current, validated, {
      clientS3Key: current.clientS3Key || ingressKey,
      status: "uploaded",
      validatedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { ...current };
  });
}

export async function uploadInputURL(upload) {
  if (objectStorage.enabled) {
    return objectStorage.createDownloadURL(upload.s3Key);
  }
  return upload.publicURL;
}

export async function ensureUploadSafeForGeneration(userId, upload, imageURL) {
  if (upload.contentSafetyStatus === "allowed") {
    return upload;
  }
  if (upload.contentSafetyStatus === "blocked") {
    throw new HttpError(400, "This photo cannot be processed under SceneMe's safety rules.", {
      code: "IMAGE_SAFETY_BLOCKED"
    });
  }

  let assessment;
  try {
    assessment = await assertSafeUserImage(imageURL, userId);
  } catch (error) {
    if (error instanceof HttpError && error.code === "IMAGE_SAFETY_BLOCKED") {
      await persistUploadSafety(userId, upload.s3Key, "blocked", config.openAIModerationModel);
    }
    throw error;
  }
  if (assessment.status === "allowed") {
    return persistUploadSafety(userId, upload.s3Key, "allowed", assessment.model);
  }
  return upload;
}

async function persistUploadSafety(userId, s3Key, status, model) {
  return store.mutate(async (data) => {
    const current = data.uploads.find(
      (candidate) => candidate.userId === userId && candidate.s3Key === s3Key
    );
    if (!current) {
      throw new HttpError(404, "Uploaded image not found.");
    }
    current.contentSafetyStatus = status;
    current.contentSafetyModel = model || null;
    current.contentSafetyCheckedAt = new Date().toISOString();
    current.updatedAt = new Date().toISOString();
    return { ...current };
  });
}

function localUploadURL(userId, uploadId) {
  const uploadToken = signUploadToken(userId, uploadId);
  return `${config.publicBaseURL}/v1/upload/${uploadId}?token=${encodeURIComponent(uploadToken)}`;
}

export async function serveUpload(pathname, response) {
  const fileName = path.basename(decodeURIComponent(pathname));
  if (!/^[a-f0-9-]+\.jpg$/i.test(fileName)) {
    throw new HttpError(404, "Not found.");
  }

  const filePath = path.join(config.uploadDirectory, fileName);
  let body;
  try {
    body = await fs.readFile(filePath);
  } catch {
    throw new HttpError(404, "Not found.");
  }

  response.writeHead(200, {
    "Content-Type": "image/jpeg",
    "Content-Length": body.length,
    "Cache-Control": "private, no-store",
    "X-Content-Type-Options": "nosniff",
    ...corsHeaders()
  });
  response.end(body);
}
