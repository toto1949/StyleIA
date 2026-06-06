import Foundation

enum StyleGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case casual
    case professional
    case wedding
    case sporty
    case luxury
    case streetwear

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .casual: "🧢"
        case .professional: "💼"
        case .wedding: "💒"
        case .sporty: "🏃"
        case .luxury: "💎"
        case .streetwear: "🛹"
        }
    }

    var label: String {
        switch self {
        case .casual: String(localized: "style.casual")
        case .professional: String(localized: "style.professional")
        case .wedding: String(localized: "style.wedding")
        case .sporty: String(localized: "style.sporty")
        case .luxury: String(localized: "style.luxury")
        case .streetwear: String(localized: "style.streetwear")
        }
    }
}
