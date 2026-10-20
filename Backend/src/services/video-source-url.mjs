/**
 * Re-sign a private scene image immediately before requesting an animation.
 *
 * The URL persisted on a scene job expires (normally after ten minutes),
 * whereas its private S3 object key remains valid. Never send an expired
 * presigned URL to an external video provider when an object key is available.
 */
export async function resolveVideoSourceImageURL(videoJob, sourceJob, storage) {
  if (
    storage?.enabled &&
    sourceJob &&
    sourceJob.type === "scene" &&
    sourceJob.userId === videoJob.userId &&
    sourceJob.jobId === videoJob.sourceJobId &&
    sourceJob.imageObjectKey
  ) {
    return storage.createDownloadURL(sourceJob.imageObjectKey);
  }
  return videoJob.sourceImageURL;
}
