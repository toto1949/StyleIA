import Foundation

// Secrets shim: central place to fetch the backend API base URL.
enum Secrets {
    static let companyWebsiteURL = URL(string: "https://zevyntalabs.com/")!

    static var backendAPIBaseURL: URL? {
        if
            let env = ProcessInfo.processInfo.environment["STYLEIA_API_BASE_URL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !env.isEmpty,
            let url = URL(string: env)
        {
            return url
        }

        if
            let bundleValue = (Bundle.main.object(forInfoDictionaryKey: "STYLEIA_API_BASE_URL") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleValue.isEmpty,
            let url = URL(string: bundleValue)
        {
            return url
        }

        #if DEBUG
        // Development fallback: local backend on the same Wi-Fi network.
        return URL(string: "http://192.168.1.169:8080/v1")
        #else
        return nil
        #endif
    }

    /// Public origin that hosts `/privacy` and `/terms` (API base without the `/v1` suffix).
    static var publicBaseURL: URL {
        if let api = backendAPIBaseURL {
            var absolute = api.absoluteString
            while absolute.hasSuffix("/") {
                absolute.removeLast()
            }
            if absolute.hasSuffix("/v1") {
                absolute.removeLast(3)
            }
            if let origin = URL(string: absolute) {
                return origin
            }
        }
        return URL(string: "https://styleia.onrender.com")!
    }

    static var privacyPolicyURL: URL {
        publicBaseURL.appendingPathComponent("privacy")
    }

    static var termsOfUseURL: URL {
        publicBaseURL.appendingPathComponent("terms")
    }

    /// Google OAuth iOS client ID from Info.plist (`GIDClientID`).
    static var googleClientID: String? {
        if let env = ProcessInfo.processInfo.environment["SCENEME_GOOGLE_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") {
                return trimmed
            }
        }

        return nil
    }

    /// URL scheme for Google Sign-In redirect (reversed client ID).
    static var googleURLScheme: String? {
        guard let clientID = googleClientID else { return nil }
        let prefix = "com.googleusercontent.apps."
        if clientID.hasSuffix(".apps.googleusercontent.com") {
            let idPart = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
            return prefix + idPart
        }
        return nil
    }
}
