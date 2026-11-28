import Foundation

enum HeatmapRange: String, CaseIterable, Identifiable, Sendable {
    case weeks26
    case months12

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeks26: FizzL10n.text("26 周", "26 weeks")
        case .months12: FizzL10n.text("12 月", "12 months")
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
    let weeklyTouchedFiles: Int
    let commits: DashboardTrend
    let sessions: DashboardTrend
    let touchedFiles: DashboardTrend
    let cost: DashboardTrend
    let tokens: DashboardTrend
}

struct DashboardTrend: Equatable, Sendable {
    let samples: [Double]
    let change: Double?

    init(samples: [Double], current: Double?, previous: Double?, minimumPrevious: Double = 0) {
        self.samples = samples
        guard let current, current.isFinite, current >= 0,
              let previous, previous.isFinite, previous > 0, previous >= minimumPrevious else {
            change = nil
            return
        }
        let ratio = (current - previous) / previous
        change = ratio.isFinite && ratio <= 2 ? ratio : nil
    }
}

enum CostBreakdownMode: String, CaseIterable, Identifiable, Sendable {
    case byTool
    case byProject

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byTool: FizzL10n.text("按工具", "By tool")
        case .byProject: FizzL10n.text("按项目", "By project")
        }
    }
}

struct CostSegment: Identifiable, Equatable, Sendable {
    enum Name: Equatable, Sendable {
        case source(String), selfUsage, other

        var title: String {
            switch self {
            case .source(let name): name
            case .selfUsage: FizzL10n.text("FizzDeck 自身", "FizzDeck itself")
            case .other: FizzL10n.text("其他", "Other")
            }
        }
    }

    let id: String
    let name: Name
    var label: String { name.title }
    let costUSD: Double
    let tokens: Double
    let fraction: Double
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
        struct Day {
            var sessions = 0
            var files: Set<String> = []
            var tokens: Int?
            var cost: Double?
        }

