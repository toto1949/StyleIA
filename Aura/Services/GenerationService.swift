import Foundation

struct SceneJobResponse: Decodable {
    let jobId: String
    let kind: String?
    let status: String
    let progress: Int
    let imageURL: URL?
    let videoURL: URL?
    let sceneId: String
    let sceneName: String
    let sceneLocation: String
    let subjectGender: String?
    let timeOfDay: String
    let weather: String
    let pose: String
    let hasCompanion: Bool
    let isReroll: Bool
    let createdAt: String
    let error: String?
}

/// Creates scene generation jobs on the backend and polls them to completion.
struct GenerationService {
    let api: APIService

    private struct CustomScenePayload: Encodable {
        let name: String
        let basePrompt: String
        let outfit: String
    }

    private struct SceneJobRequest: Encodable {
        let s3Key: String
        let companionS3Key: String?
        let sceneId: String
        let customScene: CustomScenePayload?
        let subjectGender: String
        let companionKind: String
        let timeOfDay: String
        let weather: String
        let pose: String
        let seed: Int
    }

    func generate(
        request: GenerationRequest,
        s3Key: String,
        companionS3Key: String?,
        token: String,
        onProgress: @MainActor @escaping (Int) -> Void
    ) async throws -> GenerationResult {
        let scene = request.scene
        let job: SceneJobResponse = try await api.post(
            "scene-jobs",
            body: SceneJobRequest(
                s3Key: s3Key,
                companionS3Key: companionS3Key,
                sceneId: scene.id,
                customScene: scene.isCustom
                    ? CustomScenePayload(name: scene.name, basePrompt: scene.basePrompt, outfit: scene.defaultOutfit)
                    : nil,
                subjectGender: request.subjectGender.rawValue,
                companionKind: request.companionKind.rawValue,
                timeOfDay: request.timeOfDay.rawValue,
                weather: request.weather.rawValue,
                pose: request.pose.rawValue,
                seed: Int.random(in: 1...999_999_999)
            ),
            token: token
        )

        return try await waitForCompletion(jobId: job.jobId, token: token, onProgress: onProgress)
    }

    /// Animates a completed scene into a short cinematic clip and returns the video URL.
    func animate(
        jobId: String,
        token: String,
        onProgress: @MainActor @escaping (Int) -> Void
    ) async throws -> URL {
        let job: SceneJobResponse = try await api.post(
            "scene-jobs/\(jobId)/video",
            body: APIService.EmptyBody(),
            token: token
        )

        if job.status == "completed", let videoURL = job.videoURL {
            return videoURL
        }

        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 280 {
            try Task.checkCancellation()
            let polled: SceneJobResponse = try await api.get("scene-jobs/\(job.jobId)", token: token)

            await MainActor.run {
                onProgress(polled.progress)
            }

            switch polled.status {
            case "completed":
                guard let videoURL = polled.videoURL else {
                    throw SceneMeAPIError.invalidResponse
                }
                return videoURL
            case "failed":
                throw SceneMeAPIError.failed(polled.error ?? "Video generation failed.")
            case "cancelled":
                throw SceneMeAPIError.cancelled
            default:
                try await Task.sleep(for: .milliseconds(2_000))
            }
        }

        throw SceneMeAPIError.timedOut
    }

    /// Regenerates only the outfit: same scene, same face, same background.
    func rerollOutfit(
        jobId: String,
        token: String,
        onProgress: @MainActor @escaping (Int) -> Void
    ) async throws -> GenerationResult {
        let job: SceneJobResponse = try await api.post(
            "scene-jobs/\(jobId)/reroll",
            body: APIService.EmptyBody(),
            token: token
        )

        return try await waitForCompletion(jobId: job.jobId, token: token, onProgress: onProgress)
    }

    func cancel(jobId: String, token: String) async throws {
        try await api.delete("scene-jobs/\(jobId)", token: token)
    }

    private func waitForCompletion(
        jobId: String,
        token: String,
        onProgress: @MainActor @escaping (Int) -> Void
    ) async throws -> GenerationResult {
        let startedAt = Date()

        while Date().timeIntervalSince(startedAt) < 190 {
            try Task.checkCancellation()
            let job: SceneJobResponse = try await api.get("scene-jobs/\(jobId)", token: token)

            await MainActor.run {
                onProgress(job.progress)
            }

            switch job.status {
            case "completed":
                guard let imageURL = job.imageURL else {
                    throw SceneMeAPIError.invalidResponse
                }
                return result(from: job, imageURL: imageURL)
            case "failed":
                throw SceneMeAPIError.failed(job.error ?? "Scene generation failed.")
            case "cancelled":
                throw SceneMeAPIError.cancelled
            default:
                try await Task.sleep(for: .milliseconds(1_500))
            }
        }

        throw SceneMeAPIError.timedOut
    }

    private func result(from job: SceneJobResponse, imageURL: URL) -> GenerationResult {
        GenerationResult(
            id: job.jobId,
            sceneId: job.sceneId,
            sceneName: job.sceneName,
            sceneLocation: job.sceneLocation,
            imageURL: imageURL,
            videoURL: job.videoURL,
            timeOfDay: TimeOfDay(rawValue: job.timeOfDay) ?? .goldenHour,
            weather: WeatherOption(rawValue: job.weather) ?? .sunny,
            pose: PoseOption(rawValue: job.pose) ?? .casual,
            hasCompanion: job.hasCompanion,
            isReroll: job.isReroll,
            createdAt: Self.parseDate(job.createdAt) ?? Date()
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
