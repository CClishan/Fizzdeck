import Foundation

enum WeeklyRecapRange: String, CaseIterable, Sendable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case all = "All"

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }

    var periodTitle: String {
        days.map { FizzL10n.text("最近 \($0) 天", "Last \($0) days") } ?? FizzL10n.text("全部已索引历史", "All indexed history")
    }

    var shortTitle: String { FizzL10n.text(days.map { "\($0) 天" } ?? "全部", rawValue) }
}

enum WeeklyRecapMetric: CaseIterable, Sendable {
    case sessions, agentTime, cost, tokens

    var title: String {
        switch self {
        case .sessions: FizzL10n.text("对话次数", "Sessions")
        case .agentTime: FizzL10n.text("AI 干活时长", "Agent time")
        case .cost: FizzL10n.text("估算费用", "Estimated cost")
        case .tokens: "Tokens"
        }
    }

    static let chartMetrics: [Self] = [.agentTime, .cost, .tokens]

    func label(_ value: Double?) -> String {
        guard let value else { return "—" }
        let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(FizzL10n.locale)
        let decimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(FizzL10n.locale)
        switch self {
        case .sessions: return value.formatted(whole)
        case .agentTime:
            if value < 60 { return value.formatted(whole) + FizzL10n.text(" 秒", " sec") }
            if value < 3_600 { return (value / 60).formatted(decimal) + FizzL10n.text(" 分钟", " min") }
            return (value / 3_600).formatted(decimal) + FizzL10n.text(" 小时", " hr")
        case .cost: return Format.cost(value, estimated: true) ?? "—"
        case .tokens: return Format.compactCount(value, locale: FizzL10n.locale)
        }
    }
}

struct WeeklyRecapTotals: Equatable, Sendable {
    private(set) var sessions = 0
    private(set) var errors = 0
    private(set) var timedSessions = 0
    private(set) var agentSeconds = 0.0
    private(set) var tokenSessions = 0
    private(set) var tokens = 0.0
    private(set) var cost = SessionCostTotal()

    mutating func add(_ session: SessionRecord) {
        sessions += 1
        if session.endedWithError { errors += 1 }
        if let seconds = session.agentTimeSeconds, seconds > 0 {
            timedSessions += 1
            agentSeconds += Double(seconds)
        }
        if let count = session.usage?.totalTokens, count > 0 {
            tokenSessions += 1
            tokens += Double(count)
        }
        cost.add(session, countZeroAsUnpriced: true)
    }

    func value(_ metric: WeeklyRecapMetric) -> Double? {
        switch metric {
        case .sessions: Double(sessions)
        case .agentTime: timedSessions > 0 ? agentSeconds : nil
        case .cost: cost.amount
        case .tokens: tokenSessions > 0 ? tokens : nil
        }
    }

    func detail(_ metric: WeeklyRecapMetric) -> String {
        switch metric {
        case .sessions: FizzL10n.text("本机记录的实际对话", "Sessions recorded on this Mac")
        case .cost:
            cost.unpriced == 0 ? FizzL10n.text("按已知计价汇总", "Based on available pricing")
                : cost.priced == 0 ? FizzL10n.text("\(cost.unpriced) 次未计价", "\(SessionSummaryText.englishCount(cost.unpriced, "unpriced session"))") : FizzL10n.text("另有 \(cost.unpriced) 次未计价", "Excludes \(SessionSummaryText.englishCount(cost.unpriced, "unpriced session"))")
        case .agentTime: timedSessions == 0 ? FizzL10n.text("无时长记录", "No time recorded") : FizzL10n.text("\(timedSessions) 次有时长记录", "Time recorded for \(SessionSummaryText.englishCount(timedSessions, "session"))")
        case .tokens: tokenSessions == 0 ? FizzL10n.text("无用量记录", "No usage recorded") : FizzL10n.text("\(tokenSessions) 次有用量记录", "Usage recorded for \(SessionSummaryText.englishCount(tokenSessions, "session"))")
        }
    }

    var averageSeconds: Double? { timedSessions > 0 ? agentSeconds / Double(timedSessions) : nil }
    var averageCost: Double? { cost.amount.map { $0 / Double(cost.priced) } }
    var errorRate: Double { sessions > 0 ? Double(errors) / Double(sessions) : 0 }
}

struct WeeklyRecapSession: Identifiable, Equatable, Sendable {
    let projectPath: String
    let projectName: String
    let record: SessionRecord

    var id: String { "\(projectPath)::\(record.stableID)" }
}

