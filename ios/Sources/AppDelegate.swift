import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard let id = info["id"] as? String, let sender = info["sender"] as? String, let message = info["message"] as? String else {
            completionHandler(); return
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .benmOpenAlert, object: nil, userInfo: ["id": id, "sender": sender, "message": message])
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let benmOpenAlert = Notification.Name("benm.open-alert")
}
