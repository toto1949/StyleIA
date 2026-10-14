import assert from "node:assert/strict";
import sharp from "sharp";

// Keep the pixel-limit case small and deterministic. Configuration is loaded
// only after these values are set.
process.env.STYLEAI_MAX_UPLOAD_PIXELS = "100";
process.env.STYLEAI_MAX_UPLOAD_BYTES = "1000000";

const { objectStorage } = await import("../src/services/object-storage-service.mjs");

const validInput = await sharp({
  create: {
    width: 10,
    height: 10,
    channels: 3,
    background: { r: 28, g: 41, b: 66 }
  }
})
  .withMetadata({ orientation: 6, density: 300 })
  .jpeg({ quality: 95 })
  .toBuffer();

const sanitized = await objectStorage.sanitizeJPEGBuffer(validInput);
const sanitizedMetadata = await sharp(sanitized.data).metadata();
assert.equal(sanitizedMetadata.format, "jpeg");
assert.equal(sanitized.metadata.width, 10);
assert.equal(sanitized.metadata.height, 10);
assert.equal(sanitizedMetadata.orientation, undefined, "orientation metadata must be removed");
assert.equal(sanitizedMetadata.exif, undefined, "EXIF metadata must be removed");
assert.equal(sanitizedMetadata.xmp, undefined, "XMP metadata must be removed");
assert.match(sanitized.sha256, /^[a-f0-9]{64}$/);

const pngInput = await sharp({
  create: {
    width: 10,
    height: 10,
    channels: 4,
    background: { r: 28, g: 41, b: 66, alpha: 1 }
  }
}).png().toBuffer();

await assert.rejects(
  objectStorage.sanitizeJPEGBuffer(pngInput),
  (error) => error?.statusCode === 415
);
await assert.rejects(
  objectStorage.sanitizeJPEGBuffer(validInput.subarray(0, Math.floor(validInput.length / 2))),
  (error) => error?.statusCode === 415
);
await assert.rejects(
  objectStorage.sanitizeJPEGBuffer(Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x01, 0x02, 0x03])),
  (error) => error?.statusCode === 415
);

const oversizedPixels = await sharp({
  create: {
    width: 11,
    height: 10,
    channels: 3,
    background: { r: 28, g: 41, b: 66 }
  }
}).jpeg().toBuffer();
await assert.rejects(
  objectStorage.sanitizeJPEGBuffer(oversizedPixels),
  (error) => error?.statusCode === 415
);

console.log("Upload decode, metadata stripping, format, truncation and pixel-limit checks passed.");
