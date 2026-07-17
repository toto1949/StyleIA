import Foundation

struct SceneJobResponse: Decodable {
    let jobId: String
    let kind: String?
    let status: String
    let progress: Int
    let imageURL: URL?
    let videoURL: URL?
    let videoClips: [VideoClipPayload]?
    let sceneId: String
    let sceneName: String
    let sceneLocation: String
    let subjectGender: String?
    let timeOfDay: String
    let weather: String
    let pose: String
    let hasCompanion: Bool
    let isReroll: Bool
    let motionStyle: String?
    let spokenLine: String?
    let directionNote: String?
    let createdAt: String?
    let error: String?
}

struct VideoClipPayload: Decodable {
    let cacheKey: String
    let motionStyle: String
    let spokenLine: String?
    let directionNote: String?
    let videoURL: URL
    let createdAt: String?
}

/// Creates scene generation jobs on the backend and polls them to completion.
struct GenerationService {
    let api: APIService

    private struct HistoryPayload: Decodable {
        let items: [SceneJobResponse]
        let total: Int
    }

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

    /// Server-side history for the signed-in user only (`auth.sub`).
    func fetchHistory(token: String, page: Int = 1, limit: Int = 50) async throws -> [GenerationResult] {
        let payload: HistoryPayload = try await api.get(
            "history",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit))
            ],
            token: token
        )
        return payload.items.compactMap { job in
            guard let imageURL = job.imageURL, job.status == "completed" else { return nil }
            return result(from: job, imageURL: imageURL)
        }
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

    private struct VideoJobRequest: Encodable {
        let motionStyle: String
        let spokenLine: String
        let directionNote: String
    }

    struct AnimatedClip {
        let videoURL: URL
        let caption: String?
        let motionStyle: String?
        let spokenLine: String?
        let directionNote: String?
        let cacheKey: String?
        let library: [SceneVideoClip]
    }

    /// Animates a completed scene into a short directed clip and returns the video URL.
    func animate(
        jobId: String,
        motionStyle: VideoMotionStyle,
        spokenLine: String,
        directionNote: String,
        token: String,
        onProgress: @MainActor @escaping (Int) -> Void
    ) async throws -> AnimatedClip {
        let job: SceneJobResponse = try await api.post(
            "scene-jobs/\(jobId)/video",
            body: VideoJobRequest(
                motionStyle: motionStyle.rawValue,
                spokenLine: spokenLine,
                directionNote: directionNote
            ),
            token: token
        )

        if job.status == "completed", let videoURL = job.videoURL {
            return animatedClip(
                from: job,
                videoURL: videoURL,
                fallbackStyle: motionStyle,
                fallbackLine: spokenLine,
                fallbackDirection: directionNote
            )
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
                return animatedClip(
                    from: polled,
                    videoURL: videoURL,
                    fallbackStyle: motionStyle,
                    fallbackLine: spokenLine,
                    fallbackDirection: directionNote
                )
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

    private func animatedClip(
        from job: SceneJobResponse,
        videoURL: URL,
        fallbackStyle: VideoMotionStyle,
        fallbackLine: String,
        fallbackDirection: String
    ) -> AnimatedClip {
        let style = job.motionStyle ?? fallbackStyle.rawValue
        let line = job.spokenLine ?? fallbackLine
        let direction = job.directionNote ?? fallbackDirection
        let library = decodedClips(from: job)
        let matched = library.first(where: {
            $0.motionStyle == style
                && ($0.spokenLine ?? "") == line
                && ($0.directionNote ?? "") == direction
        }) ?? library.first(where: { $0.videoURL == videoURL })

        return AnimatedClip(
            videoURL: videoURL,
            caption: matched?.captionText ?? (line.isEmpty ? nil : line),
            motionStyle: style,
            spokenLine: line.isEmpty ? nil : line,
            directionNote: direction.isEmpty ? nil : direction,
            cacheKey: matched?.cacheKey,
            library: library
        )
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
        let clips = decodedClips(from: job)
        return GenerationResult(
            id: job.jobId,
            sceneId: job.sceneId,
            sceneName: job.sceneName,
            sceneLocation: job.sceneLocation,
            imageURL: imageURL,
            videoURL: job.videoURL ?? clips.first?.videoURL,
            videoCaption: job.spokenLine ?? clips.first?.captionText,
            videoClips: clips,
            timeOfDay: TimeOfDay(rawValue: job.timeOfDay) ?? .goldenHour,
            weather: WeatherOption(rawValue: job.weather) ?? .sunny,
            pose: PoseOption(rawValue: job.pose) ?? .casual,
            hasCompanion: job.hasCompanion,
            isReroll: job.isReroll,
            createdAt: Self.parseDate(job.createdAt ?? "") ?? Date()
        )
    }

    private func decodedClips(from job: SceneJobResponse) -> [SceneVideoClip] {
        let payloads = job.videoClips ?? []
        let mapped = payloads.map { payload in
            SceneVideoClip(
                cacheKey: payload.cacheKey,
                motionStyle: payload.motionStyle,
                spokenLine: payload.spokenLine,
                directionNote: payload.directionNote,
                videoURL: payload.videoURL,
                createdAt: Self.parseDate(payload.createdAt ?? "") ?? Date()
            )
        }
        if !mapped.isEmpty {
            return mapped
        }
        if let videoURL = job.videoURL {
            return [
                SceneVideoClip(
                    cacheKey: "\(job.motionStyle ?? "cinematic")|\(job.spokenLine ?? "")|\(job.directionNote ?? "")",
                    motionStyle: job.motionStyle ?? "cinematic",
                    spokenLine: job.spokenLine,
                    directionNote: job.directionNote,
                    videoURL: videoURL,
                    createdAt: Self.parseDate(job.createdAt ?? "") ?? Date()
                )
            ]
        }
        return []
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
