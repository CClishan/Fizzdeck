import Foundation

struct WeeklyRecapProject: Identifiable, Equatable, Sendable {
    let path: String
    let name: String
    let sessionCount: Int
    let changedFileCount: Int
    let savedVersionCount: Int
    let cost: SessionCostTotal
    let lastActivityAt: Date

    var id: String { path }
}

struct WeeklyRecapTopFile: Identifiable, Equatable, Sendable {
    let projectName: String
    let path: String
    let sessionCount: Int

    var id: String { "\(projectName)::\(path)" }
}

struct WeeklyRecap: Equatable, Sendable {
    let range: WeeklyRecapRange
    let windowStart: Date
    let generatedAt: Date
    let activeProjects: [WeeklyRecapProject]
    let sessionCount: Int
    let changedFileCount: Int
    let savedVersionCount: Int
    let cost: SessionCostTotal
    let topFiles: [WeeklyRecapTopFile]
    let analysis: WeeklyRecapAnalysis
    let calendar: Calendar

    var hasActivity: Bool {
        sessionCount > 0 || savedVersionCount > 0
    }

    func markdown(polishedSummary: String?) -> String {
        guard let polishedSummary else { return markdown }
        return markdown + FizzL10n.text("\n\n## AI 润色\n\n", "\n\n## AI summary\n\n") + SecretRedactor.redact(polishedSummary).text
    }
}

enum WeeklyRecapService {
    static func build(
        projects: [RepoProject],
        range: WeeklyRecapRange = .week,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyRecap {
        let endDay = calendar.startOfDay(for: now)
        let windowStart: Date
        if let days = range.days {
            windowStart = calendar.date(byAdding: .day, value: 1 - days, to: endDay) ?? endDay
        } else {
            windowStart = allTimeStart(projects: projects, now: now, calendar: calendar)
        }
        let previousStart = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: windowStart) }
        var previous = previousStart.map { _ in WeeklyRecapTotals() }
        var rows: [WeeklyRecapSession] = []
        var projectSummaries: [WeeklyRecapProject] = []
        var fileSessionCounts: [String: (project: String, path: String, count: Int)] = [:]
        var globalFiles = Set<String>()

        for project in projects {
            var sessions: [SessionRecord] = []
            for session in project.sessions.recentSessions where session.kind == .conversation && session.modified <= now {
                if session.modified >= windowStart {
                    sessions.append(session)
                    rows.append(.init(projectPath: project.path, projectName: project.displayName, record: session))
                } else if let previousStart, session.modified >= previousStart {
                    previous?.add(session)
                }
            }
            let commits = savedVersionCount(
                in: project.weekly,
                windowStart: windowStart,
                now: now,
                calendar: calendar
            )
            guard !sessions.isEmpty || commits > 0 else { continue }

            var projectFiles = Set<String>()
            for session in sessions {
                var sessionFileKeys = Set<String>()
                for rawPath in session.touchedFiles {
                    let path = displayPath(rawPath, projectPath: project.path)
                    guard !path.isEmpty else { continue }
                    let normalizedPath = path.lowercased()
                    guard sessionFileKeys.insert(normalizedPath).inserted else { continue }

                    projectFiles.insert(normalizedPath)
                    let key = "\(project.path)::\(normalizedPath)"
                    globalFiles.insert(key)
                    if var entry = fileSessionCounts[key] {
                        entry.count += 1
                        fileSessionCounts[key] = entry
                    } else {
                        fileSessionCounts[key] = (project.displayName, path, 1)
                    }
                }
            }

            projectSummaries.append(
                WeeklyRecapProject(
                    path: project.path,
                    name: project.displayName,
                    sessionCount: sessions.count,
                    changedFileCount: projectFiles.count,
                    savedVersionCount: commits,
                    cost: sessions.reduce(into: SessionCostTotal()) { $0.add($1, countZeroAsUnpriced: true) },
                    lastActivityAt: max(
                        sessions.map(\.modified).max() ?? .distantPast,
                        project.recent ?? .distantPast
                    )
                )
            )
        }

        projectSummaries.sort {
            if $0.sessionCount != $1.sessionCount {
                return $0.sessionCount > $1.sessionCount
            }
            if $0.savedVersionCount != $1.savedVersionCount {
                return $0.savedVersionCount > $1.savedVersionCount
            }
            return $0.lastActivityAt > $1.lastActivityAt
        }

        let topFiles = fileSessionCounts.values
            .map { WeeklyRecapTopFile(projectName: $0.project, path: $0.path, sessionCount: $0.count) }
            .sorted {
                if $0.sessionCount != $1.sessionCount {
                    return $0.sessionCount > $1.sessionCount
                }
                if $0.projectName != $1.projectName {
                    return $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending
                }
                return $0.path < $1.path
            }
            .prefix(5)
            .map { $0 }

