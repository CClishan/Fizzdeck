import Foundation
import SwiftUI

struct LibraryTableRow: Identifiable, Sendable {
    let id: String
    let project: RepoProject
    let name: String
    let group: String
    let framework: String
    let branch: String
    let dirtyCount: Int
    let ahead: Int
    let commitSubject: String
    let aiCostSortValue: Double
    let aiCostDisplay: String
    let sizeBytes: Int64
    let sizeDisplay: String
    let recentTimestamp: TimeInterval
    let recentDisplay: String

    static func makeRows(from projects: [RepoProject], locale: Locale = FizzL10n.locale) -> [LibraryTableRow] {
        projects.map { project in
            let framework = project.stacks.first?.displayItems.first ?? "—"
            let branch = project.branch ?? "—"
            let commitSubject = !project.note.isEmpty
                ? project.note
                : (project.lastCommit?.subject ?? "—")
            let costUSD = project.sessions.totalCostUSD
            let tokens = project.sessions.totalTokens
            let aiCostDisplay: String
            let aiCostSortValue: Double
            if let cost = Format.cost(costUSD, estimated: project.sessions.costIsEstimate) {
                aiCostDisplay = cost
                aiCostSortValue = costUSD ?? 0
            } else if tokens > 0 {
                aiCostDisplay = Format.tokens(tokens, locale: locale)
                aiCostSortValue = Double(tokens) / 1_000_000_000.0
            } else {
                aiCostDisplay = "—"
                aiCostSortValue = -1
            }

            let sizeDisplay = project.sizeLoadState == .ready
                ? Format.bytes(project.size.totalBytes)
                : ""

            return LibraryTableRow(
                id: project.path,
                project: project,
                name: project.displayName,
                group: project.group,
                framework: framework,
                branch: branch,
                dirtyCount: project.dirtyCount,
                ahead: project.ahead,
                commitSubject: commitSubject,
                aiCostSortValue: aiCostSortValue,
                aiCostDisplay: aiCostDisplay,
                sizeBytes: project.size.totalBytes,
                sizeDisplay: sizeDisplay,
                recentTimestamp: project.recent?.timeIntervalSince1970 ?? 0,
                recentDisplay: Format.relative(project.recent, locale: locale)
            )
        }
    }
}

enum LibraryTableColumn: String, Hashable, Sendable {
    case name
    case group
    case framework
    case branch
    case dirtyCount
    case ahead
    case commitSubject
    case aiCost
    case sizeBytes
    case recentTimestamp
}

struct LibraryRowComparator: SortComparator, Hashable, Sendable {
    let column: LibraryTableColumn
    var order: SortOrder = .forward

    func compare(_ lhs: LibraryTableRow, _ rhs: LibraryTableRow) -> ComparisonResult {
        let result: ComparisonResult
        switch column {
        case .name:
            result = lhs.name.localizedStandardCompare(rhs.name)
        case .group:
            result = lhs.group.localizedStandardCompare(rhs.group)
        case .framework:
            result = lhs.framework.localizedStandardCompare(rhs.framework)
        case .branch:
            result = lhs.branch.localizedStandardCompare(rhs.branch)
        case .dirtyCount:
            result = compareValues(lhs.dirtyCount, rhs.dirtyCount)
        case .ahead:
            result = compareValues(lhs.ahead, rhs.ahead)
        case .commitSubject:
            result = lhs.commitSubject.localizedStandardCompare(rhs.commitSubject)
        case .aiCost:
            result = compareValues(lhs.aiCostSortValue, rhs.aiCostSortValue)
        case .sizeBytes:
            result = compareValues(lhs.sizeBytes, rhs.sizeBytes)
        case .recentTimestamp:
            result = compareValues(lhs.recentTimestamp, rhs.recentTimestamp)
        }
        return order == .forward ? result : inverted(result)
    }

