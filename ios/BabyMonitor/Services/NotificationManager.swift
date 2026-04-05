import UserNotifications

enum NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    static func postDisconnectNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Baby Monitor Disconnected"
        content.body = "\(Config.serverName) is no longer reachable"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "disconnect-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
