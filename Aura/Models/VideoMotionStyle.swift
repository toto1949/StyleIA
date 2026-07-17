import Foundation

/// Director modes for Pro video animation — what kind of living clip to make.
enum VideoMotionStyle: String, Codable, CaseIterable, Identifiable {
    case cinematic
    case talking
    case portrait
    case energy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .talking: return "Talking"
        case .portrait: return "Portrait"
        case .energy: return "Energy"
        }
    }

    var subtitle: String {
        switch self {
        case .cinematic: return "Slow push-in, living editorial"
        case .talking: return "Spoken voice + interview caption"
        case .portrait: return "Near-still beauty breathing shot"
        case .energy: return "Atmosphere-forward scene life"
        }
    }

    var systemImage: String {
        switch self {
        case .cinematic: return "film"
        case .talking: return "quote.bubble.fill"
        case .portrait: return "person.crop.square"
        case .energy: return "sparkles"
        }
    }

    var showsTalkLine: Bool { self == .talking }
}

/// Suggested spoken lines for Talking mode, tuned to scene vibe.
enum VideoTalkSuggestions {
    static func lines(for sceneName: String, location: String, category: SceneCategory?) -> [String] {
        let haystack = "\(sceneName) \(location) \(category?.rawValue ?? "")".lowercased()

        if haystack.contains("keynote") || haystack.contains("stage") || category == .professional {
            return [
                "Here's what nobody is saying.",
                "Let's get straight to the point.",
                "This changes everything."
            ]
        }

        if haystack.contains("red carpet") || haystack.contains("nba") || haystack.contains("coachella")
            || category == .events {
            return [
                "You're not going to believe this night.",
                "I still can't believe I'm here.",
                "This is only the beginning."
            ]
        }

        if haystack.contains("cafe") || haystack.contains("paris") || category == .luxury {
            return [
                "I could stay here forever.",
                "Tell me that again.",
                "This feels unreal."
            ]
        }

        if category == .urban {
            return [
                "The city never sleeps.",
                "Watch this.",
                "I live for nights like this."
            ]
        }

        return [
            "I still can't believe I'm here.",
            "This feels unreal.",
            "You're going to want to see this."
        ]
    }
}

/// Free-text / chip suggestions for how the clip should move.
enum VideoDirectionSuggestions {
    static let chips: [String] = [
        "Slow confident walk toward camera",
        "Look off-camera then turn back and smile",
        "Soft laugh and a small head tilt",
        "Hold a powerful pose with wind in hair",
        "Wave casually like greeting a friend"
    ]
}
