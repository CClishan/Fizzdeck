import Foundation

struct RepoCommitActivity: Codable, Sendable, Equatable {
    let path: String
    let head: String
    let authorEmails: [String]
    let windowDays: Int
    let timestamps: [Int]
    let updatedAt: Date
}

struct CommitActivitySnapshot: Codable, Sendable, Equatable {
    var byProject: [String: RepoCommitActivity]

    static let empty = CommitActivitySnapshot(byProject: [:])
}

enum CommitActivityService {
    static let defaultWindowDays = 371

    static func loadCache(from url: URL = AppPaths.commitActivityCacheFile) -> CommitActivitySnapshot {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CommitActivitySnapshot.self, from: data)
        else { return .empty }
        return decoded
    }

    static func saveCache(
        _ snapshot: CommitActivitySnapshot,
        to url: URL = AppPaths.commitActivityCacheFile
    ) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func parseAndFilterLog(
        _ output: String,
        matchingEmails: Set<String>,
        fallbackNames: Set<String>
    ) -> [Int] {
        guard !output.isEmpty else { return [] }
        let normalizedEmails = Set(matchingEmails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let normalizedNames = Set(fallbackNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        guard !normalizedEmails.isEmpty || !normalizedNames.isEmpty else { return [] }

        var timestamps: [Int] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let ts = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }

            let email = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let matches: Bool
            if !normalizedEmails.isEmpty {
                matches = normalizedEmails.contains(email)
            } else {
                matches = normalizedNames.contains(name)
            }

            if matches {
                timestamps.append(ts)
            }
        }
        return timestamps.sorted(by: >)
    }

    static func globalAuthorIdentity() async -> (emails: [String], names: [String]) {
        async let emailOut = Shell.output("git", ["config", "--global", "--get-all", "user.email"], timeout: 5)
        async let nameOut = Shell.output("git", ["config", "--global", "--get-all", "user.name"], timeout: 5)
        let (emailsRaw, namesRaw) = await (emailOut, nameOut)
        return (splitIdentityLines(emailsRaw), splitIdentityLines(namesRaw))
    }

    static func refresh(
        projects: [RepoProject],
        cached: CommitActivitySnapshot,
        windowDays: Int = defaultWindowDays,
        maxConcurrent: Int = 4
    ) async -> CommitActivitySnapshot {
        let globalIdentity = await globalAuthorIdentity()
        let gitProjects = projects.filter { GitService.hasGit(URL(fileURLWithPath: $0.path)) }
        guard !gitProjects.isEmpty else { return .empty }

        let limit = max(1, maxConcurrent)
        var result: [String: RepoCommitActivity] = [:]

        await withTaskGroup(of: (String, RepoCommitActivity?).self) { group in
            var iterator = gitProjects.makeIterator()
            for _ in 0..<limit {
                guard let project = iterator.next() else { break }
                let existing = cached.byProject[project.path]
                group.addTask {
                    let activity = await fetchRepoActivity(
                        path: project.path,
                        cached: existing,
                        globalIdentity: globalIdentity,
                        windowDays: windowDays
                    )
                    return (project.path, activity)
                }
            }

            while let (path, activity) = await group.next() {
                if let activity {
                    result[path] = activity
                }
                if let nextProject = iterator.next(), !Task.isCancelled {
                    let existing = cached.byProject[nextProject.path]
                    group.addTask {
                        let activity = await fetchRepoActivity(
                            path: nextProject.path,
                            cached: existing,
                            globalIdentity: globalIdentity,
                            windowDays: windowDays
                        )
                        return (nextProject.path, activity)
                    }
                }
            }
        }

        return CommitActivitySnapshot(byProject: result)
    }

    private static func fetchRepoActivity(
        path: String,
        cached: RepoCommitActivity?,
        globalIdentity: (emails: [String], names: [String]),
        windowDays: Int
    ) async -> RepoCommitActivity? {
        guard !Task.isCancelled else { return cached }
        let directory = URL(fileURLWithPath: path)

        async let headOut = Shell.output("git", ["rev-parse", "HEAD"], cwd: directory, timeout: 5)
        async let localEmailOut = Shell.output("git", ["config", "--local", "--get-all", "user.email"], cwd: directory, timeout: 5)
        async let localNameOut = Shell.output("git", ["config", "--local", "--get-all", "user.name"], cwd: directory, timeout: 5)

        let (headRaw, localEmailsRaw, localNamesRaw) = await (headOut, localEmailOut, localNameOut)
        guard let head = headRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty else {
            return nil
        }

        let emails = mergeUnique(splitIdentityLines(localEmailsRaw) + globalIdentity.emails)
        let names = mergeUnique(splitIdentityLines(localNamesRaw) + globalIdentity.names)

        if let cached,
           cached.head == head,
           cached.windowDays >= windowDays,
           cached.authorEmails == emails {
            return cached
        }

        guard let logOutput = await Shell.output(
            "git",
            ["log", "--since=\(windowDays).days", "--format=%ct%x1f%ae%x1f%an"],
            cwd: directory,
            timeout: 15
        ) else {
            return cached
        }

        let timestamps = parseAndFilterLog(
            logOutput,
            matchingEmails: Set(emails),
            fallbackNames: Set(names)
        )
        return RepoCommitActivity(
            path: path,
            head: head,
            authorEmails: emails,
            windowDays: windowDays,
            timestamps: timestamps,
            updatedAt: Date()
        )
    }

    private static func splitIdentityLines(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func mergeUnique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in items where seen.insert(item).inserted {
            ordered.append(item)
        }
        return ordered.sorted()
    }
}
