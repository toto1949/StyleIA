import Foundation

/// Lightweight local profile shown in the header avatar and profile tab.
struct UserProfile: Codable, Equatable {
    var displayName: String

    var initial: String {
        String(displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    static let `default` = UserProfile(displayName: "Aura")
}
