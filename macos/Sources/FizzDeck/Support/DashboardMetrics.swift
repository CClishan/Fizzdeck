import Foundation

enum HeatmapRange: String, CaseIterable, Identifiable, Sendable {
    case weeks26
    case months12

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeks26: "26 周"
        case .months12: "12 月"
        }
    }

    var weekCount: Int {
        switch self {
        case .weeks26: 26
        case .months12: 52
        }
    }
}

struct HeatmapProjectCount: Equatable, Sendable {
    let name: String
    let path: String
    let count: Int
}

struct HeatmapDayCell: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let count: Int
    let level: Int
    let isFuture: Bool
    let projects: [HeatmapProjectCount]
}

struct HeatmapSummary: Equatable, Sendable {
    let columns: [[HeatmapDayCell]]
    let totalCommits: Int
    let currentStreak: Int
    let longestStreak: Int
    let weekCommits: Int
}

struct AIToolShare: Identifiable, Equatable, Sendable {
    let id: String
    let tool: String
    let title: String
    let tokens: Int
    let sessions: Int
    let costUSD: Double
    let fraction: Double
}

struct DashboardKPISummary: Equatable, Sendable {
    let weeklyCommits: Int
    let weeklySessions: Int
    let weeklyCostUSD: Double?
    let previousWeekCostUSD: Double?
    let monthlyCostUSD: Double?
    let costIsEstimate: Bool
    let weeklyTokens: Int
    let weekOverWeekCostDeltaPercent: Double?
    var weeklyTouchedFiles: Int = 0
}

enum CostBreakdownMode: String, CaseIterable, Identifiable, Sendable {
    case byTool
    case byProject

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byTool: "按工具"
        case .byProject: "按项目"
        }
    }
}

struct CostSegment: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let costUSD: Double
    let tokens: Int
    let fraction: Double
    let tintKey: String
}

struct ContinueWorkItem: Identifiable, Sendable {
    let id: String
    let project: RepoProject
    let session: SessionRecord
    let toolTitle: String
    let summary: String
    let modified: Date
    var touchedFileCount: Int = 0
    var durationMinutes: Int? = nil
    var endedWithError: Bool = false
    var lastError: String? = nil
}

struct TimelineBlock: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case commit
        case session
    }

    let id: String
    let startHour: Double
    let durationHours: Double
    let projectName: String
    let projectPath: String
    let kind: Kind
    let detail: String
}

struct TimelineDayColumn: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let weekdayLabel: String
    let dayNumber: String
    let isToday: Bool
    let blocks: [TimelineBlock]
}

struct HealthAlert: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case lowDisk
        case highCleanup
        case staleDirty
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let targetProjectPath: String?
}

enum DashboardMetrics {
    static func buildHeatmap(
        snapshot: CommitActivitySnapshot,
        projects: [RepoProject],
        range: HeatmapRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HeatmapSummary {
        let today = calendar.startOfDay(for: now)
        let currentWeekMonday = startOfISOWeek(for: today, calendar: calendar)
        let weekCount = range.weekCount
        let gridStart = calendar.date(byAdding: .day, value: -(weekCount - 1) * 7, to: currentWeekMonday) ?? today

        let perDayProjects = aggregateDailyProjectCommits(
            snapshot: snapshot,
            projects: projects,
            calendar: calendar
        )

        var allCountsInRange: [Int] = []
        var totalCommits = 0
        var columns: [[HeatmapDayCell]] = []
        columns.reserveCapacity(weekCount)

        for weekIndex in 0..<weekCount {
            var weekCells: [HeatmapDayCell] = []
            weekCells.reserveCapacity(7)
            for dayOffset in 0..<7 {
                let offset = weekIndex * 7 + dayOffset
                let date = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? today
                let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
                let isFuture = date > today
                let projectCounts = isFuture ? [] : (perDayProjects[key] ?? [])
                let count = projectCounts.reduce(0) { $0 + $1.count }
                if !isFuture {
                    allCountsInRange.append(count)
                    totalCommits += count
                }
                weekCells.append(HeatmapDayCell(
                    id: key,
                    date: date,
                    count: count,
                    level: 0,
                    isFuture: isFuture,
                    projects: projectCounts
                ))
            }
            columns.append(weekCells)
        }

        let thresholds = intensityThresholds(for: allCountsInRange)
        columns = columns.map { week in
            week.map { cell in
                HeatmapDayCell(
                    id: cell.id,
                    date: cell.date,
                    count: cell.count,
                    level: cell.isFuture ? 0 : intensityLevel(for: cell.count, thresholds: thresholds),
                    isFuture: cell.isFuture,
                    projects: cell.projects
                )
            }
        }

        let (currentStreak, longestStreak) = computeStreaks(
            perDayProjects: perDayProjects,
            from: gridStart,
            through: today,
            calendar: calendar
        )

        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var weekCommits = 0
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: sevenDayStart) ?? today
            let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
            weekCommits += (perDayProjects[key] ?? []).reduce(0) { $0 + $1.count }
        }

