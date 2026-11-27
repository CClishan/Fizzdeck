import SwiftUI

struct ProjectActivityPanel: View {
    let project: RepoProject
    @State private var counts: [String: Int]?
    @State private var readingGit = false

    var body: some View {
        let now = Date()
        let gitStatus = readingGit || project.gitLoadState != .ready ? "读取中…" : (project.branch == nil ? "未开启版本保护" : "暂无数据")
        ProjectActivityChart(history: ProjectActivityDay.series(sessions: project.sessions.recentSessions, commits: counts, days: 30, now: now),
                             sessionsReady: project.sessionLoadState == .ready, gitStatus: counts == nil ? gitStatus : nil)
            .task(id: [project.path, project.lastCommit?.hash ?? "", project.branch ?? "", WorkbenchMetrics.dayKey(now)]) {
                counts = nil
                guard project.lastCommit != nil else {
                    if project.branch != nil { counts = [:] }
                    readingGit = false
                    return
                }
                readingGit = true
                let result = await GitService.dailyCommitCounts(URL(fileURLWithPath: project.path), days: 30, now: now)
                guard !Task.isCancelled else { return }
                counts = result
                readingGit = false
            }
    }
}

private struct ProjectActivityChart: View {
    let history: [ProjectActivityDay]
    let sessionsReady: Bool
    let gitStatus: String?
    @State private var days = 14

    var body: some View {
        let series = history.suffix(days)
        let cost = series.reduce(into: SessionCostTotal()) { $0.add($1.cost) }
        let commitTotal = series.compactMap(\.commits).reduce(0, +)

        Panel(title: "项目活动", symbol: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 6) {
                rowTitle("AI 估算费用", value: sessionsReady ? cost.description : "读取中…")
                    .help("会话费用归入最后活动的本地日期；空心菱形表示有未计价的会话。")
                bars(series, costRow: true)
                rowTitle("提交", value: gitStatus ?? "\(commitTotal) 次")
                bars(series, costRow: false)
                if let first = series.first, let last = series.last {
                    HStack {
                        Text(first.date, format: .dateTime.month().day())
                        Spacer()
                        if cost.unpriced > 0 { Label("有未计价会话", systemImage: "diamond") }
                        Spacer()
                        Text(last.date, format: .dateTime.month().day())
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        } accessory: {
            Picker("活动范围", selection: $days) {
                Text("14 天").tag(14)
                Text("30 天").tag(30)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 124)
        }
    }

    private func rowTitle(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func bars(_ series: ArraySlice<ProjectActivityDay>, costRow: Bool) -> some View {
        let peak = series.map { costRow ? $0.cost.subtotal : Double($0.commits ?? 0) }.max() ?? 0
        let tint = costRow ? FizzTheme.accent : Color.teal
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(series) { day in
                let value = costRow ? day.cost.amount : day.commits.map(Double.init)
                let unknown = costRow && day.cost.unpriced > 0
                let detail = costRow ? day.cost.description : (day.commits.map { "\($0) 次提交" } ?? "暂无提交数据")
                VStack(spacing: 1) {
                    if unknown { Image(systemName: "diamond").font(.system(size: 6)).foregroundStyle(.secondary) }
                    RoundedRectangle(cornerRadius: 2)
                        .fill((value ?? 0) > 0 || (costRow && day.cost.priced > 0) ? tint : FizzTheme.stroke)
                        .frame(height: value.map { peak > 0 ? max(2, 27 * $0 / peak) : 2 } ?? 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .help("\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(detail)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted))，\(detail)")
            }
        }
        .frame(height: 35)
    }
}
