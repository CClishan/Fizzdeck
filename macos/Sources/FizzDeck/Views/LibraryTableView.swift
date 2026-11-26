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

    static func makeRows(from projects: [RepoProject]) -> [LibraryTableRow] {
        projects.map { project in
            let framework = project.stacks.first?.items.first ?? "—"
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
                aiCostDisplay = Format.tokens(tokens)
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
                recentDisplay: Format.relative(project.recent)
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
            TableColumn("名称", sortUsing: LibraryRowComparator(column: .name)) { row in
                HStack(spacing: 7) {
                    ProjectBadgeIcon(project: row.project, size: 18, framed: false)
                    Text(row.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if row.project.starred {
                        FizzIcon(symbol: "star.fill", size: 8)
                            .foregroundStyle(.yellow)
                    }
                    if row.project.port == .running {
                        PortStatusBadge(state: .running, port: row.project.run?.port)
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("分组", sortUsing: LibraryRowComparator(column: .group)) { row in
                Text(row.group)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 78)

            TableColumn("框架", sortUsing: LibraryRowComparator(column: .framework)) { row in
                Text(row.framework)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 72, ideal: 96)

            TableColumn("分支", sortUsing: LibraryRowComparator(column: .branch)) { row in
                Text(row.branch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 110)

            TableColumn("改动", sortUsing: LibraryRowComparator(column: .dirtyCount)) { row in
                Text(row.dirtyCount > 0 ? "\(row.dirtyCount)" : "—")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(row.dirtyCount > 0 ? Color.orange : Color.secondary)
            }
            .width(min: 48, ideal: 56)

            TableColumn("未推送", sortUsing: LibraryRowComparator(column: .ahead)) { row in
                Text(row.ahead > 0 ? "↑\(row.ahead)" : "—")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(row.ahead > 0 ? FizzTheme.accent : Color.secondary)
            }
            .width(min: 52, ideal: 62)

            TableColumn("最近提交", sortUsing: LibraryRowComparator(column: .commitSubject)) { row in
                Text(row.commitSubject)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 140, ideal: 220)

            TableColumn("AI 费用", sortUsing: LibraryRowComparator(column: .aiCost)) { row in
                Text(row.aiCostDisplay)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(row.aiCostSortValue >= 0 ? Color.primary : Color.secondary)
            }
            .width(min: 66, ideal: 78)

            TableColumn("体积", sortUsing: LibraryRowComparator(column: .sizeBytes)) { row in
                Group {
                    if row.project.sizeLoadState == .ready {
                        Text(row.sizeDisplay)
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if row.project.sizeLoadState == .loading {
                        FizzShimmerPlaceholder(width: 42, height: 10)
                    } else {
                        Text("—")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(min: 64, ideal: 76)

            TableColumn("最近活跃", sortUsing: LibraryRowComparator(column: .recentTimestamp)) { row in
                Text(row.recentDisplay)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .width(min: 72, ideal: 86)
        }
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
                Button("打开 \(project.displayName)") {
                    store.openProject(project)
                }
                Button(project.starred ? "取消星标" : "设为星标") {
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
