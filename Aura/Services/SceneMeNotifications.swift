import Foundation
import UIKit
import UserNotifications

/// Local notifications when background video (or other long jobs) finish.
@MainActor
enum SceneMeNotifications {
    static let clipReadyCategory = "SCENEME_CLIP_READY"

    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Posts a real system notification when a directed clip finishes.
    /// Always delivers (including while the app is active) so users who left
    /// Result for Profile still get a banner — not only the in-app toast title.
    static func notifyClipReady(
        sceneName: String,
        styleTitle: String,
        resultId: String? = nil,
        force: Bool = true
    ) {
        _ = force

        let content = UNMutableNotificationContent()
        content.title = "\(styleTitle) clip is ready"
        content.body = "\(sceneName) finished rendering — tap to watch in SceneMe."
        content.sound = .default
        content.badge = NSNumber(value: 1)
        content.categoryIdentifier = clipReadyCategory
        var userInfo: [String: Any] = [
            "type": "clip_ready",
            "sceneName": sceneName,
            "styleTitle": styleTitle
        ]
        if let resultId {
            userInfo["resultId"] = resultId
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "sceneme.clip.\(resultId ?? UUID().uuidString).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                #if DEBUG
                print("[SceneMeNotifications] Failed to schedule clip-ready: \(error)")
                #endif
            }
        }
    }

    static func clearBadge() {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}
