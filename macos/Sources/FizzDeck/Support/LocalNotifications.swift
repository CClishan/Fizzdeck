import UserNotifications

enum LocalNotifications {
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func send(
        title: String,
        body: String,
        projectPath: String? = nil,
        tab: ProjectTab? = nil
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "FizzDeck"
        content.userInfo = [:]
        if let projectPath {
            content.userInfo["projectPath"] = projectPath
        }
        if let tab {
            content.userInfo["tab"] = tab.rawValue
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
