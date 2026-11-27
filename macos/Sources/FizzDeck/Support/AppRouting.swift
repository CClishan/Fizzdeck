import AppKit
import Foundation

@MainActor
enum AppRouting {
    static let openProjectNotification = Notification.Name("FizzDeck.openProject")

    struct ProjectRequest: Sendable {
        let path: String
        let tab: ProjectTab?
        var showHandoff = false
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
        let tab = (userInfo["tab"] as? String).flatMap(ProjectTab.fromRoutingValue)
        return ProjectRequest(path: path, tab: tab)
    }

    // A URL can only navigate to a root the user already added. The handoff URL opens
    // the preview; only an explicit Copy action writes the system clipboard.
    nonisolated static func projectRequest(from url: URL, managedRoots: [String]) -> ProjectRequest? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "fizzdeck", let action = parts.host,
              ["open", "handoff"].contains(action), parts.path.isEmpty || parts.path == "/",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ $0.name == "path" || ($0.name == "tab" && action == "open") }),
              let path = items.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/"), managedRoots.contains(path) else { return nil }
        let tab = items.first(where: { $0.name == "tab" })
        if let tab, ProjectTab(rawValue: tab.value ?? "") == nil { return nil }
        return ProjectRequest(path: path, tab: tab?.value.flatMap(ProjectTab.init(rawValue:)), showHandoff: action == "handoff")
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
