import Foundation

struct GitRemote: Sendable, Hashable {
    let raw: String

    init?(raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.raw = value
    }

    var webURL: URL? {
        guard let hostAndPath = hostAndPath else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = hostAndPath.host
        components.port = hostAndPath.port
        var path = hostAndPath.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix(".git") {
            path.removeLast(4)
        }
        guard !path.isEmpty else { return nil }
        components.path = "/" + path
        return components.url
    }

    private var hostAndPath: (host: String, path: String, port: Int?)? {
        if let components = URLComponents(string: raw),
           let scheme = components.scheme?.lowercased() {
            guard scheme != "file" else { return nil }
            guard let host = components.host, !host.isEmpty else { return nil }
            let port = scheme == "http" || scheme == "https" ? components.port : nil
            return (host, components.path, port)
        }

        guard let separator = raw.firstIndex(of: ":") else { return nil }
        let prefix = String(raw[..<separator])
        let path = String(raw[raw.index(after: separator)...])
        guard !prefix.contains("/"), !path.hasPrefix("//") else { return nil }

        let host = prefix.split(separator: "@").last.map(String.init) ?? prefix
        guard host.contains("."), host != "localhost" else { return nil }
        return (host, path, nil)
    }
}

struct GitTrackingCounts: Equatable, Sendable {
    var behind = 0
    var ahead = 0
}

enum GitService {
    private static let fieldSeparator = "\u{1f}"
    private static let recordSeparator = "\u{1e}"

    static func hasGit(_ directory: URL) -> Bool {
        FileTools.exists(directory.appendingPathComponent(".git"))
    }

    static func remote(_ directory: URL) async -> GitRemote? {
        guard hasGit(directory) else { return nil }
        guard let value = await Shell.output(
            "git",
            ["config", "--get", "remote.origin.url"],
            cwd: directory,
            timeout: 10
        ) else { return nil }
        return GitRemote(raw: value)
    }

    static func summary(_ directory: URL) async -> GitSummary? {
        guard hasGit(directory) else { return nil }

        async let branchTask = Shell.output("git", ["rev-parse", "--abbrev-ref", "HEAD"], cwd: directory)
        async let logTask = Shell.output(
            "git",
            ["log", "-1", "--format=%H%n%ad%n%s%n%an", "--date=iso-strict"],
            cwd: directory
        )
        async let statusTask = statusOutput(directory)
        async let trackingTask = Shell.output(
            "git",
            ["rev-list", "--count", "--left-right", "@{upstream}...HEAD"],
            cwd: directory
        )

        let (branch, log, status, tracking) = await (branchTask, logTask, statusTask, trackingTask)
        let lines = statusLines(status)
        let untracked = lines.filter { $0.hasPrefix("??") }.count
        let changes = ChangeStats(tracked: lines.count - untracked, untracked: untracked, total: lines.count)
        let counts = trackingCounts(tracking)

        return GitSummary(
            branch: branch ?? "HEAD",
            lastCommit: parseLastCommit(log),
            changes: changes,
            ahead: counts.ahead,
            behind: counts.behind
        )
    }

    static func weekly(_ directory: URL) async -> [String: Int]? {
        guard hasGit(directory) else { return nil }
        guard let output = await Shell.output(
            "git",
            ["log", "--since=7.days", "--date=short", "--format=%ad"],
            cwd: directory
        ) else { return nil }

        var counts: [String: Int] = [:]
        for day in output.split(separator: "\n").map(String.init) where !day.isEmpty {
            counts[day, default: 0] += 1
        }
        return counts
    }

    static func detail(_ directory: URL) async -> (GitDetail?, [Commit]) {
        guard hasGit(directory) else { return (nil, []) }

        async let branchesTask = Shell.output(
            "git",
            ["branch", "--format=%(refname:short)|%(committerdate:iso-strict)|%(upstream:short)", "--sort=-committerdate"],
            cwd: directory
        )
        async let statusTask = statusOutput(directory)
        async let remoteTask = Shell.output("git", ["remote", "get-url", "origin"], cwd: directory)
        async let aheadTask = Shell.output("git", ["rev-list", "--count", "--left-right", "@{u}...HEAD"], cwd: directory)
        async let stashTask = Shell.output("git", ["stash", "list"], cwd: directory)
        async let tagTask = Shell.output("git", ["describe", "--tags", "--abbrev=0"], cwd: directory)
        async let commitsTask = recentCommits(directory, limit: 12)

        let (branches, status, remote, ahead, stash, tag, commits) =
            await (branchesTask, statusTask, remoteTask, aheadTask, stashTask, tagTask, commitsTask)

        let branchList = parseBranches(branches)
        let files = parseChangedFiles(status)
        let counts = trackingCounts(ahead)

        let summary = GitDetail(
            branches: Array(branchList.prefix(40)),
            files: Array(files.prefix(200)),
            remote: remote,
            ahead: counts.ahead,
            behind: counts.behind,
            stashCount: stash?.split(separator: "\n").filter { !$0.isEmpty }.count ?? 0,
            lastTag: tag,
            changedCount: files.count
        )
        return (summary, commits)
    }

    static func recentCommits(_ directory: URL, limit: Int) async -> [Commit] {
        guard let output = await Shell.output(
            "git",
            [
                "log",
                "-\(limit)",
                "--format=%H\(fieldSeparator)%h\(fieldSeparator)%ad\(fieldSeparator)%an\(fieldSeparator)%s\(fieldSeparator)%D\(recordSeparator)",
                "--date=iso-strict",
            ],
            cwd: directory
        ) else { return [] }

        return output
            .split(separator: Character(recordSeparator))
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { record in
                let fields = record.split(
                    separator: Character(fieldSeparator),
                    maxSplits: 5,
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard fields.count >= 5 else { return nil }
                return Commit(
                    hash: fields[1],
                    date: Format.isoDate(fields[2]),
                    subject: fields[4],
                    author: fields[3]
                )
            }
    }

    private static func statusOutput(_ directory: URL) async -> String? {
        guard let result = await Shell.run(
            "git",
            ["status", "--porcelain=v1", "-uall"],
            cwd: directory,
            timeout: 30
        ), result.succeeded else {
            return nil
        }
        return result.text.trimmingCharacters(in: .newlines)
    }

    private static func parseLastCommit(_ output: String?) -> Commit? {
        guard let output else { return nil }
        let fields = output.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count >= 4 else { return nil }
        return Commit(
            hash: String(fields[0]).prefix(7).description,
            date: Format.isoDate(String(fields[1])),
            subject: String(fields[2]),
            author: String(fields[3])
        )
    }

    static func trackingCounts(_ output: String?) -> GitTrackingCounts {
        guard let output else { return GitTrackingCounts() }
        let parts = output.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard parts.count == 2 else { return GitTrackingCounts() }
        return GitTrackingCounts(behind: parts[0], ahead: parts[1])
    }

    private static func parseBranches(_ output: String?) -> [BranchInfo] {
        guard let output else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return BranchInfo(
                name: name,
                date: parts.count > 1 ? parts[1] : "",
                upstream: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
            )
        }
    }

    private static func parseChangedFiles(_ output: String?) -> [GitFileChange] {
        guard let output else { return [] }
        return output.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = String(line.dropFirst(3))
            return GitFileChange(code: code, path: path, untracked: line.hasPrefix("??"))
        }
    }

    private static func statusLines(_ output: String?) -> [String] {
        output?.split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? []
    }
}
