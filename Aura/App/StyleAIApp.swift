import SwiftUI

@main
struct StyleAIApp: App {
    var body: some Scene {
        WindowGroup {
            StyleIATabRootView()
                .tint(StyleIATheme.moss)
                .task {
                    StyleIALocalNetworkPermission.warmUpIfNeeded()
                }
        }
    }
}