    private func compareValues<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func inverted(_ result: ComparisonResult) -> ComparisonResult {
        switch result {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

struct LibraryTableView: View {
    @Environment(RepositoryStore.self) private var store

    let projects: [RepoProject]
    @Binding var selectedPaths: Set<String>

    @State private var sortOrder: [LibraryRowComparator] = [
        LibraryRowComparator(column: .recentTimestamp, order: .reverse),
    ]

    private var rows: [LibraryTableRow] {
        LibraryTableRow.makeRows(from: projects).sorted(using: sortOrder)
    }

    private var tableHeight: CGFloat {
        max(280, min(580, CGFloat(projects.count) * 34 + 38))
    }

    var body: some View {
        Table(rows, selection: $selectedPaths, sortOrder: $sortOrder) {
            TableColumn(FizzL10n.text("名称", "Name"), sortUsing: LibraryRowComparator(column: .name)) { row in
                HStack(spacing: 7) {
                    ProjectBadgeIcon(project: row.project, size: 18, framed: false)
                    Text(row.name)
                        .font(FizzTypography.body(.medium))
                        .lineLimit(1)
                    if row.project.starred {
                        FizzIcon(.xs, symbol: "star.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    if row.project.port == .running {
                        PortStatusBadge(state: .running, port: row.project.run?.port)
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn(FizzL10n.text("分组", "Group"), sortUsing: LibraryRowComparator(column: .group)) { row in
                Text(row.project.groupTitle)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 78)

            TableColumn(FizzL10n.text("框架", "Framework"), sortUsing: LibraryRowComparator(column: .framework)) { row in
                Text(row.framework)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 72, ideal: 96)

            TableColumn(FizzL10n.text("分支", "Branch"), sortUsing: LibraryRowComparator(column: .branch)) { row in
                Text(row.branch)
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 110)

            TableColumn(FizzL10n.text("改动", "Changes"), sortUsing: LibraryRowComparator(column: .dirtyCount)) { row in
                Text(row.dirtyCount > 0 ? "\(row.dirtyCount)" : "—")
                    .font(FizzTypography.mono)
                    .foregroundStyle(row.dirtyCount > 0 ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 82)

            TableColumn(FizzL10n.text("未推送", "Unpushed"), sortUsing: LibraryRowComparator(column: .ahead)) { row in
                Text(row.ahead > 0 ? "↑\(row.ahead)" : "—")
                    .font(FizzTypography.mono)
                    .foregroundStyle(row.ahead > 0 ? Color.secondary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 76, ideal: 86)

            TableColumn(FizzL10n.text("最近提交", "Latest commit"), sortUsing: LibraryRowComparator(column: .commitSubject)) { row in
                Text(row.commitSubject)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 140, ideal: 220)

            TableColumn(FizzL10n.text("AI 费用", "AI cost"), sortUsing: LibraryRowComparator(column: .aiCost)) { row in
                Text(row.aiCostDisplay)
                    .font(FizzTypography.mono)
                    .foregroundStyle(row.aiCostSortValue >= 0 ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 66, ideal: 78)

            TableColumn(FizzL10n.text("体积", "Size"), sortUsing: LibraryRowComparator(column: .sizeBytes)) { row in
                Group {
                    if row.project.sizeLoadState == .ready {
                        Text(row.sizeDisplay)
                            .foregroundStyle(.secondary)
                    } else if row.project.sizeLoadState == .loading {
                        FizzShimmerPlaceholder(width: 42, height: 10)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(FizzTypography.mono)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 76)

            TableColumn(FizzL10n.text("最近活跃", "Last active"), sortUsing: LibraryRowComparator(column: .recentTimestamp)) { row in
                Text(row.recentDisplay)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .id(FizzL10n.isEnglish)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(height: tableHeight)
        .clipShape(RoundedRectangle(cornerRadius: FizzRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.panel, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
        .contextMenu(forSelectionType: String.self) { selection in
            if let path = selection.first,
               let project = projects.first(where: { $0.path == path }) {
                Button(FizzL10n.text("打开 \(project.displayName)", "Open \(project.displayName)")) {
                    store.openProject(project)
                }
                Button(project.starred ? FizzL10n.text("取消星标", "Unstar") : FizzL10n.text("设为星标", "Star")) {
                    store.toggleStar(project)
                }
                ProjectGroupingMenu(project: project)
                Divider()
                ProjectQuickActions(project: project)
            }
        } primaryAction: { selection in
            if let path = selection.first,
               let project = projects.first(where: { $0.path == path }) {
                store.openProject(project)
            }
        }
    }
}
