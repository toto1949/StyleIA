import Foundation

/// A completed scene generation, as stored in history and shown on the result screen.
struct GenerationResult: Codable, Equatable, Identifiable {
    let id: String
    let sceneId: String
    let sceneName: String
    let sceneLocation: String
    let imageURL: URL
    /// Set once the user animates the scene into a short video clip.
    var videoURL: URL?
    let timeOfDay: TimeOfDay
    let weather: WeatherOption
    let pose: PoseOption
    let hasCompanion: Bool
    let isReroll: Bool
    let createdAt: Date
}
