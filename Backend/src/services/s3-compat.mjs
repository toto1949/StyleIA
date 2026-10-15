/**
 * Supabase Storage encrypts stored objects at rest but its S3 compatibility
 * layer does not accept the explicit x-amz-server-side-encryption request header.
 * Keep that header for AWS S3 and compatible providers which support it.
 */
export function objectEncryptionOptions(endpoint = "") {
  if (!endpoint) return { ServerSideEncryption: "AES256" };
  let parsed;
  try {
    parsed = new URL(endpoint);
  } catch {
    return { ServerSideEncryption: "AES256" };
  }
  const host = parsed.hostname.toLowerCase();
  const isSupabaseHost = host.endsWith(".supabase.co");
  const isSupabaseS3Path = parsed.pathname.replace(/\/+$/, "") === "/storage/v1/s3";
  if (parsed.protocol === "https:" && isSupabaseHost && isSupabaseS3Path) {
    return {};
  }
  return { ServerSideEncryption: "AES256" };
}
