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
    var showsCoverPreview = true
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

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(FizzL10n.text("项目", "Projects"))
                    .font(FizzTypography.font(15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(projects.count)")
                    .font(FizzTypography.micro(.regular))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            if selectionMode {
                batchBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                switch mode {
                case .cards:
                    cards
                case .list:
                    LibraryTableView(projects: projects, selectedPaths: $selectedPaths)
                }
            }
            .id(mode)
            .transition(.opacity.combined(with: .scale(scale: 0.992, anchor: .top)))
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: selectionMode)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: mode)
    }

    private var batchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FizzIcon(.md, symbol: "checkmark.circle")
                    .foregroundStyle(Color.secondary)
                Text(FizzL10n.text("已选 \(selectedCount) 个", "\(selectedCount) selected"))
                    .font(FizzTypography.caption(.medium))

                Spacer(minLength: 8)

                FizzMenuButton(title: FizzL10n.text("更多批量操作", "More actions for selected projects")) {
                    if let onBatchStar {
                        Button(allSelectedStarred ? FizzL10n.text("取消星标", "Unstar") : FizzL10n.text("设星标", "Star")) {
                            onBatchStar(!allSelectedStarred)
                        }
                        .disabled(selectedCount == 0)
                    }

                    if let onBatchGroup {
                        Menu(FizzL10n.text("改分组", "Change group")) {
                            ForEach(knownGroups, id: \.self) { group in
                                Button(ProjectGrouping.title(for: group)) { onBatchGroup(group) }
                            }
                            if !knownGroups.isEmpty {
                                Divider()
                            }
                            Button(FizzL10n.text("自动分组", "Automatic group")) { onBatchGroup(nil) }
                            Button(FizzL10n.text("自定义…", "Custom…")) {
                                if let custom = SystemActions.promptForGroupName() {
                                    onBatchGroup(custom)
                                }
                            }
                        }
                        .disabled(selectedCount == 0)
                    }

                    if let onBatchFetch {
                        Button(GitSyncAction.fetch.title, action: onBatchFetch)
                            .disabled(selectedCount == 0 || batchRunning || isScanning)
                    }

                    Button(FizzL10n.text("复制清理命令", "Copy cleanup commands"), action: onCopyCleanup)
                        .disabled(selectedCount == 0)

                    Divider()

                    Button(allVisibleSelected ? FizzL10n.text("取消全选", "Deselect all") : FizzL10n.text("全选", "Select all"), action: onToggleSelectAll)
                        .disabled(projects.isEmpty)
                    Button(FizzL10n.text("清除", "Clear"), action: onClearSelection)
                        .disabled(selectedPaths.isEmpty)
                }

                FizzActionButton(
                    title: batchRunning ? FizzL10n.text("扫描中…", "Scanning…") : FizzL10n.text("重新扫描", "Rescan"),
                    height: .compact,
                    action: onRescanSelected
                )
                .disabled(selectedCount == 0 || batchRunning || isScanning)
            }

            if let batchFeedback {
                HStack(spacing: 5) {
                    FizzIcon(.sm, symbol: "info.circle")
                        .foregroundStyle(Color.secondary)
                    Text(batchFeedback)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(FizzTypography.micro)
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
                    showsCoverPreview: showsCoverPreview,
                    toggleSelection: { onToggleSelection(project) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
}
