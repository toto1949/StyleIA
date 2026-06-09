import SwiftUI

struct StyleIAPersona: Identifiable, Equatable {
    let id: String
    let name: String
    let descriptor: String
    let match: Int
    let skin: Color
    let hair: Color
    let shirt: Color
    let cardTint: Color
    let badgeColor: Color
    let hasGlasses: Bool

    var displayName: String {
        name.replacingOccurrences(of: "\n", with: " ")
    }

    static func == (lhs: StyleIAPersona, rhs: StyleIAPersona) -> Bool {
        lhs.id == rhs.id
    }

    static let samples = [
        StyleIAPersona(
            id: "urban-classic",
            name: "Urban\nClassic",
            descriptor: "Refined -\nWarm",
            match: 94,
            skin: Color(hex: 0xE4A95F),
            hair: Color(hex: 0x1E160C),
            shirt: Color(hex: 0x1C344B),
            cardTint: Color(hex: 0x0D1723),
            badgeColor: StyleIATheme.moss,
            hasGlasses: false
        ),
        StyleIAPersona(
            id: "earth-dandy",
            name: "Earth\nDandy",
            descriptor: "Earthy -\nGold",
            match: 92,
            skin: Color(hex: 0xC48D4A),
            hair: Color(hex: 0x2F1D0B),
            shirt: Color(hex: 0x3A2611),
            cardTint: Color(hex: 0x111716),
            badgeColor: StyleIATheme.gold,
            hasGlasses: true
        ),
        StyleIAPersona(
            id: "neo-formal",
            name: "Neo\nFormal",
            descriptor: "Cool -\nSharp",
            match: 89,
            skin: Color(hex: 0xE8A767),
            hair: Color(hex: 0x151011),
            shirt: Color(hex: 0x1B1A36),
            cardTint: Color(hex: 0x12131F),
            badgeColor: Color(hex: 0x5F83DA),
            hasGlasses: false
        )
    ]
}
