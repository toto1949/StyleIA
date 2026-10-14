import crypto from "node:crypto";
import { store } from "../src/services/store-instance.mjs";

await store.init();

const userId = crypto.randomUUID();
const jobId = crypto.randomUUID();
const publicJobId = crypto.randomUUID();
const providerRequestId = `queue-${crypto.randomUUID()}`;

try {
  await store.mutate((data) => {
    data.users.push({
      id: userId,
      email: `provider-state-${userId}@example.invalid`,
      fullName: "Provider State Test",
      createdAt: new Date().toISOString()
    });
    data.jobs.push({
      id: jobId,
      jobId: publicJobId,
      userId,
      type: "scene-video",
      status: "processing",
      progress: 61,
      providerRequestId,
      providerModel: "fal-ai/elevenlabs/tts/turbo-v2.5",
      providerPhase: "tts",
      providerVideoUrl: "https://fal.media/private/base-video.mp4",
      providerAudioUrl: null,
      attemptCount: 1,
      estimatedCostUSD: 0.12,
      createdAt: new Date().toISOString()
    });
  });

  const persisted = (await store.snapshot()).jobs.find((job) => job.id === jobId);
  if (!persisted) {
    throw new Error("Provider-state job was not persisted.");
  }
  if (persisted.providerRequestId !== providerRequestId
      || persisted.providerModel !== "fal-ai/elevenlabs/tts/turbo-v2.5"
      || persisted.providerPhase !== "tts"
      || persisted.providerVideoUrl !== "https://fal.media/private/base-video.mp4"
      || persisted.status !== "processing") {
    throw new Error(`Provider state did not round-trip: ${JSON.stringify({
      providerRequestId: persisted.providerRequestId,
      providerModel: persisted.providerModel,
      providerPhase: persisted.providerPhase,
      providerVideoUrl: persisted.providerVideoUrl,
      status: persisted.status
    })}`);
  }

  console.log("Durable provider-state PostgreSQL round-trip passed.");
} finally {
  await store.mutate((data) => {
    data.jobs = data.jobs.filter((job) => job.id !== jobId);
    data.users = data.users.filter((user) => user.id !== userId);
  }).catch(() => {});
  await store.close?.();
}
