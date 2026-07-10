import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { authenticateRequest, signUploadToken, verifyToken } from "../auth.mjs";
import { config } from "../config.mjs";
import { corsHeaders, HttpError, readRawBody, sendJSON } from "../http-utils.mjs";
import { store } from "../services/store-instance.mjs";

export async function presignUpload(request, response) {
  const auth = authenticateRequest(request);
  const uploadId = crypto.randomUUID();
  const s3Key = `uploads/${uploadId}.jpg`;
  const uploadToken = signUploadToken(auth.sub, uploadId);
  const uploadURL = `${config.publicBaseURL}/v1/upload/${uploadId}?token=${encodeURIComponent(uploadToken)}`;

  await store.mutate(async (data) => {
    data.uploads.push({
      id: uploadId,
      userId: auth.sub,
      s3Key,
      localPath: path.join(config.uploadDirectory, `${uploadId}.jpg`),
      publicURL: `${config.publicBaseURL}/uploads/${uploadId}.jpg`,
      status: "pending",
      size: 0,
      contentType: "image/jpeg",
      createdAt: new Date().toISOString()
    });
  });

  sendJSON(response, 200, { uploadURL, s3Key });
}

export async function receiveUpload(request, response, uploadId, token) {
  const uploadAuth = verifyToken(token, "upload");
  if (uploadAuth.uploadId !== uploadId) {
    throw new HttpError(401, "Unauthorized.");
  }

  const body = await readRawBody(request, config.maxUploadBytes);
  if (body.length === 0) {
    throw new HttpError(400, "Upload body is empty.");
  }

  if (!String(request.headers["content-type"] || "").startsWith("image/")) {
    throw new HttpError(415, "Upload must be an image.");
  }

  const upload = await store.mutate(async (data) => {
    const candidate = data.uploads.find((item) => item.id === uploadId && item.userId === uploadAuth.sub);
    if (!candidate) {
      throw new HttpError(404, "Upload not found.");
    }

    await fs.writeFile(candidate.localPath, body);
    candidate.status = "uploaded";
    candidate.size = body.length;
    candidate.contentType = request.headers["content-type"] || "image/jpeg";
    candidate.updatedAt = new Date().toISOString();
    return candidate;
  });

  sendJSON(response, 200, { success: true, s3Key: upload.s3Key });
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
    "Cache-Control": "public, max-age=31536000, immutable",
    ...corsHeaders()
  });
  response.end(body);
}
