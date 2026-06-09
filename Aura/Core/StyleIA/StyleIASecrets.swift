import Foundation

// Secrets shim: central place to fetch the backend API base URL.
enum Secrets {
    static var backendAPIBaseURL: URL? {
        if
            let env = ProcessInfo.processInfo.environment["STYLEIA_API_BASE_URL"],
            let url = URL(string: env.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return url
        }

        if
            let bundleValue = Bundle.main.object(forInfoDictionaryKey: "STYLEIA_API_BASE_URL") as? String,
            let url = URL(string: bundleValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return url
        }

        return URL(string: "http://192.168.1.169:8080/v1")
    }
}
