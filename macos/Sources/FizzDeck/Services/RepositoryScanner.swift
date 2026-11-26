import Foundation
import OSLog

enum ScanCacheStore {
    private struct Payload: Codable {
        let version: Int
        let projects: [String: RepoProject]
    }

    private static let currentVersion = 1

    static func load(
        for roots: [String],
        meta: [String: ProjectMeta],
        cacheFile: URL = AppPaths.scanCacheFile
    ) -> [RepoProject] {
        guard let data = try? Data(contentsOf: cacheFile),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == currentVersion
        else { return [] }

        return roots.compactMap { rawRoot in
            let path = PathTools.normalize(rawRoot)
            guard var project = payload.projects[path] else { return nil }
            let saved = meta[path] ?? ProjectMeta()
            project.starred = saved.starred
            project.color = saved.color
            project.note = saved.note
            project.group = saved.group ?? ProjectGrouping.detected(for: path, kind: project.kind)
            project.port = .noPreview
            return project
        }
        .sorted { ($0.recent ?? .distantPast) > ($1.recent ?? .distantPast) }
    }

    static func save(_ projects: [RepoProject], cacheFile: URL = AppPaths.scanCacheFile) {
        let map = Dictionary(
            projects.map { (PathTools.normalize($0.path), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let payload = Payload(version: currentVersion, projects: map)
        try? FileTools.manager.createDirectory(
            at: cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheFile, options: .atomic)
    }
}

enum RepositoryScanner {
    private static let logger = Logger(subsystem: "com.a003.fizzdeck", category: "scan")

    static func scan(roots: [String], meta: [String: ProjectMeta]) async -> ScanOutput {
        let started = Date()
        let projects = await scan(paths: roots, meta: meta)
        let result = ScanOutput(
            projects: projects,
            roots: roots,
            scannedAt: Date(),
            duration: Date().timeIntervalSince(started)
        )
        logger.info(
            "scan roots=\(roots.count, privacy: .public) projects=\(projects.count, privacy: .public) durationMs=\(Int(result.duration * 1000), privacy: .public)"
        )
        return result
    }

    static func scan(paths: [String], meta: [String: ProjectMeta]) async -> [RepoProject] {
        let fast = await scanFast(paths: paths, meta: meta)
        let withGitAndSessions = await enrichGitAndSessions(projects: fast, meta: meta)
        var resultByPath = Dictionary(
            withGitAndSessions.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for await (path, size, cleanup) in enrichSizesStream(paths: withGitAndSessions.map(\.path)) {
            guard var project = resultByPath[path] else { continue }
            project.size = size
            project.cleanup = cleanup
            project.sizeLoadState = .ready
            resultByPath[path] = project
        }
        return Array(resultByPath.values)
            .sorted { ($0.recent ?? .distantPast) > ($1.recent ?? .distantPast) }
    }

    static func scanFast(
        paths: [String],
        meta: [String: ProjectMeta],
        evidenceIndex: ToolEvidenceIndex? = nil
    ) async -> [RepoProject] {
        let uniquePaths = uniqueNormalized(paths)
        guard !uniquePaths.isEmpty else { return [] }

        let resolvedIndex = await Task.detached(priority: .userInitiated) {
            evidenceIndex ?? ToolEvidenceIndex.build()
        }.value

        return await Task.detached(priority: .userInitiated) {
            uniquePaths.map { path in
                scanFastProject(
                    URL(fileURLWithPath: path),
                    meta: meta,
                    evidenceIndex: resolvedIndex
                )
            }
        }.value
    }

    static func enrichGitAndSessions(
        projects: [RepoProject],
        meta: [String: ProjectMeta]
    ) async -> [RepoProject] {
        guard !projects.isEmpty else { return [] }
        let sessionIndex = await Task.detached(priority: .utility) {
            SessionIndex.build()
        }.value

        var enriched = await runBounded(projects, maxConcurrent: 6) { project in
            await enrichSingleGitAndSession(project, meta: meta, sessionIndex: sessionIndex)
        }
        enriched = await applyPortStates(enriched)
        enriched.sort { ($0.recent ?? .distantPast) > ($1.recent ?? .distantPast) }
        return enriched
    }

    static func enrichSizesStream(
        paths: [String],
        maxConcurrentProjects: Int = 2
    ) -> AsyncStream<(String, SizeInfo, CleanupInfo)> {
        let uniquePaths = uniqueNormalized(paths)
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                guard !uniquePaths.isEmpty else {
                    continuation.finish()
                    return
                }
                await withTaskGroup(of: (String, SizeInfo, CleanupInfo).self) { group in
                    var index = 0
                    let limit = max(1, maxConcurrentProjects)
                    while index < min(limit, uniquePaths.count) {
                        let path = uniquePaths[index]
                        group.addTask {
                            await measureSize(path: path)
                        }
                        index += 1
                    }

                    while let item = await group.next() {
                        if Task.isCancelled { break }
                        continuation.yield(item)
                        if index < uniquePaths.count {
                            let nextPath = uniquePaths[index]
                            group.addTask {
                                await measureSize(path: nextPath)
                            }
                            index += 1
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func measureSize(path: String) async -> (String, SizeInfo, CleanupInfo) {
        let directory = URL(fileURLWithPath: path)
        let (size, dirMap) = await SizeScanner.scanWithDirectoryMap(directory)
        let cleanup = await CleanupScanner.scan(directory, precomputedDirectoryBytes: dirMap)
        return (path, size, cleanup)
    }

    private static func scanFastProject(
        _ directory: URL,
        meta: [String: ProjectMeta],
        evidenceIndex: ToolEvidenceIndex
    ) -> RepoProject {
        let path = PathTools.normalize(directory.path)
        let name = directory.lastPathComponent
        let saved = meta[path] ?? ProjectMeta()
        let entryNames = Set(FileTools.childEntries(of: directory).map(\.lastPathComponent))
        let kind = ProjectKindDetector.detect(directory: directory, entryNames: entryNames)
        let detectedTools = ToolEvidenceDetector.detect(
            directory: directory,
            entryNames: entryNames,
            index: evidenceIndex
        )
        let groupName = saved.group ?? ProjectGrouping.detected(for: path, kind: kind)

        return RepoProject(
            path: path,
            name: name,
            displayName: name,
            group: groupName,
            kind: kind,
            detectedTools: detectedTools,
            recent: FileTools.modificationDate(directory),
            branch: nil,
            lastCommit: nil,
            dirtyCount: 0,
            changes: .zero,
            ahead: 0,
            behind: 0,
            weekly: [:],
            stacks: StackDetector.detect(directory),
            size: .empty,
            cleanup: .empty,
            run: RunDetector.runConfig(directory),
            sessions: .empty,
            intro: IntroExtractor.extract(directory),
            artwork: ProjectArtwork.find(in: directory),
            test: RunDetector.testCommand(directory),
            starred: saved.starred,
            color: saved.color,
            note: saved.note,
            port: .noPreview,
            gitLoadState: .loading,
            sizeLoadState: .loading,
            sessionLoadState: .loading
        )
    }

    private static func enrichSingleGitAndSession(
        _ project: RepoProject,
        meta: [String: ProjectMeta],
        sessionIndex: [SessionRecord]
    ) async -> RepoProject {
        let directory = URL(fileURLWithPath: project.path)
        async let gitTask = GitService.summary(directory)
        async let weeklyTask = GitService.weekly(directory)

        let git = await gitTask
        let weekly = await weeklyTask
        let sessions = SessionIndex.summary(for: directory, in: sessionIndex)
        let saved = meta[project.path] ?? ProjectMeta()

        var tools = project.detectedTools
        for rawTool in sessions.detected {
            if let detected = DetectedTool(rawValue: rawTool), !tools.contains(detected) {
                tools.append(detected)
            }
        }
        tools = DetectedTool.allCases.filter { tools.contains($0) }

        var updated = project
        updated.group = saved.group ?? ProjectGrouping.detected(for: project.path, kind: project.kind)
        updated.detectedTools = tools
        updated.branch = git?.branch
        updated.lastCommit = git?.lastCommit
        updated.dirtyCount = git?.changes.total ?? 0
        updated.changes = git?.changes ?? .zero
        updated.ahead = git?.ahead ?? 0
        updated.behind = git?.behind ?? 0
        updated.weekly = weekly ?? [:]
        updated.sessions = sessions
        updated.recent = latestDate(git?.lastCommit?.date, sessions.lastSessionAt) ?? project.recent
        updated.gitLoadState = .ready
        updated.sessionLoadState = .ready
        return updated
    }

    private static func applyPortStates(_ projects: [RepoProject]) async -> [RepoProject] {
        var portStates: [String: PortState] = [:]
        await withTaskGroup(of: (String, PortState).self) { group in
            for project in projects {
                guard let port = project.run?.port, port > 0 else {
                    portStates[project.path] = .noPreview
                    continue
                }
                group.addTask {
                    (project.path, PortProbe.isOpen(port) ? .running : .stopped)
                }
            }
            for await (path, state) in group {
                portStates[path] = state
            }
        }

        return projects.map { project in
            var project = project
            project.port = portStates[project.path] ?? .noPreview
            return project
        }
    }

    private static func runBounded<Input: Sendable, Output: Sendable>(
        _ items: [Input],
        maxConcurrent: Int,
        operation: @Sendable @escaping (Input) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: Output.self, returning: [Output].self) { group in
            var index = 0
            let limit = max(1, maxConcurrent)
            while index < min(limit, items.count) {
                let item = items[index]
                group.addTask { await operation(item) }
                index += 1
            }
            var outputs: [Output] = []
            while let result = await group.next() {
                outputs.append(result)
                if index < items.count {
                    let nextItem = items[index]
                    group.addTask { await operation(nextItem) }
                    index += 1
                }
            }
            return outputs
        }
    }

    private static func uniqueNormalized(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(PathTools.normalize).filter { seen.insert($0).inserted }
    }

    private static func latestDate(_ values: Date?...) -> Date? {
        values.compactMap { $0 }.max()
    }
}
