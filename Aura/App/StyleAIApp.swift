import SwiftUI

@main
struct SceneMeApp: App {
    @UIApplicationDelegateAdaptor(SceneMeAppDelegate.self) private var appDelegate

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
