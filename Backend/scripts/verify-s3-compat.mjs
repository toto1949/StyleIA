import assert from "node:assert/strict";
import { objectEncryptionOptions } from "../src/services/s3-compat.mjs";

assert.deepEqual(
  objectEncryptionOptions("https://sample-ref.storage.supabase.co/storage/v1/s3"),
  {},
  "Supabase S3 rejects the x-amz-server-side-encryption header"
);
assert.deepEqual(
  objectEncryptionOptions("https://sample-ref.supabase.co/storage/v1/s3/"),
  {},
  "Both Supabase S3 endpoint forms are supported"
);
assert.deepEqual(
  objectEncryptionOptions("https://sample-ref.storage.supabase.co/other-path"),
  { ServerSideEncryption: "AES256" },
  "Unrelated endpoints must retain explicit encryption"
);
assert.deepEqual(
  objectEncryptionOptions("https://example.r2.cloudflarestorage.com"),
  { ServerSideEncryption: "AES256" }
);
assert.deepEqual(objectEncryptionOptions(), { ServerSideEncryption: "AES256" });
console.log("S3 encryption header compatibility checks passed.");
