import Foundation

enum AppPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let stateDir = home.appendingPathComponent(".repodeck", isDirectory: true)
    static let rootsFile = stateDir.appendingPathComponent("roots.json")
    static let metaFile = stateDir.appendingPathComponent("state.json")
    static let logsDir = stateDir.appendingPathComponent("logs", isDirectory: true)

    static let defaultRoots: [URL] = [
        home.appendingPathComponent("pixloading"),
        home.appendingPathComponent("video-tem"),
        home.appendingPathComponent("noplan_officesite"),
        home.appendingPathComponent("Cardfun"),
        home.appendingPathComponent("A2O-LITE-NEON-AI"),
        URL(fileURLWithPath: "/Volumes/back/TapinChina"),
    ]

    static let aliases: [String: String] = [
        home.appendingPathComponent("video-tem").path: "zoopfizz",
        home.appendingPathComponent("A2O-LITE-NEON-AI").path: "NEONLITE.AI",
        home.appendingPathComponent("noplan_officesite").path: "Noplan 官网",
    ]

    static let knownPorts: [String: Int] = [
        "pixloading": 3000,
        "video-tem": 4317,
        "noplan_officesite": 5173,
        "Cardfun": 4321,
        "TapinChina": 5173,
    ]

    static let docCandidates = [
        "README.md",
        "PRODUCT.md",
        "HANDOFF.MD",
        "CLAUDE.md",
        "AGENTS.md",
        "DESIGN.md",
        "ARCHITECTURE.md",
        "lessons.md",
        "task_plan.md",
        "progress.md",
    ]
}

enum PathTools {
    static func normalize(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    static func displayPath(_ path: String) -> String {
        let home = AppPaths.home.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
