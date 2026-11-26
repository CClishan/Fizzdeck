import SwiftUI

struct HomeProjectBrowser: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let projects: [RepoProject]
    let mode: HomeViewMode
    let selectionMode: Bool
    @Binding var selectedPaths: Set<String>
    let selectedCount: Int
    let allVisibleSelected: Bool
    let batchRunning: Bool
    let isScanning: Bool
    let batchFeedback: String?
    var knownGroups: [String] = []
    var allSelectedStarred: Bool = false
    var focusedProjectPath: String? = nil
    var onBatchStar: ((Bool) -> Void)? = nil
    var onBatchGroup: ((String?) -> Void)? = nil
    var onBatchFetch: (() -> Void)? = nil
    let onToggleSelection: (RepoProject) -> Void
    let onCopyCleanup: () -> Void
    let onRescanSelected: () -> Void
    let onToggleSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onEndSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("项目")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(projects.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            if selectionMode {
                batchBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            switch mode {
            case .cards:
                cards
            case .list:
                LibraryTableView(projects: projects, selectedPaths: $selectedPaths)
            }
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: selectionMode)
    }

    private var batchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "checkmark.circle", size: 13)
                    .foregroundStyle(FizzTheme.accent)
                Text("已选 \(selectedCount) 个")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()

                Spacer(minLength: 8)

                if let onBatchStar {
                    Button(allSelectedStarred ? "取消星标" : "设星标") {
                        onBatchStar(!allSelectedStarred)
                    }
                    .disabled(selectedCount == 0)
                    .opacity(selectedCount == 0 ? 0.42 : 1)
                    .buttonStyle(.glass)
                }

                if let onBatchGroup {
                    Menu("改分组") {
                        ForEach(knownGroups, id: \.self) { group in
                            Button(group) {
                                onBatchGroup(group)
                            }
                        }
                        if !knownGroups.isEmpty {
                            Divider()
                        }
                        Button("自动分组") {
                            onBatchGroup(nil)
                        }
                        Button("自定义…") {
                            if let custom = SystemActions.promptForGroupName() {
                                onBatchGroup(custom)
                            }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .disabled(selectedCount == 0)
                    .opacity(selectedCount == 0 ? 0.42 : 1)
                }

                if let onBatchFetch {
                    Button("Fetch", action: onBatchFetch)
                        .disabled(selectedCount == 0 || batchRunning || isScanning)
                        .opacity(selectedCount == 0 || batchRunning || isScanning ? 0.42 : 1)
                        .buttonStyle(.glass)
                }

                Button("复制清理命令", action: onCopyCleanup)
                    .disabled(selectedCount == 0)
                    .opacity(selectedCount == 0 ? 0.42 : 1)
                    .buttonStyle(.glass)

                Button(action: onRescanSelected) {
                    if batchRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("重新扫描")
                    }
                }
                .disabled(selectedCount == 0 || batchRunning || isScanning)
                .opacity(selectedCount == 0 || batchRunning || isScanning ? 0.42 : 1)
                .buttonStyle(.glass)

                Button(allVisibleSelected ? "取消全选" : "全选", action: onToggleSelectAll)
                    .disabled(projects.isEmpty)
                    .opacity(projects.isEmpty ? 0.42 : 1)
                    .buttonStyle(.glass)

                Button("清除", action: onClearSelection)
                    .disabled(selectedPaths.isEmpty)
                    .opacity(selectedPaths.isEmpty ? 0.42 : 1)
                    .buttonStyle(.glass)

                Button("完成", action: onEndSelection)
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)
                    .controlSize(.regular)
            }
            .controlSize(.small)

            if let batchFeedback {
                HStack(spacing: 5) {
                    FizzIcon(symbol: "info.circle", size: 11)
                        .foregroundStyle(FizzTheme.accent)
                    Text(batchFeedback)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fizzCard(radius: FizzRadius.card)
    }

    private var cards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: FizzSpacing.grid)],
            spacing: FizzSpacing.grid
        ) {
            ForEach(projects) { project in
                ProjectFolderCard(
                    project: project,
                    selecting: selectionMode,
                    selected: selectedPaths.contains(project.path),
                    focused: focusedProjectPath == project.path,
                    toggleSelection: { onToggleSelection(project) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
}
