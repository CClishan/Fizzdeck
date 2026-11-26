import Foundation

enum AppPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let stateDir = home.appendingPathComponent(".repodeck", isDirectory: true)
    static let rootsFile = stateDir.appendingPathComponent("roots.json")
    static let metaFile = stateDir.appendingPathComponent("state.json")
    static let scanCacheFile = stateDir.appendingPathComponent("scan-cache.json")
    static let sessionCacheFile = stateDir.appendingPathComponent("session-cache.json")
    static let commitActivityCacheFile = stateDir.appendingPathComponent("commit-activity.json")
    static let onboardingFile = stateDir.appendingPathComponent("onboarding.json")
    static let logsDir = stateDir.appendingPathComponent("logs", isDirectory: true)
    static let launchersDir = stateDir.appendingPathComponent("launchers", isDirectory: true)
    static let coversDir = stateDir.appendingPathComponent("covers", isDirectory: true)

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
        trimTrailingSlash(URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    static func canonical(_ path: String) -> String {
        trimTrailingSlash(
            URL(fileURLWithPath: path)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
        )
    }

    static func displayPath(_ path: String) -> String {
        let home = AppPaths.home.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var value = path
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