        let today = calendar.startOfDay(for: now)
        let weekStart = sevenDayWindowStart(now: now, calendar: calendar)
        let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let dayKeys = (0..<14).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: prevWeekStart) ?? today
            return WorkbenchMetrics.dayKey(date, calendar: calendar)
        }
        let indices = Dictionary(dayKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var days = Array(repeating: Day(), count: dayKeys.count)

        let dailyCommits = aggregateDailyProjectCommits(
            snapshot: commitActivity,
            projects: projects,
            calendar: calendar
        )
        let commits = dayKeys.map { key in
            (dailyCommits[key] ?? []).reduce(0) { $0 + $1.count }
        }

        var monthlyCost: Double?
        var costIsEstimate = false

        for project in projects {
            for session in project.sessions.recentSessions
            where session.modified >= monthStart && session.modified <= now && !session.isWorkspaceSummary {
                let cost = session.costUSD.flatMap { $0.isFinite ? max(0, $0) : nil }
                if let cost {
                    monthlyCost = (monthlyCost ?? 0) + cost
                }

                guard session.modified >= prevWeekStart,
                      let index = indices[WorkbenchMetrics.dayKey(session.modified, calendar: calendar)] else { continue }
                days[index].sessions += 1
                if let tokens = session.usage?.totalTokens {
                    days[index].tokens = (days[index].tokens ?? 0) + max(0, tokens)
                }
                for file in session.touchedFiles where !file.isEmpty {
                    days[index].files.insert("\(project.path)::\(file)")
                }
                if let cost {
                    days[index].cost = (days[index].cost ?? 0) + cost
                    costIsEstimate = costIsEstimate || (index >= 7 && session.costIsEstimate == true)
                }
            }
        }

        let current = days.suffix(7)
        let previous = days.prefix(7)
        let weeklyCommits = commits.suffix(7).reduce(0, +)
        let weeklySessions = current.reduce(0) { $0 + $1.sessions }
        let weeklyFiles = current.reduce(into: Set<String>()) { $0.formUnion($1.files) }.count
        let previousFiles = previous.reduce(into: Set<String>()) { $0.formUnion($1.files) }.count
        let weeklyCost = sumIfRecorded(current.map(\.cost))
        let previousCost = sumIfRecorded(previous.map(\.cost))
        let weeklyTokens = sumIfRecorded(current.map(\.tokens))
        let previousTokens = sumIfRecorded(previous.map(\.tokens))
        let costTrend = DashboardTrend(
            samples: weeklyCost == nil ? [] : current.map { $0.cost ?? 0 },
            current: weeklyCost,
            previous: previousCost,
            minimumPrevious: 0.5
        )

        func trend(_ samples: [Int], current: Int, previous: Int, minimum: Double = 0) -> DashboardTrend {
            DashboardTrend(samples: samples.map(Double.init), current: Double(current),
                           previous: Double(previous), minimumPrevious: minimum)
        }

        return DashboardKPISummary(
            weeklyCommits: weeklyCommits,
            weeklySessions: weeklySessions,
            weeklyCostUSD: weeklyCost,
            previousWeekCostUSD: previousCost,
            monthlyCostUSD: monthlyCost,
            costIsEstimate: costIsEstimate,
            weeklyTokens: weeklyTokens ?? 0,
            weekOverWeekCostDeltaPercent: costTrend.change.map { $0 * 100 },
            weeklyTouchedFiles: weeklyFiles,
            commits: trend(Array(commits.suffix(7)), current: weeklyCommits, previous: commits.prefix(7).reduce(0, +)),
            sessions: trend(current.map(\.sessions), current: weeklySessions,
                            previous: previous.reduce(0) { $0 + $1.sessions }, minimum: 3),
            touchedFiles: trend(current.map { $0.files.count }, current: weeklyFiles, previous: previousFiles),
            cost: costTrend,
            tokens: DashboardTrend(
                samples: weeklyTokens == nil ? [] : current.map { Double($0.tokens ?? 0) },
                current: weeklyTokens.map(Double.init),
                previous: previousTokens.map(Double.init)
            )
        )
    }

    private static func sumIfRecorded<Value: AdditiveArithmetic>(_ values: [Value?]) -> Value? {
        let recorded = values.compactMap { $0 }
        return recorded.isEmpty ? nil : recorded.reduce(.zero, +)
    }

    static func weeklyConversationTotals(
        projects: [RepoProject], now: Date = Date(), calendar: Calendar = .current
    ) -> WeeklyRecapTotals {
        let start = sevenDayWindowStart(now: now, calendar: calendar)
        var totals = WeeklyRecapTotals()
        for project in projects {
            for session in project.sessions.recentSessions
            where session.kind == .conversation && (start...now).contains(session.modified) {
                totals.add(session)
            }
        }
        return totals
    }

    static func costBreakdown(
        sessions: [WeeklyRecapSession],
        mode: CostBreakdownMode,
        selfUsage: SelfUsageTotals? = nil
    ) -> [CostSegment] {
        var buckets: [String: (label: String, totals: WeeklyRecapTotals)] = [:]
        for row in sessions {
            let key = mode == .byTool ? row.record.tool : row.projectPath
            let label = mode == .byTool ? HomeDashboardModel.toolTitle(row.record.tool) : row.projectName
            buckets[key, default: (label, WeeklyRecapTotals())].totals.add(row.record)
        }
        var entries = buckets.map { key, value in
            (id: key, name: CostSegment.Name.source(value.label), cost: value.totals.cost.subtotal, tokens: value.totals.tokens)
        }
        if mode == .byTool,
           let selfUsage,
           (selfUsage.estimatedCostUSD > 0 || selfUsage.totalTokens > 0) {
            entries.append(("fizzdeck-self", .selfUsage, selfUsage.estimatedCostUSD, Double(selfUsage.totalTokens)))
        }

        let totalCost = entries.reduce(0.0) { $0 + $1.cost }
        let useCost = totalCost > 0
        let sorted = entries.map { (id: $0.id, name: $0.name, cost: $0.cost, tokens: $0.tokens,
                                    metric: useCost ? $0.cost : $0.tokens) }
        .filter { $0.metric > 0 }
        .sorted { left, right in
            if left.metric != right.metric {
                return left.metric > right.metric
            }
            let lhs = left.name.title, rhs = right.name.title
            return lhs == rhs ? left.id < right.id : lhs < rhs
        }
        let total = sorted.reduce(0.0) { $0 + $1.metric }
        guard total > 0 else { return [] }

        var result: [CostSegment] = sorted.prefix(5).map { item in
            CostSegment(
                id: item.id,
                name: item.name,
                costUSD: item.cost,
                tokens: item.tokens,
                fraction: item.metric / total
            )
        }

        if sorted.count > 5 {
            let tail = sorted.dropFirst(5)
            let otherCost = tail.reduce(0.0) { $0 + $1.cost }
            let otherTokens = tail.reduce(0.0) { $0 + $1.tokens }
            let otherMetric = tail.reduce(0.0) { $0 + $1.metric }
            result.append(CostSegment(
                id: "other",
                name: .other,
                costUSD: otherCost,
                tokens: otherTokens,
                fraction: otherMetric / total
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
            let summary = cleaned.isEmpty ? FizzL10n.text("\(toolTitle) 会话", "\(toolTitle) session") : cleaned
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
        calendar: Calendar = .current,
        copyMode: CopyMode = .pro
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
                let detail: String
                if copyMode == .plain {
                    detail = FizzL10n.text("存了 \(group.count) 个版本", "\(SessionSummaryText.englishCount(group.count, "version")) saved")
                } else {
                    detail = group.count == 1 ? FizzL10n.text("提交", "Commit") : FizzL10n.text("\(group.count) 次提交", "\(group.count) commits")
                }
                blocksByDay[key, default: []].append(TimelineBlock(
                    id: "c:\(path):\(key)",
                    startHour: group.earliestHour,
                    durationHours: min(2.5, 0.75 + Double(group.count - 1) * 0.25),
                    projectName: project.displayName,
                    projectPath: path,
                    kind: .commit,
                    detail: detail
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
                    detail: copyMode == .plain ? FizzL10n.text("\(tool) 对话", "\(tool) conversation") : FizzL10n.text("\(tool) 会话", "\(tool) session")
                ))
            }
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = FizzL10n.locale
        weekdayFormatter.timeZone = calendar.timeZone
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
                title: FizzL10n.text("磁盘余量偏低", "Low disk space"),
                detail: FizzL10n.text("仅剩 \(Format.bytes(freeDiskBytes)) 可用", "Only \(Format.bytes(freeDiskBytes)) free"),
                targetProjectPath: nil
            ))
        }

        let cleanupBytes = projects.reduce(Int64(0)) { $0 + $1.cleanup.reusableBytes }
        let highCleanupThreshold: Int64 = 5_000_000_000
        if cleanupBytes >= highCleanupThreshold {
            alerts.append(HealthAlert(
                id: "high-cleanup",
                kind: .highCleanup,
                title: FizzL10n.text("可清理空间较多", "Space available to reclaim"),
                detail: FizzL10n.text("可释放 \(Format.bytes(cleanupBytes))", "Reclaim \(Format.bytes(cleanupBytes))"),
                targetProjectPath: nil
            ))
        }

        let staleCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        for project in projects where project.dirtyCount > 0 {
            if let recent = project.recent, recent < staleCutoff {
                alerts.append(HealthAlert(
                    id: "stale-dirty:\(project.path)",
                    kind: .staleDirty,
                    title: FizzL10n.text("\(project.displayName) 有陈旧未提交改动", "\(project.displayName) has old uncommitted changes"),
                    detail: FizzL10n.text("\(project.dirtyCount) 处改动 · \(Format.relative(recent))活跃", "\(SessionSummaryText.englishCount(project.dirtyCount, "change")) · Last active \(Format.relative(recent))"),
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
