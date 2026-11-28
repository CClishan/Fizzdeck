import Foundation

enum HomeViewMode: String, CaseIterable, Identifiable, Sendable {
    case cards
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: FizzL10n.text("卡片墙", "Cards")
        case .list: FizzL10n.text("表格", "Table")
        }
    }

    var symbol: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

enum HomeSort: String, CaseIterable, Identifiable, Sendable {
    case recent
    case name
    case size
    case dirty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: FizzL10n.text("最近活动", "Recent activity")
        case .name: FizzL10n.text("名称", "Name")
        case .size: FizzL10n.text("体积", "Size")
        case .dirty: FizzL10n.text("改动数", "Change count")
        }
    }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .name: "textformat.abc"
        case .size: "internaldrive"
        case .dirty: "exclamationmark.circle"
        }
    }

    func sort(_ projects: [RepoProject]) -> [RepoProject] {
        projects.sorted { left, right in
            switch self {
            case .recent:
                return (left.recent ?? .distantPast) > (right.recent ?? .distantPast)
            case .name:
                return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            case .size:
                return left.size.totalBytes > right.size.totalBytes
            case .dirty:
                if left.dirtyCount != right.dirtyCount {
                    return left.dirtyCount > right.dirtyCount
                }
                return (left.recent ?? .distantPast) > (right.recent ?? .distantPast)
            }
        }
    }
}

struct HomeFacets: Equatable, Sendable {
    var group: String? = nil
    var color: TagColor? = nil
    var tool: String? = nil

    var isEmpty: Bool {
        group == nil && color == nil && tool == nil
    }

    var hasAny: Bool {
        !isEmpty
    }

    mutating func clear() {
        group = nil
        color = nil
        tool = nil
    }
}

struct HomeSummaryStats: Equatable, Sendable {
    let projectCount: Int
    let runningCount: Int
    let totalBytes: Int64
    let cleanupBytes: Int64
    let cleanupItemCount: Int
}

enum LibraryBatchResult: Equatable, Sendable {
    case cleanup(copied: Int, skipped: Int)
    case starred(Int, Bool)
    case grouped(Int, String?)
    case fetched(succeeded: Int, failed: Int)
    case rescanned(Int, missing: Int)

    var message: String {
        switch self {
        case .cleanup(0, _):
            return FizzL10n.text("所选项目没有可清理项", "Nothing to clean in the selected projects")
        case let .cleanup(count, 0):
            return FizzL10n.text("已复制 \(count) 个项目的清理命令", "Copied cleanup commands for \(SessionSummaryText.englishCount(count, "project"))")
        case let .cleanup(count, skipped):
            return FizzL10n.text("已复制 \(count) 个；\(skipped) 个没有可清理项", "Copied commands for \(count); \(skipped) had nothing to clean")
        case let .starred(count, starred):
            return starred
                ? FizzL10n.text("已为 \(count) 个项目设为星标", "Starred \(SessionSummaryText.englishCount(count, "project"))")
                : FizzL10n.text("已取消 \(count) 个项目的星标", "Unstarred \(SessionSummaryText.englishCount(count, "project"))")
        case let .grouped(count, group?):
            let title = ProjectGrouping.title(for: group)
            return FizzL10n.text("已将 \(count) 个项目移至「\(title)」", "Moved \(SessionSummaryText.englishCount(count, "project")) to “\(title)”")
        case let .grouped(count, nil):
            return FizzL10n.text("已将 \(count) 个项目恢复自动分组", "Restored automatic grouping for \(SessionSummaryText.englishCount(count, "project"))")
        case .fetched(0, 0):
            return FizzL10n.text("所选项目均非 Git 仓库", "None of the selected projects are Git repositories.")
        case let .fetched(count, 0):
            return FizzL10n.text("已 Fetch \(count) 个仓库", "Fetched \(count) \(count == 1 ? "repository" : "repositories")")
        case let .fetched(count, failed):
            return FizzL10n.text("Fetch 完成：\(count) 个成功，\(failed) 个失败", "Fetch complete: \(count) succeeded, \(failed) failed")
        case .rescanned(0, _):
            return FizzL10n.text("所选目录都不存在", "None of the selected folders exist.")
        case let .rescanned(count, 0):
            return FizzL10n.text("已重新扫描 \(count) 个项目", "Rescanned \(SessionSummaryText.englishCount(count, "project"))")
        case let .rescanned(count, missing):
            return FizzL10n.text("已重新扫描 \(count) 个；\(missing) 个目录不存在", "Rescanned \(count); \(SessionSummaryText.englishCount(missing, "folder")) missing")
        }
    }
}

