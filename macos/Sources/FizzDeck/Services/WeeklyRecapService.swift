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
    let windowStart: Date
    let generatedAt: Date
    let activeProjects: [WeeklyRecapProject]
    let sessionCount: Int
    let changedFileCount: Int
    let savedVersionCount: Int
    let cost: SessionCostTotal
    let topFiles: [WeeklyRecapTopFile]
    let markdown: String

    var hasActivity: Bool {
        sessionCount > 0 || savedVersionCount > 0
    }

    func markdown(polishedSummary: String?) -> String {
        guard let polishedSummary else { return markdown }
        return markdown + "\n\n## AI 润色\n\n" + SecretRedactor.redact(polishedSummary).text
    }
}

enum WeeklyRecapService {
    static func build(
        projects: [RepoProject],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyRecap {
        let endDay = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: endDay)
            ?? now.addingTimeInterval(-6 * 24 * 60 * 60)
        var projectSummaries: [WeeklyRecapProject] = []
        var fileSessionCounts: [String: (project: String, path: String, count: Int)] = [:]
        var globalFiles = Set<String>()

        for project in projects {
            let sessions = project.sessions.recentSessions.filter {
                $0.kind == .conversation
                    && $0.modified >= windowStart
                    && $0.modified <= now
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
                    cost: sessions.reduce(into: SessionCostTotal()) { $0.add($1) },
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
        let cost = projectSummaries.reduce(into: SessionCostTotal()) { $0.add($1.cost) }
        let markdown = makeMarkdown(
            windowStart: windowStart,
            generatedAt: now,
            projects: projectSummaries,
            sessionCount: sessionCount,
            changedFileCount: globalFiles.count,
            savedVersionCount: savedVersionCount,
            cost: cost,
            topFiles: topFiles
        )

        return WeeklyRecap(
            windowStart: windowStart,
            generatedAt: now,
            activeProjects: projectSummaries,
            sessionCount: sessionCount,
            changedFileCount: globalFiles.count,
            savedVersionCount: savedVersionCount,
            cost: cost,
            topFiles: topFiles,
            markdown: SecretRedactor.redact(markdown).text
        )
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

    private static func makeMarkdown(
        windowStart: Date,
        generatedAt: Date,
        projects: [WeeklyRecapProject],
        sessionCount: Int,
        changedFileCount: Int,
        savedVersionCount: Int,
        cost: SessionCostTotal,
        topFiles: [WeeklyRecapTopFile]
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M 月 d 日"
        let range = "\(formatter.string(from: windowStart)) – \(formatter.string(from: generatedAt))"

        var lines = [
            "# FizzDeck 本周回顾",
            "",
            "**\(range)**",
            "",
        ]

        guard sessionCount > 0 || savedVersionCount > 0 else {
            lines.append("这周还没有新的 AI 对话或保存记录。")
            lines.append("下次和 AI 一起改完东西，再回来看看。")
            lines.append("")
            lines.append("> 由 FizzDeck 在本机汇总，密钥已脱敏。")
            return lines.joined(separator: "\n")
        }

        lines.append(
            "这 7 天里，你在 \(projects.count) 个项目里和 AI 聊了 \(sessionCount) 次，"
                + "改了 \(changedFileCount) 个文件，存下 \(savedVersionCount) 个版本。"
        )
        lines.append("")
        lines.append("## 活跃项目")
        for project in projects.prefix(6) {
            lines.append(
                "- **\(project.name)**：\(project.sessionCount) 次对话 · "
                    + "\(project.changedFileCount) 个文件 · \(project.savedVersionCount) 个版本"
            )
        }

        if !topFiles.isEmpty {
            lines.append("")
            lines.append("## 改得最多")
            for (index, file) in topFiles.enumerated() {
                lines.append("\(index + 1). `\(file.path)` · \(file.projectName) · \(file.sessionCount) 次")
            }
        }

        lines.append("")
        lines.append("估算费用：**\(cost.description)**")
        lines.append("")
        lines.append("> 由 FizzDeck 在本机汇总，密钥已脱敏。")
        return lines.joined(separator: "\n")
    }
}
