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
        TerminalLauncher.openDirectory(path)
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

    static func copy(
        _ value: String,
        feedback: String? = "已复制到剪贴板",
        microViz: ToastMicroViz? = nil
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        if let feedback {
            Task { @MainActor in
                ToastCenter.shared.show(
                    feedback,
                    symbol: "doc.on.doc.fill",
                    tint: FizzTheme.accent,
                    microViz: microViz
                )
            }
        }
    }

    @MainActor
    static func promptForGroupName(defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = "移动到分组"
        alert.informativeText = "输入已有分组名，或新建一个分组。"
        alert.addButton(withTitle: "移动")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = "分组名称"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return String(value.prefix(24))
    }
}

enum ProjectEditor: String, CaseIterable, Identifiable, Sendable {
    case cursor
    case trae
    case windsurf
    case vscode
    case zed
    case xcode
    case antigravity
    case intellij
    case webstorm
    case pycharm
    case goland
    case rustrover
    case clion
    case phpstorm
    case rubymine
    case datagrip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: "Cursor"
        case .trae: "Trae"
        case .windsurf: "Windsurf"
        case .vscode: "VS Code"
        case .zed: "Zed"
        case .xcode: "Xcode"
        case .antigravity: "Antigravity"
        case .intellij: "IntelliJ IDEA"
        case .webstorm: "WebStorm"
        case .pycharm: "PyCharm"
        case .goland: "GoLand"
        case .rustrover: "RustRover"
        case .clion: "CLion"
        case .phpstorm: "PhpStorm"
        case .rubymine: "RubyMine"
        case .datagrip: "DataGrip"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .cursor: ["com.todesktop.230313mzl4w4u92"]
        case .trae: ["com.trae.app"]
        case .windsurf: ["com.exafunction.windsurf"]
        case .vscode: ["com.microsoft.VSCode"]
        case .zed: ["dev.zed.Zed"]
        case .xcode: ["com.apple.dt.Xcode"]
        case .antigravity: ["com.google.antigravity-ide"]
        case .intellij: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        case .webstorm: ["com.jetbrains.WebStorm"]
        case .pycharm: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        case .goland: ["com.jetbrains.goland"]
        case .rustrover: ["com.jetbrains.rustrover"]
        case .clion: ["com.jetbrains.CLion"]
        case .phpstorm: ["com.jetbrains.PhpStorm"]
        case .rubymine: ["com.jetbrains.RubyMine"]
        case .datagrip: ["com.jetbrains.DataGrip"]
        }
    }

    var fallbackApplicationPaths: [String] {
        switch self {
        case .trae: ["/Applications/Trae.app"]
        case .windsurf: ["/Applications/Windsurf.app"]
        case .xcode: ["/Applications/Xcode.app"]
        case .antigravity: ["/Applications/Antigravity IDE.app"]
        case .intellij: ["/Applications/IntelliJ IDEA.app", "/Applications/IntelliJ IDEA CE.app"]
        case .webstorm: ["/Applications/WebStorm.app"]
        case .pycharm: ["/Applications/PyCharm.app", "/Applications/PyCharm CE.app"]
        case .goland: ["/Applications/GoLand.app"]
        case .rustrover: ["/Applications/RustRover.app"]
        case .clion: ["/Applications/CLion.app"]
        case .phpstorm: ["/Applications/PhpStorm.app"]
        case .rubymine: ["/Applications/RubyMine.app"]
        case .datagrip: ["/Applications/DataGrip.app"]
        case .cursor, .vscode, .zed: []
        }
    }

    var applicationURL: URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }
        return fallbackApplicationPaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileTools.isDirectory($0) }
    }

    func target(for path: String) -> URL? {
        let directory = URL(fileURLWithPath: path)
        guard self == .xcode else { return directory }
        return Self.xcodeTarget(in: directory)
    }

    static func available(for path: String) -> [ProjectEditor] {
        allCases.filter { editor in
            editor.applicationURL != nil && editor.target(for: path) != nil
        }
    }

    static func xcodeTarget(in directory: URL, maxDepth: Int = 3) -> URL? {
        let topLevel = entries(in: directory)
        if let target = topLevelTarget(in: topLevel, includePackage: true) {
            return target
        }
        guard maxDepth > 0 else { return nil }

        var frontier = searchableDirectories(in: topLevel)
        var packageFallback: URL?
        for _ in 1...maxDepth {
            guard !frontier.isEmpty else { return packageFallback }
            var next: [URL] = []
            for child in frontier {
                let childEntries = entries(in: child)
                if let target = topLevelTarget(in: childEntries, includePackage: false) {
                    return target
                }
                if packageFallback == nil,
                   let package = childEntries.first(where: { $0.lastPathComponent == "Package.swift" }) {
                    packageFallback = package
                }
                next.append(contentsOf: searchableDirectories(in: childEntries))
            }
            frontier = next
        }
        return packageFallback
    }

    private static func topLevelTarget(in entries: [URL], includePackage: Bool) -> URL? {
        let priority = [".xcworkspace", ".xcodeproj"]
        for suffix in priority {
            if let value = entries
                .filter({ $0.pathExtension == String(suffix.dropFirst()) })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first {
                return value
            }
        }
        return includePackage ? entries.first { $0.lastPathComponent == "Package.swift" } : nil
    }

    private static func entries(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static let skippedDirectoryNames: Set<String> = [
        "build",
        "DerivedData",
        "dist",
        "node_modules",
        "Pods",
        "vendor",
    ]

    private static func searchableDirectories(in entries: [URL]) -> [URL] {
        entries.filter { entry in
            guard !skippedDirectoryNames.contains(entry.lastPathComponent) else { return false }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }
}