struct BatchCleanupCommands {
    let script: String?
    let result: LibraryBatchResult
    var feedback: String { result.message }
}

struct WorkbenchSearchHit: Identifiable {
    let result: SessionSearchResult
    private let terms: [String]
    var id: String { result.id }
    var title: String { result.displayTitle }

    var snippet: String? {
        // An AI excerpt is already redacted source text. Regenerate only the index's labels.
        guard let cached = result.matchedSnippet, !cached.hasPrefix("✦ ") else { return result.matchedSnippet }
        return SessionSearchIndex.makeSnippet(queryTerms: terms, primaryIntent: result.primaryIntent,
                                              lastUser: result.lastUser ?? "", aiSummary: "",
                                              lastError: result.lastError ?? "", touchedFiles: result.touchedFilesText) ?? cached
    }

    static func make(_ results: [SessionSearchResult], query: String) -> [Self] {
        let terms = SessionSearchIndex.tokenizeQuery(query)
        return results.map { Self(result: $0, terms: terms) }
    }
}

enum HomeDashboardModel {
    static func matchingProjects(from projects: [RepoProject], filter: HomeFilter) -> [RepoProject] {
        projects.filter(filter.matches)
    }

    static func visibleProjects(
        from matching: [RepoProject],
        facets: HomeFacets,
        sort: HomeSort
    ) -> [RepoProject] {
        sort.sort(
            matching.filter { project in
                if let group = facets.group, project.group != group { return false }
                if let color = facets.color, project.color != color { return false }
                if let tool = facets.tool, !project.allTools.contains(tool) { return false }
                return true
            }
        )
    }

    static func availableGroups(in matching: [RepoProject]) -> [String] {
        ProjectGrouping.ordered(matching.map(\.group))
    }

    static func availableTools(in matching: [RepoProject]) -> [String] {
        let detected = Set(matching.flatMap(\.allTools))
        let preferred = DetectedTool.allCases.map(\.rawValue).filter(detected.contains)
        return preferred + detected.subtracting(preferred).sorted()
    }

    struct FrameworkChoice: Identifiable {
        let id: String
        let title: String
    }

