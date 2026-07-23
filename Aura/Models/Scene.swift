import Foundation

/// A scene template the user can be generated into.
/// Named `SceneTemplate` to avoid colliding with SwiftUI's `Scene`.
struct SceneTemplate: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let location: String
    let category: SceneCategory
    let description: String
    let basePrompt: String
    let thumbnailURL: URL?
    let defaultOutfit: String
    let maleOutfit: String?
    let femaleOutfit: String?
    let availableTimes: [TimeOfDay]
    let availableWeather: [WeatherOption]
    let defaultTime: TimeOfDay
    let defaultWeather: WeatherOption
    let badge: SceneBadge?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case location
        case category
        case description
        case basePrompt = "base_prompt"
        case thumbnailURL = "thumbnail_url"
        case defaultOutfit = "default_outfit"
        case maleOutfit = "male_outfit"
        case femaleOutfit = "female_outfit"
        case availableTimes = "available_times"
        case availableWeather = "available_weather"
        case defaultTime = "default_time"
        case defaultWeather = "default_weather"
        case badge
    }

    var isCustom: Bool {
        id == "custom" || id.hasPrefix("custom-")
    }

    /// A user-described scene template; the backend builds the prompt from this text.
    static func custom(name: String, description: String, outfit: String) -> SceneTemplate {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutfit = outfit.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        return SceneTemplate(
            id: "custom-\(UUID().uuidString.lowercased())",
            name: trimmedName.isEmpty ? "My Scene" : trimmedName,
            location: "Custom Scene",
            category: .custom,
            description: trimmedDescription,
            basePrompt: trimmedDescription,
            thumbnailURL: nil,
            defaultOutfit: trimmedOutfit.isEmpty
                ? "a stylish outfit that naturally fits the described scene, editorial fashion quality"
                : trimmedOutfit,
            maleOutfit: nil,
            femaleOutfit: nil,
            availableTimes: TimeOfDay.allCases,
            availableWeather: WeatherOption.allCases,
            defaultTime: .goldenHour,
            defaultWeather: .sunny,
            badge: nil
        )
    }
}

enum SceneCategory: String, Codable, CaseIterable, Identifiable {
    case urban
    case nature
    case luxury
    case events
    case professional
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .professional:
            return "Pro Headshots"
        case .custom:
            return "Yours"
        default:
            return rawValue.capitalized
        }
    }

    /// Categories shown as filter chips in the picker.
    static var pickerCases: [SceneCategory] {
        [.urban, .nature, .luxury, .events, .professional, .custom]
    }
}

enum SceneBadge: String, Codable {
    case popular
    case new
    case premium
    case limited

    var title: String {
        switch self {
        case .popular:
            return "POPULAR"
        case .new:
            return "NEW"
        case .premium:
            return "PREMIUM"
        case .limited:
            return "LIMITED"
        }
    }
}

enum SceneCatalog {
    private final class BundleAnchor {}

    /// Bundled copy of the backend's scenes.json, used as the catalog source
    /// when the backend hasn't been reached yet (and for thumbnails offline).
    static let bundled: [SceneTemplate] = {
        let bundle = Bundle(for: BundleAnchor.self)
        guard
            let url = bundle.url(forResource: "scenes", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(ScenesPayload.self, from: data)
        else {
            return []
        }

        return payload.scenes
    }()
}

struct ScenesPayload: Codable {
    let scenes: [SceneTemplate]
}