        return HeatmapSummary(
            columns: columns,
            totalCommits: totalCommits,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            weekCommits: weekCommits
        )
    }

    /// Builds an AI activity heatmap for plain-language mode by aggregating conversation sessions
    /// and touched files per day. In the returned `HeatmapSummary`, `totalCommits` stores total
    /// activity units across the range and `weekCommits` stores the trailing 7-day activity units.
    static func buildAIActivityHeatmap(
        projects: [RepoProject],
        range: HeatmapRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HeatmapSummary {
        let today = calendar.startOfDay(for: now)
        let currentWeekMonday = startOfISOWeek(for: today, calendar: calendar)
        let weekCount = range.weekCount
        let gridStart = calendar.date(byAdding: .day, value: -(weekCount - 1) * 7, to: currentWeekMonday) ?? today

        let perDayProjects = aggregateDailyAIActivity(projects: projects, calendar: calendar)

        var allCountsInRange: [Int] = []
        var totalActivity = 0
        var columns: [[HeatmapDayCell]] = []
        columns.reserveCapacity(weekCount)

        for weekIndex in 0..<weekCount {
            var weekCells: [HeatmapDayCell] = []
            weekCells.reserveCapacity(7)
            for dayOffset in 0..<7 {
                let offset = weekIndex * 7 + dayOffset
                let date = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? today
                let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
                let isFuture = date > today
                let projectCounts = isFuture ? [] : (perDayProjects[key] ?? [])
                let count = projectCounts.reduce(0) { $0 + $1.count }
                if !isFuture {
                    allCountsInRange.append(count)
                    totalActivity += count
                }
                weekCells.append(HeatmapDayCell(
                    id: key,
                    date: date,
                    count: count,
                    level: 0,
                    isFuture: isFuture,
                    projects: projectCounts
                ))
            }
            columns.append(weekCells)
        }

        let thresholds = intensityThresholds(for: allCountsInRange)
        columns = columns.map { week in
            week.map { cell in
                HeatmapDayCell(
                    id: cell.id,
                    date: cell.date,
                    count: cell.count,
                    level: cell.isFuture ? 0 : intensityLevel(for: cell.count, thresholds: thresholds),
                    isFuture: cell.isFuture,
                    projects: cell.projects
                )
            }
        }

        let (currentStreak, longestStreak) = computeStreaks(
            perDayProjects: perDayProjects,
            from: gridStart,
            through: today,
            calendar: calendar
        )

        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var weekActivity = 0
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: sevenDayStart) ?? today
            let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
            weekActivity += (perDayProjects[key] ?? []).reduce(0) { $0 + $1.count }
        }

        return HeatmapSummary(
            columns: columns,
            totalCommits: totalActivity,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            weekCommits: weekActivity
        )
    }

    static func projectPathsCommitted(
        onDayKey dayKey: String,
        snapshot: CommitActivitySnapshot,
        projects: [RepoProject],
        calendar: Calendar = .current
    ) -> Set<String> {
        let perDay = aggregateDailyProjectCommits(
            snapshot: snapshot,
            projects: projects,
            calendar: calendar
        )
        return Set((perDay[dayKey] ?? []).map(\.path))
    }

    static func weeklyToolShares(
        projects: [RepoProject],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AIToolShare] {
        let cutoff = sevenDayWindowStart(now: now, calendar: calendar)
        var byTool: [String: (tokens: Int, sessions: Int, cost: Double)] = [:]

        for project in projects {
            for session in project.sessions.recentSessions where session.modified >= cutoff {
                let tokens = max(0, session.usage?.totalTokens ?? 0)
                let cost = max(0, session.costUSD ?? 0)
                var current = byTool[session.tool] ?? (0, 0, 0)
                current.tokens += tokens
                current.sessions += 1
                current.cost += cost
                byTool[session.tool] = current
            }
        }

        guard !byTool.isEmpty else { return [] }
        let totalTokens = byTool.values.reduce(0) { $0 + $1.tokens }
        let totalSessions = byTool.values.reduce(0) { $0 + $1.sessions }
        let useTokens = totalTokens > 0
        let denominator = Double(useTokens ? totalTokens : max(1, totalSessions))

        return byTool.map { tool, value in
            let metric = Double(useTokens ? value.tokens : value.sessions)
            return AIToolShare(
                id: tool,
                tool: tool,
                title: HomeDashboardModel.toolTitle(tool),
                tokens: value.tokens,
                sessions: value.sessions,
                costUSD: value.cost,
                fraction: metric / denominator
            )
        }
        .sorted { left, right in
            if left.fraction != right.fraction {
                return left.fraction > right.fraction
            }
            return left.tool < right.tool
        }
    }

    static func kpiSummary(
        projects: [RepoProject],
        commitActivity: CommitActivitySnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardKPISummary {
        let today = calendar.startOfDay(for: now)
        let weekStart = sevenDayWindowStart(now: now, calendar: calendar)
        let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today

        let perDay = aggregateDailyProjectCommits(
            snapshot: commitActivity,
            projects: projects,
            calendar: calendar
        )
        var weeklyCommits = 0
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? today
            let key = WorkbenchMetrics.dayKey(day, calendar: calendar)
            weeklyCommits += (perDay[key] ?? []).reduce(0) { $0 + $1.count }
        }

        var weeklySessions = 0
        var weeklyTokens = 0
        var weeklyCost = 0.0
        var hasWeeklyCost = false
        var prevWeekCost = 0.0
        var hasPrevWeekCost = false
        var monthlyCost = 0.0
        var hasMonthlyCost = false
        var costIsEstimate = false

        var touchedPairs = Set<String>()
        for project in projects {
            for session in project.sessions.recentSessions {
                if session.modified >= weekStart {
                    weeklySessions += 1
                    weeklyTokens += max(0, session.usage?.totalTokens ?? 0)
                    for file in session.touchedFiles where !file.isEmpty {
                        touchedPairs.insert("\(project.path)::\(file)")
                    }
                    if let cost = session.costUSD {
                        weeklyCost += max(0, cost)
                        hasWeeklyCost = true
                    }
                    if session.costIsEstimate == true {
                        costIsEstimate = true
                    }
                } else if session.modified >= prevWeekStart {
                    if let cost = session.costUSD {
                        prevWeekCost += max(0, cost)
                        hasPrevWeekCost = true
                    }
                }

                if session.modified >= monthStart, let cost = session.costUSD {
                    monthlyCost += max(0, cost)
                    hasMonthlyCost = true
                }
            }
        }

        let delta: Double?
        if hasWeeklyCost && hasPrevWeekCost && prevWeekCost > 0 {
            delta = ((weeklyCost - prevWeekCost) / prevWeekCost) * 100
        } else {
            delta = nil
        }

        return DashboardKPISummary(
            weeklyCommits: weeklyCommits,
            weeklySessions: weeklySessions,
            weeklyCostUSD: hasWeeklyCost ? weeklyCost : nil,
            previousWeekCostUSD: hasPrevWeekCost ? prevWeekCost : nil,
            monthlyCostUSD: hasMonthlyCost ? monthlyCost : nil,
            costIsEstimate: costIsEstimate,
            weeklyTokens: weeklyTokens,
            weekOverWeekCostDeltaPercent: delta,
            weeklyTouchedFiles: touchedPairs.count
        )
    }

    static func costBreakdown(
        projects: [RepoProject],
        mode: CostBreakdownMode,
        selfUsage: SelfUsageTotals? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CostSegment] {
        let cutoff = sevenDayWindowStart(now: now, calendar: calendar)
        var buckets: [String: (label: String, cost: Double, tokens: Int, tintKey: String)] = [:]

        for project in projects {
            for session in project.sessions.recentSessions where session.modified >= cutoff {
                let cost = max(0, session.costUSD ?? 0)
                let tokens = max(0, session.usage?.totalTokens ?? 0)
                guard cost > 0 || tokens > 0 else { continue }

                let key: String
                let label: String
                let tintKey: String
                switch mode {
                case .byTool:
                    key = session.tool
                    label = HomeDashboardModel.toolTitle(session.tool)
                    tintKey = session.tool
                case .byProject:
                    key = project.path
                    label = project.displayName
                    tintKey = project.group
                }

                var entry = buckets[key] ?? (label, 0, 0, tintKey)
                entry.cost += cost
                entry.tokens += tokens
                buckets[key] = entry
            }
        }

        if mode == .byTool,
           let selfUsage,
           (selfUsage.estimatedCostUSD > 0 || selfUsage.totalTokens > 0) {
            var entry = buckets["fizzdeck-self"] ?? ("FizzDeck 自身", 0, 0, "fizzdeck-self")
            entry.cost += max(0, selfUsage.estimatedCostUSD)
            entry.tokens += max(0, selfUsage.totalTokens)
            buckets["fizzdeck-self"] = entry
        }

        guard !buckets.isEmpty else { return [] }
        let totalCost = buckets.values.reduce(0.0) { $0 + $1.cost }
        let useCost = totalCost > 0
        let total = useCost
            ? totalCost
            : Double(max(1, buckets.values.reduce(0) { $0 + $1.tokens }))

        let sorted = buckets.map { key, value in
            (
                id: key,
                label: value.label,
                cost: value.cost,
                tokens: value.tokens,
                tintKey: value.tintKey,
                metric: useCost ? value.cost : Double(value.tokens)
            )
        }
        .sorted { left, right in
            if left.metric != right.metric {
                return left.metric > right.metric
            }
            return left.label < right.label
        }

        var result: [CostSegment] = sorted.prefix(5).map { item in
            CostSegment(
                id: item.id,
                label: item.label,
                costUSD: item.cost,
                tokens: item.tokens,
                fraction: item.metric / total,
                tintKey: item.tintKey
            )
        }

        if sorted.count > 5 {
            let tail = sorted.dropFirst(5)
            let otherCost = tail.reduce(0.0) { $0 + $1.cost }
            let otherTokens = tail.reduce(0) { $0 + $1.tokens }
            let otherMetric = tail.reduce(0.0) { $0 + $1.metric }
            result.append(CostSegment(
                id: "other",
                label: "其他",
                costUSD: otherCost,
                tokens: otherTokens,
                fraction: otherMetric / total,
                tintKey: "other"
            ))
        }

        return result
    }

    static func continueWorkItems(projects: [RepoProject], limit: Int = 4) -> [ContinueWorkItem] {
        guard limit > 0 else { return [] }
        var candidates: [ContinueWorkItem] = []

        for project in projects {
            let resumable = project.sessions.recentSessions.filter {
                $0.kind == .conversation && DetectedTool(rawValue: $0.tool)?.supportsResume == true
            }
            guard let latest = resumable.max(by: { $0.modified < $1.modified }) else { continue }
            let toolTitle = HomeDashboardModel.toolTitle(latest.tool)
            let cleaned = SessionSummaryText.clean(latest.primaryIntent ?? "")
            let summary = cleaned.isEmpty ? "\(toolTitle) 会话" : cleaned
            candidates.append(ContinueWorkItem(
                id: "\(project.path)::\(latest.stableID)",
                project: project,
                session: latest,
                toolTitle: toolTitle,
                summary: summary,
                modified: latest.modified,
                touchedFileCount: latest.touchedFiles.count,
                durationMinutes: latest.durationMinutes,
                endedWithError: latest.endedWithError,
                lastError: latest.lastError
            ))
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }

    static func weeklyTimeline(
        projects: [RepoProject],
        commitActivity: CommitActivitySnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimelineDayColumn] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let projectByPath = Dictionary(
            projects.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var blocksByDay: [String: [TimelineBlock]] = [:]
        var commitGroups: [String: [String: (earliestHour: Double, count: Int)]] = [:]

        for (path, activity) in commitActivity.byProject {
            guard projectByPath[path] != nil else { continue }
            for ts in activity.timestamps {
                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= today else { continue }
                let key = WorkbenchMetrics.dayKey(day, calendar: calendar)
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60.0
                if let existing = commitGroups[key]?[path] {
                    commitGroups[key, default: [:]][path] = (
                        earliestHour: min(existing.earliestHour, hour),
                        count: existing.count + 1
                    )
                } else {
                    commitGroups[key, default: [:]][path] = (earliestHour: hour, count: 1)
                }
            }
        }

        for (key, byPath) in commitGroups {
            for (path, group) in byPath {
                guard let project = projectByPath[path] else { continue }
                blocksByDay[key, default: []].append(TimelineBlock(
                    id: "c:\(path):\(key)",
                    startHour: group.earliestHour,
                    durationHours: min(2.5, 0.75 + Double(group.count - 1) * 0.25),
                    projectName: project.displayName,
                    projectPath: path,
                    kind: .commit,
                    detail: group.count == 1 ? "提交" : "\(group.count) 次提交"
                ))
            }
        }

        for project in projects {
            for session in project.sessions.recentSessions {
                let day = calendar.startOfDay(for: session.modified)
                guard day >= start, day <= today else { continue }
                let key = WorkbenchMetrics.dayKey(day, calendar: calendar)
                let anchor = session.startedAt ?? session.modified
                let comps = calendar.dateComponents([.hour, .minute], from: anchor)
                let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60.0
                let spanSeconds = session.startedAt.map { max(900, session.modified.timeIntervalSince($0)) } ?? 1_800
                let durationHours = min(3.0, max(0.5, spanSeconds / 3_600.0))
                let tool = HomeDashboardModel.toolTitle(session.tool)

                blocksByDay[key, default: []].append(TimelineBlock(
                    id: "s:\(project.path):\(session.stableID)",
                    startHour: hour,
                    durationHours: durationHours,
                    projectName: project.displayName,
                    projectPath: project.path,
                    kind: .session,
                    detail: "\(tool) 会话"
                ))
            }
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_Hans")
        weekdayFormatter.calendar = calendar
        weekdayFormatter.dateFormat = "E"

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? today
            let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
            let dayNum = calendar.component(.day, from: date)
            let sortedBlocks = (blocksByDay[key] ?? []).sorted { $0.startHour < $1.startHour }
            return TimelineDayColumn(
                id: key,
                date: date,
                weekdayLabel: weekdayFormatter.string(from: date),
                dayNumber: "\(dayNum)",
                isToday: calendar.isDate(date, inSameDayAs: today),
                blocks: sortedBlocks
            )
        }
    }

    static func healthAlerts(
        projects: [RepoProject],
        freeDiskBytes: Int64?,
        now: Date = Date()
    ) -> [HealthAlert] {
        var alerts: [HealthAlert] = []
        let lowDiskThreshold: Int64 = 20_000_000_000
        if let freeDiskBytes, freeDiskBytes < lowDiskThreshold {
            alerts.append(HealthAlert(
                id: "low-disk",
                kind: .lowDisk,
                title: "磁盘余量偏低",
                detail: "仅剩 \(Format.bytes(freeDiskBytes)) 可用",
                targetProjectPath: nil
            ))
        }

        let cleanupBytes = projects.reduce(Int64(0)) { $0 + $1.cleanup.reusableBytes }
        let highCleanupThreshold: Int64 = 5_000_000_000
        if cleanupBytes >= highCleanupThreshold {
            alerts.append(HealthAlert(
                id: "high-cleanup",
                kind: .highCleanup,
                title: "可清理空间较多",
                detail: "可释放 \(Format.bytes(cleanupBytes))",
                targetProjectPath: nil
            ))
        }

        let staleCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        for project in projects where project.dirtyCount > 0 {
            if let recent = project.recent, recent < staleCutoff {
                alerts.append(HealthAlert(
                    id: "stale-dirty:\(project.path)",
                    kind: .staleDirty,
                    title: "\(project.displayName) 有陈旧未提交改动",
                    detail: "\(project.dirtyCount) 处改动 · \(Format.relative(recent))活跃",
                    targetProjectPath: project.path
                ))
            }
        }

        return alerts
    }

    static func partitionByActivity(
        _ projects: [RepoProject],
        idleDays: Int = 30,
        now: Date = Date()
    ) -> (active: [RepoProject], idle: [RepoProject]) {
        let cutoff = now.addingTimeInterval(-Double(idleDays) * 24 * 60 * 60)
        var active: [RepoProject] = []
        var idle: [RepoProject] = []

        for project in projects {
            if project.starred || project.port == .running {
                active.append(project)
            } else if let recent = project.recent, recent >= cutoff {
                active.append(project)
            } else if project.recent == nil {
                active.append(project)
            } else {
                idle.append(project)
            }
        }
        return (active, idle)
    }

    // MARK: - Private Helpers

    static func sevenDayWindowStart(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today
    }

    private static func startOfISOWeek(for day: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: day)
        // Sunday = 1, Monday = 2, ..., Saturday = 7
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    private static func aggregateDailyProjectCommits(
        snapshot: CommitActivitySnapshot,
        projects: [RepoProject],
        calendar: Calendar
    ) -> [String: [HeatmapProjectCount]] {
        var perDayPerProject: [String: [String: (name: String, count: Int)]] = [:]

        if !snapshot.byProject.isEmpty {
            let nameByPath = Dictionary(
                projects.map { ($0.path, $0.displayName) },
                uniquingKeysWith: { first, _ in first }
            )
            for (path, activity) in snapshot.byProject {
                guard let name = nameByPath[path] else { continue }
                for ts in activity.timestamps {
                    let date = Date(timeIntervalSince1970: TimeInterval(ts))
                    let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
                    var projectMap = perDayPerProject[key] ?? [:]
                    let current = projectMap[path]?.count ?? 0
                    projectMap[path] = (name, current + 1)
                    perDayPerProject[key] = projectMap
                }
            }
        } else {
            // Fallback to project.weekly when commit-activity cache is not yet populated.
            for project in projects {
                for (dayKey, count) in project.weekly where count > 0 {
                    var projectMap = perDayPerProject[dayKey] ?? [:]
                    let current = projectMap[project.path]?.count ?? 0
                    projectMap[project.path] = (project.displayName, current + count)
                    perDayPerProject[dayKey] = projectMap
                }
            }
        }

        return perDayPerProject.mapValues { map in
            map.map { path, entry in
                HeatmapProjectCount(name: entry.name, path: path, count: entry.count)
            }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return left.name < right.name
            }
        }
    }

    private static func aggregateDailyAIActivity(
        projects: [RepoProject],
        calendar: Calendar
    ) -> [String: [HeatmapProjectCount]] {
        var perDayPerProject: [String: [String: (name: String, count: Int)]] = [:]

        for project in projects {
            for session in project.sessions.recentSessions where session.kind == .conversation {
                let key = WorkbenchMetrics.dayKey(session.modified, calendar: calendar)
                let units = max(1, session.touchedFiles.count)
                var projectMap = perDayPerProject[key] ?? [:]
                let current = projectMap[project.path]?.count ?? 0
                projectMap[project.path] = (project.displayName, current + units)
                perDayPerProject[key] = projectMap
            }
        }

        return perDayPerProject.mapValues { map in
            map.map { path, entry in
                HeatmapProjectCount(name: entry.name, path: path, count: entry.count)
            }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return left.name < right.name
            }
        }
    }

    private static func intensityThresholds(for counts: [Int]) -> [Int] {
        let nonZero = counts.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return [1, 2, 4, 8] }
        let q1 = nonZero[(nonZero.count - 1) / 4]
        let q2 = nonZero[(nonZero.count - 1) / 2]
        let q3 = nonZero[((nonZero.count - 1) * 3) / 4]
        let t1 = max(1, q1)
        let t2 = max(t1 + 1, q2)
        let t3 = max(t2 + 1, q3)
        return [t1, t2, t3]
    }

    private static func intensityLevel(for count: Int, thresholds: [Int]) -> Int {
        guard count > 0 else { return 0 }
        if count <= thresholds[0] { return 1 }
        if count <= thresholds[1] { return 2 }
        if count <= thresholds[2] { return 3 }
        return 4
    }

    private static func computeStreaks(
        perDayProjects: [String: [HeatmapProjectCount]],
        from start: Date,
        through today: Date,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        let totalDays = max(0, (calendar.dateComponents([.day], from: start, to: today).day ?? 0)) + 1
        var longest = 0
        var running = 0
        var activeDays: [Bool] = []
        activeDays.reserveCapacity(totalDays)

        for offset in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? today
            let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
            let active = !(perDayProjects[key] ?? []).isEmpty
            activeDays.append(active)
            if active {
                running += 1
                longest = max(longest, running)
            } else {
                running = 0
            }
        }

        // Current streak counts backward from today (or yesterday if today has 0 commits yet).
        var current = 0
        var idx = activeDays.count - 1
        if idx >= 0, !activeDays[idx] {
            idx -= 1
        }
        while idx >= 0, activeDays[idx] {
            current += 1
            idx -= 1
        }

        return (current, longest)
    }
}
