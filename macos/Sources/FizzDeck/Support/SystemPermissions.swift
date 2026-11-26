import AppKit
import Foundation
import ServiceManagement
import UserNotifications

enum NotificationPermission: Equatable {
    case allowed
    case denied
    case notDetermined
    case unknown
}

enum LoginItemState: Equatable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable
}

enum SystemPermissionService {
    static func notificationPermission() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    static func requestNotifications() async -> NotificationPermission {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )
        return await notificationPermission()
    }

    static var hasFullDiskAccess: Bool? {
        let paths = [
            NSHomeDirectory() + "/Library/Safari/History.db",
            NSHomeDirectory() + "/Library/Mail/V10/MailData/Envelope Index",
        ]
        let existing = paths.filter {
            FileManager.default.fileExists(atPath: $0)
        }
        guard !existing.isEmpty else { return nil }

        return existing.contains { path in
            guard let handle = FileHandle(forReadingAtPath: path) else {
                return false
            }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 1))?.isEmpty == false
        }
    }

    static func openNotificationSettings() {
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    static func openFilesAndFoldersSettings() {
        open(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders"
        )
    }

    static func openAutomationSettings() {
        open(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
        )
    }

    static func openFullDiskAccessSettings() {
        open(
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        )
    }

    private static func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum LoginItemService {
    static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
