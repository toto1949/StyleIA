import Foundation
import Security

/// The signed-in user, persisted across launches.
struct SceneMeSession: Codable, Equatable {
    let userId: String
    let email: String
    let fullName: String
    let accessToken: String

    var displayName: String {
        if !fullName.isEmpty {
            return fullName
        }
        return String(email.split(separator: "@").first ?? "Me")
    }
}

/// Keychain-backed storage for the session token, so credentials survive
/// reinstall-free launches and never sit in UserDefaults.
struct SessionStore {
    private let service = "com.sceneme.session"
    private let account = "current-user"

    func load() -> SceneMeSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let session = try? JSONDecoder().decode(SceneMeSession.self, from: data)
        else {
            return nil
        }

        return session
    }

    func save(_ session: SceneMeSession) {
        guard let data = try? JSONEncoder().encode(session) else {
            return
        }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
