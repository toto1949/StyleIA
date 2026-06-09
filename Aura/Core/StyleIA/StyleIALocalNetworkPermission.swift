import Foundation
import Network

enum StyleIALocalNetworkPermission {
    private static var browser: NWBrowser?

    static func warmUpIfNeeded() {
        guard Secrets.backendAPIBaseURL?.isPrivateNetworkURL == true else {
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: "_http._tcp", domain: nil),
            using: parameters
        )
        self.browser = browser

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                stop()
            default:
                break
            }
        }

        browser.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            stop()
        }
    }

    private static func stop() {
        browser?.cancel()
        browser = nil
    }
}

private extension URL {
    var isPrivateNetworkURL: Bool {
        guard let host else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 {
            return true
        }

        if parts[0] == 172 && (16...31).contains(parts[1]) {
            return true
        }

        if parts[0] == 192 && parts[1] == 168 {
            return true
        }

        return parts[0] == 169 && parts[1] == 254
    }
}
