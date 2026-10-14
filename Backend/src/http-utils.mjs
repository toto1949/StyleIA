import { StringDecoder } from "node:string_decoder";

export class HttpError extends Error {
  constructor(statusCode, message, { code, headers } = {}) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.headers = headers;
  }
}

export function sendJSON(response, statusCode, payload, headers = {}) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    ...corsHeaders(),
    ...headers
  });
  response.end(body);
}

export function sendError(response, error) {
  const statusCode = error instanceof HttpError ? error.statusCode : 500;
  const message = statusCode >= 500 ? "Something went wrong." : error.message;
  sendJSON(response, statusCode, {
    error: {
      code: error instanceof HttpError && error.code ? error.code : `HTTP_${statusCode}`,
      message
    },
    // Kept during the 1.0 transition for the existing iOS decoder.
    message
  }, error instanceof HttpError ? error.headers : undefined);
}

export function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type,Idempotency-Key,X-SceneMe-App-Store-Transaction-ID"
  };
}

export async function readJSON(request, maxBytes = 1_000_000) {
  const raw = await readRawBody(request, maxBytes);
  if (raw.length === 0) {
    return {};
  }

  try {
    return JSON.parse(raw.toString("utf8"));
  } catch {
    throw new HttpError(400, "Invalid JSON body.");
  }
}

export async function readRawBody(request, maxBytes) {
  const chunks = [];
  let total = 0;

  for await (const chunk of request) {
    total += chunk.length;
    if (total > maxBytes) {
      throw new HttpError(413, "Request body is too large.");
    }
    chunks.push(chunk);
  }

  return Buffer.concat(chunks);
}

export function bearerToken(request) {
  const authorization = request.headers.authorization || "";
  const [scheme, token] = authorization.split(" ");
  if (scheme !== "Bearer" || !token) {
    throw new HttpError(401, "Unauthorized.");
  }
  return token;
}

export function textFramePayload(buffer) {
  const decoder = new StringDecoder("utf8");
  return decoder.write(buffer);
}
