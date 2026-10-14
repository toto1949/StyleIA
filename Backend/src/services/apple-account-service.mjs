import crypto from "node:crypto";
import { config } from "../config.mjs";
import { base64URLEncode } from "../encoding.mjs";

const tokenEndpoint = "https://appleid.apple.com/auth/token";
const revokeEndpoint = "https://appleid.apple.com/auth/revoke";

function credentialsConfigured() {
  return Boolean(
    config.appleClientId
    && config.appleTeamId
    && config.appleKeyId
    && config.applePrivateKey
    && config.dataEncryptionKey
  );
}

function clientSecret() {
  const now = Math.floor(Date.now() / 1000);
  const encodedHeader = base64URLEncode(JSON.stringify({
    alg: "ES256",
    kid: config.appleKeyId,
    typ: "JWT"
  }));
  const encodedPayload = base64URLEncode(JSON.stringify({
    iss: config.appleTeamId,
    iat: now,
    exp: now + 5 * 60,
    aud: "https://appleid.apple.com",
    sub: config.appleClientId
  }));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: config.applePrivateKey,
    dsaEncoding: "ieee-p1363"
  });
  return `${signingInput}.${base64URLEncode(signature)}`;
}

/// Exchanges the one-time authorization code supplied by the native app for a
/// revocable refresh token. The encrypted value is stored with the user only
/// so SceneMe can revoke Sign in with Apple when that user deletes the account.
export async function exchangeAppleAuthorizationCode(authorizationCode) {
  if (!credentialsConfigured()) {
    if (config.nodeEnv === "production") {
      throw new Error("Apple account-revocation credentials are incomplete.");
    }
    return "";
  }

  const response = await fetch(tokenEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.appleClientId,
      client_secret: clientSecret(),
      code: String(authorizationCode || ""),
      grant_type: "authorization_code"
    }),
    signal: AbortSignal.timeout(10_000)
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload.refresh_token) {
    throw new Error(`Apple authorization-code exchange failed (${response.status}).`);
  }
  return encrypt(payload.refresh_token);
}

/// Apple recommends attempting credential revocation as part of in-app
/// deletion. Deletion itself must still complete if Apple is temporarily down.
export async function revokeAppleRefreshToken(encryptedRefreshToken) {
  if (!encryptedRefreshToken || !credentialsConfigured()) {
    return false;
  }

  const response = await fetch(revokeEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.appleClientId,
      client_secret: clientSecret(),
      token: decrypt(encryptedRefreshToken),
      token_type_hint: "refresh_token"
    }),
    signal: AbortSignal.timeout(10_000)
  });
  if (!response.ok) {
    throw new Error(`Apple token revocation failed (${response.status}).`);
  }
  return true;
}

function encryptionKey() {
  return crypto.createHash("sha256").update(config.dataEncryptionKey).digest();
}

function encrypt(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, ciphertext].map((part) => part.toString("base64url")).join(".");
}

function decrypt(value) {
  const [ivValue, tagValue, ciphertextValue] = String(value).split(".");
  if (!ivValue || !tagValue || !ciphertextValue) {
    throw new Error("Stored Apple refresh token is invalid.");
  }
  const decipher = crypto.createDecipheriv(
    "aes-256-gcm",
    encryptionKey(),
    Buffer.from(ivValue, "base64url")
  );
  decipher.setAuthTag(Buffer.from(tagValue, "base64url"));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextValue, "base64url")),
    decipher.final()
  ]).toString("utf8");
}
