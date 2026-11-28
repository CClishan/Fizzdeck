import Foundation

enum ProjectKind: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case web
    case macApp
    case miniProgram
    case flutter
    case game
    case cli
    case other

    var id: String { rawValue }

    // Built-in group IDs were persisted as Chinese titles before Build 26.
    var groupKey: String {
        switch self {
        case .web: "网页"
        case .macApp: "Mac 应用"
        case .miniProgram: "小程序"
        case .flutter: "Flutter"
        case .game: "游戏"
        case .cli: "命令行脚本"
        case .other: "其他"
        }
    }

    var title: String {
        guard FizzL10n.isEnglish else { return groupKey }
        switch self {
        case .web: return "Web"
        case .macApp: return "Mac Apps"
        case .miniProgram: return "Mini Apps"
        case .flutter: return "Flutter"
        case .game: return "Games"
        case .cli: return "CLI Tools"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .web: "globe"
        case .macApp: "macwindow"
        case .miniProgram: "app.badge"
        case .flutter: "bird"
        case .game: "gamecontroller"
        case .cli: "terminal"
        case .other: "folder"
        }
    }

}

enum ProjectKindDetector {
    static func detect(directory: URL, entryNames: Set<String>? = nil) -> ProjectKind {
        let names = entryNames ?? Set(FileTools.childEntries(of: directory).map(\.lastPathComponent))
        let lowercased = Set(names.map { $0.lowercased() })

        func has(_ name: String) -> Bool {
            names.contains(name) || lowercased.contains(name.lowercased())
        }

        // 1. Game engines
        if names.contains(where: { $0.lowercased().hasSuffix(".uproject") })
            || has("project.godot")
            || FileTools.exists(directory.appendingPathComponent("ProjectSettings/ProjectVersion.txt")) {
            return .game
        }

        // 2. Flutter (must include flutter: in pubspec.yaml so pure Dart CLI is not misclassified)
        if has("pubspec.yaml") {
            let pubspec = FileTools.readText(directory.appendingPathComponent("pubspec.yaml"), maxBytes: 32 * 1024)
            if pubspec.range(of: #"(?m)^flutter\s*:"#, options: .regularExpression) != nil
                || pubspec.contains("sdk: flutter") {
                return .flutter
            }
        }

        // 3. Mini programs (WeChat / uni-app)
        if has("project.config.json") {
            return .miniProgram
        }
        if has("app.json") && (has("pages") || has("sitemap.json")) {
            return .miniProgram
        }
        if has("manifest.json") && (has("pages.json") || has("pages")) {
            return .miniProgram
        }

        // 4. Mac / Apple apps
        if names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            return .macApp
        }
        let packageSwiftText = has("Package.swift")
            ? FileTools.readText(directory.appendingPathComponent("Package.swift"), maxBytes: 32 * 1024)
            : ""
        if !packageSwiftText.isEmpty,
           packageSwiftText.contains("SwiftUI")
            || packageSwiftText.contains("AppKit")
            || packageSwiftText.contains(".macOS(") && !packageSwiftText.contains(".executableTarget") {
            return .macApp
        }

        // 5. Web apps
        let webConfigMarkers = [
            "next.config.js", "next.config.mjs", "next.config.ts",
            "vite.config.js", "vite.config.mjs", "vite.config.ts",
            "astro.config.mjs", "astro.config.ts", "astro.config.js",
            "svelte.config.js", "svelte.config.ts",
            "nuxt.config.ts", "nuxt.config.js",
        ]
        if webConfigMarkers.contains(where: { has($0) }) {
            return .web
        }

        let packageJSON = has("package.json")
            ? FileTools.json(directory.appendingPathComponent("package.json"))
            : nil
        if let packageJSON {
            var deps = Set<String>()
            for key in ["dependencies", "devDependencies"] {
                if let map = packageJSON[key] as? [String: Any] {
                    deps.formUnion(map.keys)
                }
            }
            let webDeps: Set<String> = [
                "next", "vite", "react", "react-dom", "vue", "svelte",
                "astro", "nuxt", "@tanstack/react-start",
            ]
            if !deps.isDisjoint(with: webDeps) || has("index.html") {
                return .web
            }
        }

        // 6. CLI / script tools
        if let packageJSON, packageJSON["bin"] != nil {
            return .cli
        }
        if has("pyproject.toml") {
            let pyproject = FileTools.readText(directory.appendingPathComponent("pyproject.toml"), maxBytes: 32 * 1024)
            if pyproject.contains("[project.scripts]") || pyproject.contains("[tool.poetry.scripts]") {
                return .cli
            }
        }
        if has("go.mod") && (has("cmd") || has("main.go")) {
            return .cli
        }
        if has("Cargo.toml") && FileTools.exists(directory.appendingPathComponent("src/main.rs")) {
            return .cli
        }
        if !packageSwiftText.isEmpty && packageSwiftText.contains(".executableTarget") {
            return .cli
        }
        if has("bin"), hasExecutableScript(in: directory.appendingPathComponent("bin")) {
            return .cli
        }

        return .other
    }

    private static func hasExecutableScript(in binDirectory: URL) -> Bool {
        guard FileTools.isDirectory(binDirectory) else { return false }
        let entries = FileTools.childEntries(of: binDirectory)
        for entry in entries.prefix(12) {
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
            guard values?.isRegularFile == true else { continue }
            if values?.isExecutable == true { return true }
            let prefix = FileTools.head(entry, bytes: 64)
            if prefix.hasPrefix("#!") { return true }
        }
        return false
    }
}
