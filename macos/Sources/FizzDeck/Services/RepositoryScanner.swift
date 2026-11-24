import Foundation
import OSLog

enum RepositoryScanner {
    private static let logger = Logger(subsystem: "com.a003.fizzdeck", category: "scan")

    static func scan(roots: [String], meta: [String: ProjectMeta]) async -> ScanOutput {
        let started = Date()
        let sessionIndex = await Task.detached(priority: .utility) {
            SessionIndex.build()
        }.value

        let rootURLs = roots.map { URL(fileURLWithPath: $0) }
        var projects: [RepoProject] = []

        await withTaskGroup(of: RepoProject.self) { group in
            for root in rootURLs {
                group.addTask {
                    await scanProject(root, meta: meta, sessionIndex: sessionIndex)
                }
            }
            for await project in group {
                projects.append(project)
            }
        }

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

        projects = projects.map { project in
            var project = project
            project.port = portStates[project.path] ?? .noPreview
            return project
        }
        projects.sort { ($0.recent ?? .distantPast) > ($1.recent ?? .distantPast) }

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

    private static func scanProject(
        _ directory: URL,
        meta: [String: ProjectMeta],
        sessionIndex: [SessionRecord]
    ) async -> RepoProject {
        let path = directory.path
        let name = directory.lastPathComponent
        let displayName = AppPaths.aliases[path] ?? name
        let groupName = group(for: path)
        let saved = meta[path] ?? ProjectMeta()

        async let sizeTask = SizeScanner.scan(directory)
        async let cleanupTask = CleanupScanner.scan(directory)
        async let gitTask = GitService.summary(directory)
        async let weeklyTask = GitService.weekly(directory)

        let size = await sizeTask
        let cleanup = await cleanupTask
        let git = await gitTask
        let weekly = await weeklyTask
        let sessions = SessionIndex.summary(for: directory, in: sessionIndex)
        let intro = IntroExtractor.extract(directory)
        let stacks = StackDetector.detect(directory)
        let run = RunDetector.runConfig(directory)
        let test = RunDetector.testCommand(directory)

        let recent = latestDate(git?.lastCommit?.date, sessions.lastSessionAt)
        return RepoProject(
            path: path,
            name: name,
            displayName: displayName,
            group: groupName,
            recent: recent,
            branch: git?.branch,
            lastCommit: git?.lastCommit,
            dirtyCount: git?.changes.total ?? 0,
            changes: git?.changes ?? .zero,
            weekly: weekly ?? [:],
            stacks: stacks,
            size: size,
            cleanup: cleanup,
            run: run,
            sessions: sessions,
            intro: intro,
            test: test,
            starred: saved.starred,
            color: saved.color,
            note: saved.note,
            port: .noPreview
        )
    }

    private static func latestDate(_ values: Date?...) -> Date? {
        values.compactMap { $0 }.max()
    }

    private static func group(for path: String) -> String {
        let name = (path as NSString).lastPathComponent.lowercased()
        let value = path.lowercased()
        if value.contains("workspace") || value.contains("cpa-manager") { return "工作区" }
        if name.hasPrefix("tsys") { return "上屏管家" }
        if value.contains("converter-tools")
            || value.contains("alimama-cli")
            || value.contains("cliproxyapi")
            || value.contains("shipany") {
            return "工具库"
        }
        if value.contains("noplan") { return "官网" }
        if value.contains("zoopfizz")
            || value.contains("video-tem")
            || value.contains("pixloading")
            || value.contains("cardfun")
            || value.contains("a2o")
            || value.contains("tapinchina") {
            return "产品站"
        }
        return "其他"
    }
}
