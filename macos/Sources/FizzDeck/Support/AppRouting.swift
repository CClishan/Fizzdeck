import AppKit
import Foundation

@MainActor
enum AppRouting {
    static let openProjectNotification = Notification.Name("FizzDeck.openProject")

    struct ProjectRequest: Sendable {
        let path: String
        let tab: ProjectTab?
    }

    private static var pendingProject: ProjectRequest?

    static func openProject(path: String, tab: ProjectTab?) {
        pendingProject = ProjectRequest(path: path, tab: tab)
        presentMainWindow()
        NotificationCenter.default.post(name: openProjectNotification, object: nil)
    }

    static func consumePendingProject() -> ProjectRequest? {
        defer { pendingProject = nil }
        return pendingProject
    }

    nonisolated static func projectRequest(from userInfo: [AnyHashable: Any]) -> ProjectRequest? {
        guard let path = userInfo["projectPath"] as? String, !path.isEmpty else {
            return nil
        }
        let tab = (userInfo["tab"] as? String).flatMap(ProjectTab.init(rawValue:))
        return ProjectRequest(path: path, tab: tab)
    }

    static func presentMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.title == "FizzDeck"
        }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        )
    }
}
