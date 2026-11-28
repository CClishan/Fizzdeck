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
    static let marksFile = stateDir.appendingPathComponent("marks.json")
    static let tmpDir = stateDir.appendingPathComponent("tmp", isDirectory: true)
    static let summariesDir = stateDir.appendingPathComponent("summaries", isDirectory: true)
    static let llmWorkdir = stateDir.appendingPathComponent("llm-workdir", isDirectory: true)
    static let selfUsageFile = stateDir.appendingPathComponent("self-usage.json")
    static let sessionSearchDBFile = stateDir.appendingPathComponent("session-search.sqlite")

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

    static func localFilePath(_ raw: String) -> String? {
        guard !raw.utf8.contains(0) else { return nil }
        if raw.hasPrefix("/") { return raw }
        guard let url = URLComponents(string: raw), url.scheme?.lowercased() == "file",
              url.host?.isEmpty != false || url.host?.lowercased() == "localhost",
              url.user == nil, url.port == nil, url.query == nil, url.fragment == nil,
              !url.percentEncodedPath.contains("%00"),
              let path = url.percentEncodedPath.removingPercentEncoding,
              path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        return path
    }

    static func projectRelativeFile(_ raw: String, in cwd: String) -> String? {
        guard !raw.isEmpty, raw.utf8.count <= 4096, !raw.utf8.contains(0) else { return nil }
        let path: String
        if let local = localFilePath(raw) {
            path = local
        } else {
            guard URLComponents(string: raw)?.scheme == nil else { return nil }
            path = cwd + "/" + raw
        }

        guard let resolved = canonicalWithMissingSuffix(path) else { return nil }
        let root = cwd.hasSuffix("/") ? cwd : cwd + "/"
        guard resolved.hasPrefix(root), resolved.count > root.count else { return nil }
        return String(resolved.dropFirst(root.count))
    }

    static func canonicalWithMissingSuffix(_ path: String) -> String? {
        // Foundation only resolves symlinks if the full path exists. An edit may add or delete a file.
        guard path.hasPrefix("/") else { return nil }
        let original = trimTrailingSlash(path)
        var ancestor = original[...]
        for _ in 0..<32 {
            if FileManager.default.fileExists(atPath: String(ancestor)) {
                let suffix = ancestor == "/" ? original : String(original[ancestor.endIndex...])
                return normalize(canonical(String(ancestor)) + suffix)
            }
            guard ancestor != "/", let slash = ancestor.lastIndex(of: "/") else { return nil }
            ancestor = original[..<(slash == original.startIndex ? original.index(after: slash) : slash)]
        }
        return nil
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
