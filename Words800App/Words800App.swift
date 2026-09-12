import SwiftUI
import UserNotifications

@main
struct Words800App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dataManager = DataManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let ids = response.notification.request.content.userInfo["wordIDs"] as? [String] ?? []
        DispatchQueue.main.async {
            UserDefaults.standard.set(ids, forKey: "pendingNotificationWords")
            NotificationCenter.default.post(name: .reviewNotification, object: nil, userInfo: ["wordIDs": ids])
        }
        completionHandler()
    }
}
