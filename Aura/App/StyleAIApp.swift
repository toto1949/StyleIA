import SwiftUI

@main
struct SceneMeApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            SceneMeRootView()
                .tint(SceneMeTheme.gold)
                .task {
                    SocialAuthService.shared.configureGoogleIfNeeded()
                }
                .onOpenURL { url in
                    _ = SocialAuthService.shared.handleGoogleURL(url)
                }
        }
    }
}