        let sessionCount = projectSummaries.reduce(0) { $0 + $1.sessionCount }
        let savedVersionCount = projectSummaries.reduce(0) { $0 + $1.savedVersionCount }
        let analysis = WeeklyRecapAnalysis.build(
            sessions: rows, previous: previous, previousStart: previousStart,
            start: windowStart, now: now, calendar: calendar
        )
        return WeeklyRecap(
            range: range,
            windowStart: windowStart,
            generatedAt: now,
            activeProjects: projectSummaries,
            sessionCount: sessionCount,
            changedFileCount: globalFiles.count,
            savedVersionCount: savedVersionCount,
            cost: analysis.totals.cost,
            topFiles: topFiles,
            analysis: analysis,
            calendar: calendar
        )
    }

    private static func allTimeStart(projects: [RepoProject], now: Date, calendar: Calendar) -> Date {
        var first = now
        let today = WorkbenchMetrics.dayKey(now, calendar: calendar)
        var earliestCommit: String?
        for project in projects {
            for session in project.sessions.recentSessions where session.kind == .conversation && session.modified < first {
                first = session.modified
            }
            for (key, count) in project.weekly where count > 0 && key <= today && key < (earliestCommit ?? "~") {
                earliestCommit = key
            }
        }
        if let earliestCommit {
            let fields = earliestCommit.split(separator: "-").compactMap { Int($0) }
            if fields.count == 3, let date = calendar.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2])) {
                first = min(first, date)
            }
        }
        return calendar.startOfDay(for: first)
    }

    static func savedVersionCount(
        in weekly: [String: Int],
        windowStart: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let first = WorkbenchMetrics.dayKey(windowStart, calendar: calendar)
        let last = WorkbenchMetrics.dayKey(now, calendar: calendar)
        return weekly.reduce(0) { sum, entry in
            guard (first...last).contains(entry.key) else { return sum }
            return sum + max(0, entry.value)
        }
    }

    static func displayPath(_ path: String, projectPath: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let project = PathTools.normalize(projectPath)
        let absolute = value.hasPrefix("/") ? PathTools.normalize(value) : nil
        if let absolute {
            let prefix = project + "/"
            if absolute.hasPrefix(prefix) {
                value = String(absolute.dropFirst(prefix.count))
            } else {
                value = URL(fileURLWithPath: absolute).lastPathComponent
            }
        }
        while value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension WeeklyRecap {
    var markdown: String {
        let totals = analysis.totals
        let formatter = DateFormatter()
        formatter.locale = FizzL10n.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let includeYear = range == .all || !calendar.isDate(windowStart, equalTo: generatedAt, toGranularity: .year)
        formatter.dateFormat = FizzL10n.text(includeYear ? "yyyy 年 M 月 d 日" : "M 月 d 日",
                                            includeYear ? "MMM d, yyyy" : "MMM d")
        let dates = "\(formatter.string(from: windowStart)) – \(formatter.string(from: generatedAt))"

        var lines = [
            range == .week ? FizzL10n.text("# FizzDeck 本周回顾", "# FizzDeck weekly recap") : FizzL10n.text("# FizzDeck 跨 Agent 复盘", "# FizzDeck agent recap"),
            "",
            "**\(dates)**",
            "",
        ]

        guard sessionCount > 0 || savedVersionCount > 0 else {
            lines.append(FizzL10n.text("这段时间还没有新的 AI 对话或保存记录。", "No AI sessions or saved versions were recorded in this period."))
            lines.append(FizzL10n.text("下次和 AI 一起改完东西，再回来看看。", "Check back after your next session."))
            lines.append("")
            lines.append(FizzL10n.text("> 由 FizzDeck 在本机汇总，密钥已脱敏。", "> Compiled on this Mac by FizzDeck. Secrets are redacted."))
            return lines.joined(separator: "\n")
        }

        let count = SessionSummaryText.englishCount
        lines.append(FizzL10n.text(
            "\(range.periodTitle)，你在 \(activeProjects.count) 个项目里和 AI 聊了 \(sessionCount) 次，改了 \(changedFileCount) 个文件，存下 \(savedVersionCount) 个版本。",
            "\(range.periodTitle): \(count(sessionCount, "AI session")) across \(count(activeProjects.count, "project")), \(count(changedFileCount, "file")) changed, and \(count(savedVersionCount, "version")) saved."
        ))
        lines.append("")
        lines.append(FizzL10n.text("## 活跃项目", "## Active projects"))
        for project in activeProjects.prefix(6) {
            lines.append(FizzL10n.text(
                "- **\(project.name)**：\(project.sessionCount) 次对话 · \(project.changedFileCount) 个文件 · \(project.savedVersionCount) 个版本",
                "- **\(project.name)**: \(count(project.sessionCount, "session")) · \(count(project.changedFileCount, "file")) · \(count(project.savedVersionCount, "version"))"
            ))
        }

        if !topFiles.isEmpty {
            lines.append("")
            lines.append(FizzL10n.text("## 改得最多", "## Most changed files"))
            for (index, file) in topFiles.enumerated() {
                lines.append(FizzL10n.text("\(index + 1). `\(file.path)` · \(file.projectName) · \(file.sessionCount) 次", "\(index + 1). `\(file.path)` · \(file.projectName) · \(count(file.sessionCount, "session"))"))
            }
        }

        lines.append("")
        let time = WeeklyRecapMetric.agentTime.label(totals.value(.agentTime))
        let tokens = WeeklyRecapMetric.tokens.label(totals.value(.tokens))
        lines.append(FizzL10n.text("估算费用：**\(cost.description)** · AI 干活时长：**\(time)** · Tokens：**\(tokens)**",
                                  "Estimated cost: **\(cost.description)** · Agent time: **\(time)** · Tokens: **\(tokens)**"))
        lines.append("")
        lines.append(FizzL10n.text("> 由 FizzDeck 在本机汇总，密钥已脱敏。", "> Compiled on this Mac by FizzDeck. Secrets are redacted."))
        return SecretRedactor.redact(lines.joined(separator: "\n")).text
    }
}