struct WeeklyRecapAnalysis: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let sessions: Int
        var id: Date { date }
    }

    struct Series: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let buckets: [Int: WeeklyRecapTotals]
    }

    struct Tool: Identifiable, Equatable, Sendable {
        let id: String
        let totals: WeeklyRecapTotals
    }

    let totals: WeeklyRecapTotals
    let previous: WeeklyRecapTotals?
    let previousStart: Date?
    let bucketStarts: [Date]
    let bucketTotals: [WeeklyRecapTotals]
    let daysPerBucket: Int
    let projects: [Series]
    let tools: [Tool]
    let sessions: [WeeklyRecapSession]
    let heatmap: [Day]
    let heatmapLeadingBlanks: Int
    let activeDays: Int
    let streak: Int
    let busiestDay: Day?
    let longestSession: WeeklyRecapSession?

    func trend(_ metric: WeeklyRecapMetric) -> DashboardTrend {
        let value = totals.value(metric)
        let minimum: Double = switch metric {
        case .sessions: 3
        case .cost: 0.5
        default: 0
        }
        return DashboardTrend(
            samples: value == nil ? [] : bucketTotals.map { $0.value(metric) ?? 0 },
            current: value, previous: previous?.value(metric), minimumPrevious: minimum
        )
    }

    // A missing measurement breaks the line. Empty buckets contribute zero only to conversation counts.
    func samples(_ metric: WeeklyRecapMetric) -> [Double?] {
        bucketTotals.map { $0.value(metric) }
    }

    static func build(
        sessions: [WeeklyRecapSession], previous: WeeklyRecapTotals?, previousStart: Date?,
        start: Date, now: Date, calendar: Calendar
    ) -> Self {
        let today = calendar.startOfDay(for: now)
        let dayCount = max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
        let stride = 1 + (dayCount - 1) / 45
        let bucketCount = 1 + (dayCount - 1) / stride
        let bucketStarts = (0..<bucketCount).map { calendar.date(byAdding: .day, value: $0 * stride, to: start) ?? start }
        var bucketTotals = Array(repeating: WeeklyRecapTotals(), count: bucketCount)
        var projectNames: [String: String] = [:]
        var projectCounts: [String: Int] = [:]
        var byProject: [String: [Int: WeeklyRecapTotals]] = [:]
        var byTool: [String: WeeklyRecapTotals] = [:]
        var active: [Date: Int] = [:]
        var totals = WeeklyRecapTotals()
        var longest: WeeklyRecapSession?

        for session in sessions {
            let record = session.record
            let date = calendar.startOfDay(for: record.modified)
            let day = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            guard day >= 0, day < dayCount else { continue }
            let index = day / stride
            totals.add(record)
            bucketTotals[index].add(record)
            active[date, default: 0] += 1
            byTool[record.tool, default: WeeklyRecapTotals()].add(record)
            byProject[session.projectPath, default: [:]][index, default: WeeklyRecapTotals()].add(record)
            projectNames[session.projectPath] = session.projectName
            projectCounts[session.projectPath, default: 0] += 1
            if let seconds = record.agentTimeSeconds, seconds > (longest?.record.agentTimeSeconds ?? 0) {
                longest = session
            }
        }

        let projects = byProject.map { path, buckets in
            Series(id: path, name: projectNames[path] ?? path, buckets: buckets)
        }.sorted {
            let left = projectCounts[$0.id, default: 0]
            let right = projectCounts[$1.id, default: 0]
            return left == right ? $0.id < $1.id : left > right
        }
        var tools = byTool.map { Tool(id: $0.key, totals: $0.value) }
        tools.sort { left, right in
            let lhs = left.totals.sessions
            let rhs = right.totals.sessions
            return lhs == rhs ? left.id < right.id : lhs > rhs
        }
        let busiest = active.max { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value }
            .map { Day(date: $0.key, sessions: $0.value) }
        let heatmap = (max(0, dayCount - 42)..<dayCount).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Day(date: date, sessions: active[date, default: 0])
        }
        let weekday = heatmap.first.map { calendar.component(.weekday, from: $0.date) } ?? calendar.firstWeekday
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var streak = 0
        var day = active[today] == nil ? calendar.date(byAdding: .day, value: -1, to: today) : today
        while let current = day, active[current] != nil {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: current)
        }
        return Self(
            totals: totals, previous: previous, previousStart: previousStart, bucketStarts: bucketStarts,
            bucketTotals: bucketTotals, daysPerBucket: stride, projects: projects, tools: tools,
            sessions: sessions.sorted { $0.record.modified == $1.record.modified ? $0.id < $1.id : $0.record.modified > $1.record.modified },
            heatmap: heatmap, heatmapLeadingBlanks: leading, activeDays: active.count,
            streak: streak, busiestDay: busiest, longestSession: longest
        )
    }
}
