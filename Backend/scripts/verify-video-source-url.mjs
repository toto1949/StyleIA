import { resolveVideoSourceImageURL } from "../src/services/video-source-url.mjs";
import assert from "node:assert/strict";

const userId = "11111111-1111-4111-8111-111111111111";
const videoJob = {
  userId,
  sourceJobId: "source-1",
  sourceImageURL: "https://example.test/expired-signed-url",
};
const storage = {
  enabled: true,
  createDownloadURL: async (key) => {
    assert.equal(key, "private/user/job/image.jpg");
    return "https://example.test/fresh-signed-url";
  }
};
const source = {
  type: "scene",
  jobId: "source-1",
  userId,
  imageObjectKey: "private/user/job/image.jpg"
};
assert.equal(await resolveVideoSourceImageURL(videoJob, source, storage), "https://example.test/fresh-signed-url");
assert.equal(await resolveVideoSourceImageURL(videoJob, null, storage), videoJob.sourceImageURL);
assert.equal(await resolveVideoSourceImageURL(videoJob, { ...source, userId: "other" }, storage), videoJob.sourceImageURL);
assert.equal(await resolveVideoSourceImageURL(videoJob, source, { ...storage, enabled: false }), videoJob.sourceImageURL);
assert.equal(await resolveVideoSourceImageURL(videoJob, { ...source, imageObjectKey: null }, storage), videoJob.sourceImageURL);
console.log("Private video source is re-signed only for matching owner and source scene.");
