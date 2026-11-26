import Foundation

struct GitWorktree: Identifiable, Sendable, Hashable {
    let path: String
    let head: String?
    let branch: String?
    let isMain: Bool
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
    let isPrunable: Bool

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum GitWorktreeService {
    static func list(in directory: URL) async -> [GitWorktree] {
        guard let result = await Shell.run(
            "git",
            ["worktree", "list", "--porcelain"],
            cwd: directory,
            timeout: 20
        ), result.succeeded else {
            return []
        }
        return parsePorcelain(result.text)
    }

    static func parsePorcelain(_ output: String) -> [GitWorktree] {
        var records: [[String]] = []
        var current: [String] = []

        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            if rawLine.hasPrefix("worktree ") {
                if !current.isEmpty {
                    records.append(current)
                }
                current = [rawLine]
            } else if !rawLine.isEmpty, !current.isEmpty {
                current.append(rawLine)
            }
        }
        if !current.isEmpty {
            records.append(current)
        }

        return records.enumerated().compactMap { index, lines in
            guard let first = lines.first,
                  first.hasPrefix("worktree ")
            else { return nil }
            let path = String(first.dropFirst("worktree ".count))
            guard !path.isEmpty else { return nil }

            var head: String?
            var branch: String?
            var detached = false
            var bare = false
            var locked = false
            var prunable = false

            for line in lines.dropFirst() {
                if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line.hasPrefix("branch ") {
                    branch = String(line.dropFirst("branch ".count))
                } else if line == "detached" {
                    detached = true
                } else if line == "bare" {
                    bare = true
                } else if line.hasPrefix("locked") {
                    locked = true
                } else if line.hasPrefix("prunable") {
                    prunable = true
                }
            }

            let normalizedPath = PathTools.normalize(path)
            return GitWorktree(
                path: normalizedPath,
                head: head.map { String($0.prefix(12)) },
                branch: branch,
                isMain: index == 0,
                isDetached: detached || (branch == nil && !bare),
                isBare: bare,
                isLocked: locked,
                isPrunable: prunable
            )
        }
    }
}
