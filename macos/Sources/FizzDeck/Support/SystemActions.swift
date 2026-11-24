import AppKit
import Foundation

enum SystemActions {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openTerminal(_ path: String) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let directory = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminal,
            configuration: configuration
        )
    }

    static func open(_ path: String, in editor: ProjectEditor) {
        guard let target = editor.target(for: path),
              let application = editor.applicationURL
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [target],
            withApplicationAt: application,
            configuration: configuration
        )
    }

    static func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

enum ProjectEditor: String, CaseIterable, Identifiable, Sendable {
    case cursor
    case vscode
    case zed
    case xcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        case .zed: "Zed"
        case .xcode: "Xcode"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .vscode: "com.microsoft.VSCode"
        case .zed: "dev.zed.Zed"
        case .xcode: "com.apple.dt.Xcode"
        }
    }

    var fallbackApplicationPath: String? {
        self == .xcode ? "/Applications/Xcode.app" : nil
    }

    var applicationURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        guard let fallbackApplicationPath else { return nil }
        return URL(fileURLWithPath: fallbackApplicationPath)
    }

    func target(for path: String) -> URL? {
        let directory = URL(fileURLWithPath: path)
        guard self == .xcode else { return directory }
        return xcodeTarget(in: directory)
    }

    static func available(for path: String) -> [ProjectEditor] {
        allCases.filter { editor in
            editor.applicationURL != nil && editor.target(for: path) != nil
        }
    }

    private func xcodeTarget(in directory: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let priority = [".xcworkspace", ".xcodeproj"]
        for suffix in priority {
            if let value = entries
                .filter({ $0.pathExtension == String(suffix.dropFirst()) })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first {
                return value
            }
        }
        return entries.first { $0.lastPathComponent == "Package.swift" }
    }
}
