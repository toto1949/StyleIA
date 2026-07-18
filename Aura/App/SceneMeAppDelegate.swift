import UIKit
import UserNotifications

/// Delivers local notification banners even while SceneMe is in the foreground,
/// and routes taps back into the video player.
final class SceneMeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show a real banner/sound even if the user is browsing Profile mid-generation.
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(
            name: .sceneMeOpenReadyClip,
            object: nil,
            userInfo: userInfo as? [AnyHashable: Any]
        )
        completionHandler()
    }
}

extension Notification.Name {
    static let sceneMeOpenReadyClip = Notification.Name("sceneMeOpenReadyClip")
}
