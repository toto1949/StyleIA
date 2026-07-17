import Foundation
import UIKit
import UserNotifications

/// Local notifications when background video (or other long jobs) finish.
@MainActor
enum SceneMeNotifications {
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Posts a local notification when a directed clip finishes.
    /// - Parameter force: when true (user left Result), always deliver even in foreground.
    static func notifyClipReady(sceneName: String, styleTitle: String, force: Bool = false) {
        if !force, UIApplication.shared.applicationState == .active {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your clip is ready"
        content.body = "\(styleTitle) for \(sceneName) just finished — open SceneMe to watch."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sceneme.clip.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