    static func availableFrameworks(in projects: [RepoProject]) -> [FrameworkChoice] {
        var seen = Set<String>()
        return projects.compactMap { project -> FrameworkChoice? in
            guard let stack = project.stacks.first, let key = stack.items.first,
                  seen.insert(key).inserted, let title = stack.displayItems.first else { return nil }
            return FrameworkChoice(id: key, title: title)
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func libraryProjects(
        from projects: [RepoProject],
        query: LibraryQuery,
        sort: HomeSort,
        commitActivity: CommitActivitySnapshot,
        calendar: Calendar = .current
    ) -> [RepoProject] {
        let committedOnDay: Set<String>? = query.commitDayKey.map {
            DashboardMetrics.projectPathsCommitted(
                onDayKey: $0,
                snapshot: commitActivity,
                projects: projects,
                calendar: calendar
            )
        }
        let needle = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = projects.filter { project in
            if query.starredOnly && !project.starred { return false }
            if query.dirtyOnly && project.dirtyCount == 0 { return false }
            if query.runningOnly && project.port != .running { return false }
            if query.hasSessionsOnly && project.sessions.sessionCount == 0 { return false }
            if query.unpushedOnly && project.ahead == 0 { return false }
            if let group = query.group, project.group != group { return false }
            if let color = query.color, project.color != color { return false }
            if let tool = query.tool, !project.allTools.contains(tool) { return false }
            if let framework = query.framework {
                let matchesFramework = project.stacks.contains { $0.items.contains(framework) }
                if !matchesFramework { return false }
            }
            if let committedOnDay, !committedOnDay.contains(project.path) { return false }
            if !needle.isEmpty {
                let matchesSearch = project.displayName.lowercased().contains(needle)
                    || project.name.lowercased().contains(needle)
                    || project.path.lowercased().contains(needle)
                    || (project.branch?.lowercased().contains(needle) ?? false)
                    || project.kind.title.lowercased().contains(needle)
                    || project.stacks.contains(where: { group in
                        group.items.contains(where: { $0.lowercased().contains(needle) })
                            || group.displayItems.contains(where: { $0.lowercased().contains(needle) })
                    })
                if !matchesSearch { return false }
            }
            return true
        }

        return sort.sort(filtered)
    }

    static func groupCount(
        _ group: String,
        in matching: [RepoProject],
        facets: HomeFacets
    ) -> Int {
        matching.filter { project in
            guard project.group == group else { return false }
            if let color = facets.color, project.color != color { return false }
            if let tool = facets.tool, !project.allTools.contains(tool) { return false }
            return true
        }.count
    }

    static func colorCount(
        _ color: TagColor,
        in matching: [RepoProject],
        facets: HomeFacets
    ) -> Int {
        matching.filter { project in
            guard project.color == color else { return false }
            if let group = facets.group, project.group != group { return false }
            if let tool = facets.tool, !project.allTools.contains(tool) { return false }
            return true
        }.count
    }

    static func toolCount(
        _ tool: String,
        in matching: [RepoProject],
        facets: HomeFacets
    ) -> Int {
        matching.filter { project in
            guard project.allTools.contains(tool) else { return false }
            if let group = facets.group, project.group != group { return false }
            if let color = facets.color, project.color != color { return false }
            return true
        }.count
    }

    static func summaryStats(for projects: [RepoProject]) -> HomeSummaryStats {
        HomeSummaryStats(
            projectCount: projects.count,
            runningCount: projects.filter { $0.port == .running }.count,
            totalBytes: projects.reduce(0) { $0 + $1.size.totalBytes },
            cleanupBytes: projects.reduce(0) { $0 + $1.cleanup.reusableBytes },
            cleanupItemCount: projects.reduce(0) { $0 + $1.cleanup.items.count }
        )
    }

    static func headerDetail(
        visibleCount: Int,
        matchingCount: Int,
        hasFacets: Bool,
        filter: HomeFilter,
        runningCount: Int,
        isScanning: Bool,
        pendingSizeCount: Int,
        relativeScannedAt: String?
    ) -> String {
        var parts: [String] = []
        if hasFacets {
            parts.append(FizzL10n.text("显示 \(visibleCount) / \(matchingCount) 个项目", "Showing \(visibleCount) of \(matchingCount)"))
        } else {
            parts.append(FizzL10n.text("\(visibleCount) 个项目", SessionSummaryText.englishCount(visibleCount, "project")))
        }
        if filter != .running, runningCount > 0 {
            parts.append(FizzL10n.text("\(runningCount) 个运行中", "\(runningCount) running"))
        }
        if isScanning {
            parts.append(FizzL10n.text("正在扫描", "Scanning"))
        } else if pendingSizeCount > 0 {
            parts.append(FizzL10n.text("正在统计体积 (\(pendingSizeCount))", "Calculating sizes (\(pendingSizeCount))"))
        } else if let relativeScannedAt {
            parts.append(FizzL10n.text("\(relativeScannedAt)更新", "Updated \(relativeScannedAt)"))
        }
        return parts.joined(separator: " · ")
    }

    static func batchCleanupCommands(for projects: [RepoProject]) -> BatchCleanupCommands {
        let commands = projects.compactMap { project -> String? in
            let command = project.cleanup.removalCommand
            guard !command.isEmpty else { return nil }
            return "# \(project.displayName)\n\(command)"
        }
        return BatchCleanupCommands(
            script: commands.isEmpty ? nil : commands.joined(separator: "\n"),
            result: .cleanup(copied: commands.count, skipped: projects.count - commands.count)
        )
    }

    static func toolTitle(_ raw: String) -> String {
        DetectedTool(rawValue: raw)?.title ?? raw
    }

    static func toolSymbol(_ raw: String) -> String {
        DetectedTool(rawValue: raw)?.symbol ?? "sparkles"
    }
}

enum LibraryGridDirection: Sendable {
    case up
    case down
    case left
    case right
}

enum LibraryKeyboardNavigation {
    static func nextIndex(
        current: Int?,
        direction: LibraryGridDirection,
        count: Int,
        columns: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        let step = max(1, columns)
        guard let current, current >= 0, current < count else {
            switch direction {
            case .right, .down: return 0
            case .left, .up: return count - 1
            }
        }
        switch direction {
        case .left:
            return max(0, current - 1)
        case .right:
            return min(count - 1, current + 1)
        case .up:
            return current >= step ? current - step : current
        case .down:
            return min(count - 1, current + step)
        }
    }
}
