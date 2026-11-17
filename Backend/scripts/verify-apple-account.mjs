import assert from "node:assert/strict";
import crypto from "node:crypto";

const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
process.env.NODE_ENV = "test";
process.env.APPLE_CLIENT_ID = "com.sceneme.test";
process.env.APPLE_TEAM_ID = "TESTTEAM01";
process.env.APPLE_KEY_ID = "TESTKEY001";
process.env.APPLE_PRIVATE_KEY = privateKey.export({ type: "pkcs8", format: "pem" });
process.env.STYLEAI_DATA_ENCRYPTION_KEY = "test-only-encryption-key-not-production";
const { exchangeAppleAuthorizationCode, revokeAppleRefreshToken } = await import("../src/services/apple-account-service.mjs");

const originalFetch = globalThis.fetch;
let nextResponse;
let calls = 0;
globalThis.fetch = async (url, options) => {
  calls += 1;
  assert.equal(options.method, "POST");
  assert.equal(options.headers["Content-Type"], "application/x-www-form-urlencoded");
  const body = options.body;
  assert.equal(body.get("client_id"), "com.sceneme.test");
  const [headerPart, payloadPart, signaturePart] = body.get("client_secret").split(".");
  const header = JSON.parse(Buffer.from(headerPart, "base64url"));
  const claims = JSON.parse(Buffer.from(payloadPart, "base64url"));
  assert.equal(header.alg, "ES256");
  assert.equal(header.kid, "TESTKEY001");
  assert.equal(claims.iss, "TESTTEAM01");
  assert.equal(claims.sub, body.get("client_id"));
  assert.equal(claims.aud, "https://appleid.apple.com");
  assert.equal(claims.exp - claims.iat, 300);
  assert.ok(crypto.verify("sha256", Buffer.from(`${headerPart}.${payloadPart}`), {
    key: publicKey, dsaEncoding: "ieee-p1363"
  }, Buffer.from(signaturePart, "base64url")));
  if (url.endsWith("/auth/token")) {
    assert.equal(body.get("grant_type"), "authorization_code");
    assert.equal(body.get("code"), "test-authorization-code");
  } else {
    assert.equal(url, "https://appleid.apple.com/auth/revoke");
    assert.equal(body.get("token"), "test-refresh-token");
  }
  return nextResponse();
};

try {
  for (const code of ["invalid_client", "invalid_grant", "invalid_request"]) {
    nextResponse = () => new Response(JSON.stringify({ error: code, error_description: "sensitive-description" }), { status: 400 });
    const before = calls;
    await assert.rejects(exchangeAppleAuthorizationCode("test-authorization-code"), {
      message: `Apple authorization-code exchange failed (400; ${code}).`
    });
    assert.equal(calls, before + 1, "Do not retry one-time codes automatically");
  }
  for (const payload of [{ error: "secret-value", refresh_token: "private-token" }, null, {}]) {
    nextResponse = () => new Response(JSON.stringify(payload), { status: 400 });
    await assert.rejects(exchangeAppleAuthorizationCode("test-authorization-code"), {
      message: "Apple authorization-code exchange failed (400; unrecognized_response)."
    });
  }
  nextResponse = () => new Response("not-json", { status: 502 });
  await assert.rejects(exchangeAppleAuthorizationCode("test-authorization-code"), /502; unrecognized_response/);
  nextResponse = () => new Response(JSON.stringify({ refresh_token: "test-refresh-token" }), { status: 200 });
  const encrypted = await exchangeAppleAuthorizationCode("test-authorization-code");
  assert.equal(encrypted.split(".").length, 3);
  assert.ok(!encrypted.includes("test-refresh-token"));
  nextResponse = () => new Response("", { status: 200 });
  assert.equal(await revokeAppleRefreshToken(encrypted), true);
} finally {
  globalThis.fetch = originalFetch;
}
console.log("Apple account tests passed: JWT signature, safe OAuth errors, no retry, encrypted token revocation. All provider responses mocked; no live Apple request.");
