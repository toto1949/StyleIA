import Foundation

/// One directed animate clip for a scene (Talking, Cinematic, etc.).
struct SceneVideoClip: Codable, Equatable, Identifiable {
    var id: String { cacheKey }

    let cacheKey: String
    let motionStyle: String
    let spokenLine: String?
    let directionNote: String?
    let videoURL: URL
    let createdAt: Date

    var style: VideoMotionStyle {
        VideoMotionStyle(rawValue: motionStyle) ?? .cinematic
    }

    var displayTitle: String {
        style.title
    }

    var captionText: String? {
        guard let spokenLine else { return nil }
        let trimmed = spokenLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A completed scene generation, as stored in history and shown on the result screen.
struct GenerationResult: Codable, Equatable, Identifiable {
    let id: String
    let sceneId: String
    let sceneName: String
    let sceneLocation: String
    let imageURL: URL
    /// Latest directed clip URL (convenience / backward compatibility).
    var videoURL: URL?
    /// Spoken caption from the latest Talking clip.
    var videoCaption: String?
    /// All directed clips kept for this scene (Talking + Cinematic + …).
    var videoClips: [SceneVideoClip]
    let timeOfDay: TimeOfDay
    let weather: WeatherOption
    let pose: PoseOption
    let hasCompanion: Bool
    let isReroll: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, sceneId, sceneName, sceneLocation, imageURL
        case videoURL, videoCaption, videoClips
        case timeOfDay, weather, pose, hasCompanion, isReroll, createdAt
    }

    init(
        id: String,
        sceneId: String,
        sceneName: String,
        sceneLocation: String,
        imageURL: URL,
        videoURL: URL? = nil,
        videoCaption: String? = nil,
        videoClips: [SceneVideoClip] = [],
        timeOfDay: TimeOfDay,
        weather: WeatherOption,
        pose: PoseOption,
        hasCompanion: Bool,
        isReroll: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.sceneId = sceneId
        self.sceneName = sceneName
        self.sceneLocation = sceneLocation
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.videoCaption = videoCaption
        self.videoClips = videoClips
        self.timeOfDay = timeOfDay
        self.weather = weather
        self.pose = pose
        self.hasCompanion = hasCompanion
        self.isReroll = isReroll
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sceneId = try container.decode(String.self, forKey: .sceneId)
        sceneName = try container.decode(String.self, forKey: .sceneName)
        sceneLocation = try container.decode(String.self, forKey: .sceneLocation)
        imageURL = try container.decode(URL.self, forKey: .imageURL)
        videoURL = try container.decodeIfPresent(URL.self, forKey: .videoURL)
        videoCaption = try container.decodeIfPresent(String.self, forKey: .videoCaption)
        videoClips = try container.decodeIfPresent([SceneVideoClip].self, forKey: .videoClips) ?? []
        timeOfDay = try container.decode(TimeOfDay.self, forKey: .timeOfDay)
        weather = try container.decode(WeatherOption.self, forKey: .weather)
        pose = try container.decode(PoseOption.self, forKey: .pose)
        hasCompanion = try container.decode(Bool.self, forKey: .hasCompanion)
        isReroll = try container.decode(Bool.self, forKey: .isReroll)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // Migrate older history that only had a single videoURL.
        if videoClips.isEmpty, let videoURL {
            videoClips = [
                SceneVideoClip(
                    cacheKey: "legacy|\(id)",
                    motionStyle: "cinematic",
                    spokenLine: videoCaption,
                    directionNote: nil,
                    videoURL: videoURL,
                    createdAt: createdAt
                )
            ]
        }
    }

    var hasAnyVideo: Bool {
        !videoClips.isEmpty || videoURL != nil
    }

    /// Upserts a directed clip and keeps `videoURL` pointing at the latest.
    mutating func upsert(clip: SceneVideoClip, maxClips: Int = 4) {
        if let index = videoClips.firstIndex(where: { $0.cacheKey == clip.cacheKey }) {
            videoClips[index] = clip
        } else {
            videoClips.insert(clip, at: 0)
        }
        if videoClips.count > maxClips {
            videoClips = Array(videoClips.prefix(maxClips))
        }
        videoURL = clip.videoURL
        videoCaption = clip.captionText
    }
}
