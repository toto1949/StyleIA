export function base64URLEncode(input) {
  return Buffer.from(input)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export function base64URLDecode(input) {
  const normalized = input.replaceAll("-", "+").replaceAll("_", "/");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(normalized + padding, "base64");
}

export function parseBase64URLJSON(input) {
  return JSON.parse(base64URLDecode(input).toString("utf8"));
}
