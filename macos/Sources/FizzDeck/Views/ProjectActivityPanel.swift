import SwiftUI

struct ProjectActivityPanel: View {
    let project: RepoProject
    @State private var counts: [String: Int]?
    @State private var readingGit = false

    var body: some View {
        let now = Date()
        let gitStatus = readingGit || project.gitLoadState != .ready ? FizzL10n.text("读取中…", "Loading…") : (project.branch == nil ? FizzL10n.text("未开启版本保护", "Version protection off") : FizzL10n.text("暂无数据", "No data"))
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

        Panel(title: FizzL10n.text("项目活动", "Project activity"), symbol: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                rowTitle(FizzL10n.text("AI 估算费用", "Estimated AI cost"), value: sessionsReady ? cost.description : FizzL10n.text("读取中…", "Loading…"))
                    .help(FizzL10n.text("会话费用归入最后活动的本地日期；空心菱形表示有未计价的会话。", "Session costs use the local date of last activity. A hollow diamond marks a day with unpriced sessions."))
                bars(series, costRow: true)
                rowTitle(FizzL10n.text("提交", "Commits"), value: gitStatus ?? FizzL10n.text("\(commitTotal) 次", "\(commitTotal)"))
                bars(series, costRow: false)
                if let first = series.first, let last = series.last {
                    HStack {
                        Text(first.date, format: .dateTime.month().day().locale(FizzL10n.locale))
                        Spacer()
                        if cost.unpriced > 0 { Label(FizzL10n.text("有未计价会话", "Includes unpriced sessions"), systemImage: "diamond") }
                        Spacer()
                        Text(last.date, format: .dateTime.month().day().locale(FizzL10n.locale))
                    }
                    .font(FizzTypography.micro)
                    .foregroundStyle(.secondary)
                }
            }
        } accessory: {
            Picker(FizzL10n.text("活动范围", "Activity range"), selection: $days) {
                Text(FizzL10n.text("14 天", "14 days")).tag(14)
                Text(FizzL10n.text("30 天", "30 days")).tag(30)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 124, height: FizzControlHeight.compact.rawValue)
            .focusable(interactions: .edit)
        }
    }

    private func rowTitle(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(FizzTypography.caption)
    }

    private func bars(_ series: ArraySlice<ProjectActivityDay>, costRow: Bool) -> some View {
        let peak = series.map { costRow ? $0.cost.subtotal : Double($0.commits ?? 0) }.max() ?? 0
        let tint = Color.secondary.opacity(costRow ? 0.65 : 0.85)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(series) { day in
                let value = costRow ? day.cost.amount : day.commits.map(Double.init)
                let date = day.date.formatted(.dateTime.year().month(.abbreviated).day().locale(FizzL10n.locale))
                let unknown = costRow && day.cost.unpriced > 0
                let detail = costRow ? day.cost.description : (day.commits.map { FizzL10n.text("\($0) 次提交", "\($0) \($0 == 1 ? "commit" : "commits")") } ?? FizzL10n.text("暂无提交数据", "No commit data"))
                VStack(spacing: 1) {
                    if unknown {
                        Rectangle()
                            .strokeBorder(.secondary, lineWidth: 1)
                            .frame(width: 5, height: 5)
                            .rotationEffect(.degrees(45))
                    }
                    RoundedRectangle(cornerRadius: FizzRadius.micro)
                        .fill((value ?? 0) > 0 || (costRow && day.cost.priced > 0) ? tint : FizzTheme.stroke)
                        .frame(height: value.map { peak > 0 ? max(2, 27 * $0 / peak) : 2 } ?? 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .help("\(date) · \(detail)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FizzL10n.text("\(date)，\(detail)", "\(date), \(detail)"))
            }
        }
        .frame(height: 35)
    }
}
