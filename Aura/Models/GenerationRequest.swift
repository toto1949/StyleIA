import Foundation

enum TimeOfDay: String, Codable, CaseIterable, Identifiable {
    case morning
    case goldenHour = "golden_hour"
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:
            return "Morning"
        case .goldenHour:
            return "Golden Hr"
        case .night:
            return "Night"
        }
    }

    var emoji: String {
        switch self {
        case .morning:
            return "🌅"
        case .goldenHour:
            return "🌇"
        case .night:
            return "🌃"
        }
    }
}

enum WeatherOption: String, Codable, CaseIterable, Identifiable {
    case sunny
    case rainy
    case snowy
    case foggy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunny:
            return "Clear"
        case .rainy:
            return "Rainy"
        case .snowy:
            return "Snow"
        case .foggy:
            return "Foggy"
        }
    }

    var systemImage: String {
        switch self {
        case .sunny:
            return "sun.max.fill"
        case .rainy:
            return "cloud.rain.fill"
        case .snowy:
            return "snowflake"
        case .foggy:
            return "cloud.fog.fill"
        }
    }
}

enum PoseOption: String, Codable, CaseIterable, Identifiable {
    case casual
    case walking
    case candid
    case sitting
    case action

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .casual:
            return "🧍"
        case .walking:
            return "🚶"
        case .candid:
            return "👀"
        case .sitting:
            return "🪑"
        case .action:
            return "🏃"
        }
    }
}

/// Who the photo shows; lets the backend pick the right outfit and lock
/// gender-specific identity details into the prompt.
enum SubjectGender: String, Codable, CaseIterable, Identifiable {
    case auto
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .male:
            return "Man"
        case .female:
            return "Woman"
        }
    }

    var emoji: String {
        switch self {
        case .auto:
            return "✨"
        case .male:
            return "👨"
        case .female:
            return "👩"
        }
    }
}

/// Everything needed to ask the backend for one scene generation.
struct GenerationRequest: Equatable {
    let scene: SceneTemplate
    var timeOfDay: TimeOfDay
    var weather: WeatherOption
    var pose: PoseOption
    var subjectGender: SubjectGender
    var hasCompanion: Bool

    init(scene: SceneTemplate) {
        self.scene = scene
        self.timeOfDay = scene.defaultTime
        self.weather = scene.defaultWeather
        self.pose = .casual
        self.subjectGender = .auto
        self.hasCompanion = false
    }

    /// Human readable summary shown in the "Your scene preview" footer.
    var previewSummary: String {
        var parts = [
            "\(scene.name) at \(timeOfDay.title.lowercased())",
            "\(weather.title.lowercased()) sky",
            "\(pose.rawValue) pose",
            subjectGender == .auto
                ? "auto-matched outfit"
                : "outfit styled for a \(subjectGender.title.lowercased())"
        ]
        if hasCompanion {
            parts.append("with a friend")
        }
        return parts.joined(separator: ", ") + "…"
    }
}
