import crypto from "node:crypto";
import { config } from "./config.mjs";
import { base64URLDecode, base64URLEncode, parseBase64URLJSON } from "./encoding.mjs";
import { bearerToken, HttpError } from "./http-utils.mjs";

const appleKeyCache = {
  fetchedAt: 0,
  keys: []
};

const googleKeyCache = {
  fetchedAt: 0,
  keys: []
};

function hmac(input) {
  return crypto.createHmac("sha256", config.jwtSecret).update(input).digest();
}

export function signToken(payload, expiresInSeconds = 60 * 60 * 24 * 30) {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const body = {
    ...payload,
    iat: now,
    exp: now + expiresInSeconds
  };

  const encodedHeader = base64URLEncode(JSON.stringify(header));
  const encodedBody = base64URLEncode(JSON.stringify(body));
  const signature = base64URLEncode(hmac(`${encodedHeader}.${encodedBody}`));
  return `${encodedHeader}.${encodedBody}.${signature}`;
}

export function verifyToken(token, expectedType) {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new HttpError(401, "Unauthorized.");
  }

  const [encodedHeader, encodedBody, encodedSignature] = parts;
  const expectedSignature = hmac(`${encodedHeader}.${encodedBody}`);
  const incomingSignature = base64URLDecode(encodedSignature);

  if (
    expectedSignature.length !== incomingSignature.length ||
    !crypto.timingSafeEqual(expectedSignature, incomingSignature)
  ) {
    throw new HttpError(401, "Unauthorized.");
  }

  const payload = parseBase64URLJSON(encodedBody);
  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, "Unauthorized.");
  }

  if (expectedType && payload.type !== expectedType) {
    throw new HttpError(401, "Unauthorized.");
  }

  return payload;
}

export function authenticateRequest(request) {
  const payload = verifyToken(bearerToken(request), "access");
  if (!payload.sub) {
    throw new HttpError(401, "Unauthorized.");
  }
  return payload;
}

export function signUploadToken(userId, uploadId) {
  return signToken({ type: "upload", sub: userId, uploadId }, 15 * 60);
}

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = await pbkdf2(password, salt);
  return { salt, hash };
}

export async function verifyPassword(password, salt, expectedHash) {
  const incomingHash = await pbkdf2(password, salt);
  return crypto.timingSafeEqual(Buffer.from(incomingHash, "hex"), Buffer.from(expectedHash, "hex"));
}

function pbkdf2(password, salt) {
  return new Promise((resolve, reject) => {
    crypto.pbkdf2(password, salt, 310_000, 32, "sha256", (error, derivedKey) => {
      if (error) {
        reject(error);
      } else {
        resolve(derivedKey.toString("hex"));
      }
    });
  });
}

export function assertEmailPassword(email, password) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
    throw new HttpError(400, "Enter a valid email address.");
  }

  if (String(password || "").length < 8) {
    throw new HttpError(400, "Password must be at least 8 characters.");
  }

  return { email: normalizedEmail, password: String(password) };
}

export async function verifyAppleIdentityToken(identityToken) {
  const parts = String(identityToken || "").split(".");
  if (parts.length !== 3) {
    throw new HttpError(401, "Invalid Apple identity token.");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = parseBase64URLJSON(encodedHeader);
  const payload = parseBase64URLJSON(encodedPayload);

  if (payload.iss !== "https://appleid.apple.com") {
    throw new HttpError(401, "Invalid Apple identity token.");
  }

  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, "Apple identity token expired.");
  }

  if (config.appleClientId && payload.aud !== config.appleClientId) {
    throw new HttpError(401, "Apple identity token audience mismatch.");
  }

  if (!config.appleClientId && config.nodeEnv === "production") {
    throw new Error("APPLE_CLIENT_ID must be configured in production.");
  }

  const jwk = (await appleKeys()).find((candidate) => candidate.kid === header.kid);
  if (!jwk) {
    throw new HttpError(401, "Apple signing key not found.");
  }

  const key = await crypto.webcrypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const isValid = await crypto.webcrypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64URLDecode(encodedSignature),
    Buffer.from(`${encodedHeader}.${encodedPayload}`)
  );

  if (!isValid) {
    throw new HttpError(401, "Invalid Apple identity token signature.");
  }

  return {
    appleSub: payload.sub,
    email: payload.email || "",
    emailVerified: payload.email_verified === true || payload.email_verified === "true"
  };
}

async function appleKeys() {
  const now = Date.now();
  if (appleKeyCache.keys.length > 0 && now - appleKeyCache.fetchedAt < 60 * 60 * 1000) {
    return appleKeyCache.keys;
  }

  const response = await fetch("https://appleid.apple.com/auth/keys");
  if (!response.ok) {
    throw new Error("Unable to fetch Apple signing keys.");
  }

  const payload = await response.json();
  appleKeyCache.keys = Array.isArray(payload.keys) ? payload.keys : [];
  appleKeyCache.fetchedAt = now;
  return appleKeyCache.keys;
}

export async function verifyGoogleIdentityToken(identityToken) {
  const parts = String(identityToken || "").split(".");
  if (parts.length !== 3) {
    throw new HttpError(401, "Invalid Google identity token.");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = parseBase64URLJSON(encodedHeader);
  const payload = parseBase64URLJSON(encodedPayload);

  const issuer = String(payload.iss || "");
  if (issuer !== "accounts.google.com" && issuer !== "https://accounts.google.com") {
    throw new HttpError(401, "Invalid Google identity token.");
  }

  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, "Google identity token expired.");
  }

  const audience = String(payload.aud || "");
  const allowedAudiences = config.googleClientIds.length > 0 ? config.googleClientIds : [config.googleClientId];
  if (allowedAudiences.length > 0 && !allowedAudiences.includes(audience)) {
    throw new HttpError(401, "Google identity token audience mismatch.");
  }

  if (allowedAudiences.length === 0 && config.nodeEnv === "production") {
    throw new Error("GOOGLE_CLIENT_ID must be configured in production.");
  }

  const jwk = (await googleKeys()).find((candidate) => candidate.kid === header.kid);
  if (!jwk) {
    throw new HttpError(401, "Google signing key not found.");
  }

  const key = await crypto.webcrypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const isValid = await crypto.webcrypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64URLDecode(encodedSignature),
    Buffer.from(`${encodedHeader}.${encodedPayload}`)
  );

  if (!isValid) {
    throw new HttpError(401, "Invalid Google identity token signature.");
  }

  return {
    googleSub: payload.sub,
    email: payload.email || "",
    emailVerified: payload.email_verified === true || payload.email_verified === "true",
    fullName: payload.name || ""
  };
}

async function googleKeys() {
  const now = Date.now();
  if (googleKeyCache.keys.length > 0 && now - googleKeyCache.fetchedAt < 60 * 60 * 1000) {
    return googleKeyCache.keys;
  }

  const response = await fetch("https://www.googleapis.com/oauth2/v3/certs");
  if (!response.ok) {
    throw new Error("Unable to fetch Google signing keys.");
  }

  const payload = await response.json();
  googleKeyCache.keys = Array.isArray(payload.keys) ? payload.keys : [];
  googleKeyCache.fetchedAt = now;
  return googleKeyCache.keys;
}
