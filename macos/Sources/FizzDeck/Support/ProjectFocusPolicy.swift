import Foundation

enum ProjectFocusReason: String, Codable, Sendable, Hashable {
    case manual
    case recentActivity
}

struct FocusedProjectEntry: Identifiable, Sendable {
    let project: RepoProject
    let reason: ProjectFocusReason

    var id: String { project.path }
}

struct FocusPartition: Sendable {
    let focused: [FocusedProjectEntry]
    let overflowActiveCount: Int
    let idle: [RepoProject]

    var focusedPaths: Set<String> { Set(focused.map(\.id)) }
}

enum ProjectStatusDot: String, Equatable, Sendable {
    case aiWorking
    case broken
    case unsaved
    case none
}

enum ProjectFocusPolicy {
    static let defaultMaxFocused = 8
    static let defaultAutoActiveDays = 7
    static let defaultIdleDays = 30

    static func partition(
        projects: [RepoProject],
        maxFocused: Int = defaultMaxFocused,
        autoActiveDays: Int = defaultAutoActiveDays,
        idleDays: Int = defaultIdleDays,
        now: Date = Date()
    ) -> FocusPartition {
        let activeCutoff = now.addingTimeInterval(-Double(autoActiveDays) * 24 * 60 * 60)
        let idleCutoff = now.addingTimeInterval(-Double(idleDays) * 24 * 60 * 60)

        let manual = projects
            .filter(\.starred)
            .sorted { latestActivityDate(for: $0) > latestActivityDate(for: $1) }
            .map { FocusedProjectEntry(project: $0, reason: .manual) }

        let manualPaths = Set(manual.map(\.id))

        let autoCandidates = projects
            .filter { !manualPaths.contains($0.path) }
            .filter { project in
                if project.port == .running { return true }
                guard let latest = optionalLatestActivityDate(for: project) else { return false }
                return latest >= activeCutoff
            }
            .sorted { latestActivityDate(for: $0) > latestActivityDate(for: $1) }

        let remainingSlots = max(0, maxFocused - manual.count)
        let selectedAuto = autoCandidates
            .prefix(remainingSlots)
            .map { FocusedProjectEntry(project: $0, reason: .recentActivity) }
        let overflowActiveCount = max(0, autoCandidates.count - selectedAuto.count)

        let focused = manual + selectedAuto
        let focusedPaths = Set(focused.map(\.id))

        let idle = projects.filter { project in
            guard !focusedPaths.contains(project.path) else { return false }
            guard let latest = optionalLatestActivityDate(for: project) else { return false }
            return latest < idleCutoff
        }

        return FocusPartition(
            focused: focused,
            overflowActiveCount: overflowActiveCount,
            idle: idle
        )
    }

    static func statusDot(
        for project: RepoProject,
        testRuns: [String: TestRunState],
        activeAIProjectPaths: Set<String>
    ) -> ProjectStatusDot {
        if activeAIProjectPaths.contains(project.path) {
            return .aiWorking
        }
        if testRuns[project.path]?.status == .failed {
            return .broken
        }
        let latestConversation = project.sessions.recentSessions
            .filter { $0.kind == .conversation }
            .max(by: { $0.modified < $1.modified })
        if latestConversation?.endedWithError == true {
            return .broken
        }
        if project.changes.total > 0 || project.ahead > 0 {
            return .unsaved
        }
        return .none
    }

    private static func optionalLatestActivityDate(for project: RepoProject) -> Date? {
        switch (project.recent, project.sessions.lastSessionAt) {
        case let (.some(lhs), .some(rhs)): max(lhs, rhs)
        case let (.some(lhs), .none): lhs
        case let (.none, .some(rhs)): rhs
        case (.none, .none): nil
        }
    }

    private static func latestActivityDate(for project: RepoProject) -> Date {
        optionalLatestActivityDate(for: project) ?? .distantPast
    }
}
