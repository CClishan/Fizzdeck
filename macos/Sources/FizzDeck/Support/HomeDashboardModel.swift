import Foundation

enum HomeViewMode: String, CaseIterable, Identifiable, Sendable {
    case cards
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: "卡片墙"
        case .list: "极简列表"
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近活动"
        case .name: "名称"
        case .size: "体积"
        }
    }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .name: "textformat.abc"
        case .size: "internaldrive"
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
            parts.append("显示 \(visibleCount) / \(matchingCount) 个项目")
        } else {
            parts.append("\(visibleCount) 个项目")
        }
        if filter != .running, runningCount > 0 {
            parts.append("\(runningCount) 个运行中")
        }
        if isScanning {
            parts.append("正在扫描")
        } else if pendingSizeCount > 0 {
            parts.append("正在统计体积 (\(pendingSizeCount))")
        } else if let relativeScannedAt {
            parts.append("\(relativeScannedAt)更新")
        }
        return parts.joined(separator: " · ")
    }

    static func batchCleanupCommands(for projects: [RepoProject]) -> (script: String?, feedback: String) {
        let commands = projects.compactMap { project -> String? in
            let command = project.cleanup.removalCommand
            guard !command.isEmpty else { return nil }
            return "# \(project.displayName)\n\(command)"
        }
        guard !commands.isEmpty else {
            return (nil, "所选项目没有可清理项")
        }

        let skipped = projects.count - commands.count
        let feedback = skipped == 0
            ? "已复制 \(commands.count) 个项目的清理命令"
            : "已复制 \(commands.count) 个；\(skipped) 个没有可清理项"
        return (commands.joined(separator: "\n"), feedback)
    }

    static func toolTitle(_ raw: String) -> String {
        DetectedTool(rawValue: raw)?.title ?? raw.capitalized
    }

    static func toolSymbol(_ raw: String) -> String {
        DetectedTool(rawValue: raw)?.symbol ?? "sparkles"
    }
}
