import SwiftUI

struct HomeHeaderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let detail: String
    let mode: HomeViewMode
    var showsCoverPreview = true
    let sort: HomeSort
    let facets: HomeFacets
    let availableGroups: [String]
    let availableTools: [String]
    var availableFrameworks: [String] = []
    var selectedFramework: String? = nil
    let selectionMode: Bool
    let groupCount: (String) -> Int
    let colorCount: (TagColor) -> Int
    let toolCount: (String) -> Int
    var frameworkCount: (String) -> Int = { _ in 0 }
    let onSelectMode: (HomeViewMode) -> Void
    let onSelectSort: (HomeSort) -> Void
    let onSetGroup: (String?) -> Void
    let onSetColor: (TagColor?) -> Void
    let onSetTool: (String?) -> Void
    var onSetFramework: (String?) -> Void = { _ in }
    var extraActiveFilterCount: Int = 0
    let onClearFacets: () -> Void
    let onToggleSelection: () -> Void
    var onToggleCoverPreview: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FizzPageHeader(
                title: title,
                subtitle: detail,
                primaryAction: FizzActionButton(
                    title: selectionMode ? "完成选择" : "批量选择",
                    symbol: selectionMode ? "checkmark" : "checklist",
                    action: onToggleSelection
                )
            )

            HStack(spacing: FizzSpacing.row) {
                modePicker
                coverPreviewToggle
                filterMenu
            }
            .frame(height: FizzControlHeight.compact.rawValue)

            if facets.hasAny || selectedFramework != nil {
                activeFilterChips
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.standard),
            value: facets.hasAny || selectedFramework != nil
        )
    }

    private var modePicker: some View {
        FizzSegmentedCapsule(
            items: HomeViewMode.allCases,
            selection: Binding(get: { mode }, set: { onSelectMode($0) }),
            height: .compact,
            keyboardNavigation: true
        ) { item, _ in
            FizzIcon(.sm, symbol: item.symbol)
                .help(item.title)
                .accessibilityLabel(item.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局")
    }

    private var coverPreviewToggle: some View {
        Toggle(
            isOn: Binding(
                get: { showsCoverPreview },
                set: { _ in onToggleCoverPreview() }
            )
        ) {
            Text("封面")
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .help(showsCoverPreview ? "隐藏封面预览" : "显示封面预览")
        .accessibilityLabel("显示封面预览")
        .accessibilityValue(showsCoverPreview ? "开启" : "关闭")
        .fizzKeyboardAction(action: onToggleCoverPreview)
    }

    private var filterMenu: some View {
        FizzMenuButton(title: "排序与筛选", symbol: "line.3.horizontal.decrease") {
            Section("排序") {
                ForEach(HomeSort.allCases) { item in
                    Button {
                        onSelectSort(item)
                    } label: {
                        Label(item.title, systemImage: item == sort ? "checkmark" : item.symbol)
                    }
                }
            }

            Menu {
                Button {
                    onSetGroup(nil)
                } label: {
                    Label(
                        "全部分组",
                        systemImage: facets.group == nil ? "checkmark" : "square.grid.2x2"
                    )
                }

                Divider()

                ForEach(availableGroups, id: \.self) { group in
                    Button {
                        onSetGroup(group)
                    } label: {
                        Label(
                            "\(group) · \(groupCount(group))",
                            systemImage: facets.group == group ? "checkmark" : "circle.fill"
                        )
                    }
                }
            } label: {
                Label(
                    facets.group.map { "分组 · \($0)" } ?? "分组",
                    systemImage: "square.grid.2x2"
                )
            }
            .disabled(availableGroups.isEmpty)

            Menu {
                Button {
                    onSetColor(nil)
                } label: {
                    Label("全部颜色", systemImage: facets.color == nil ? "checkmark" : "circle")
                }

                Divider()

                ForEach(TagColor.allCases) { color in
                    Button {
                        onSetColor(color)
                    } label: {
                        Label(
                            "\(color.label) · \(colorCount(color))",
                            systemImage: facets.color == color ? "checkmark" : "circle.fill"
                        )
                    }
                }
            } label: {
                Label(
                    facets.color.map { "颜色 · \($0.label)" } ?? "颜色",
                    systemImage: "paintpalette"
                )
            }

            Menu {
                Button {
                    onSetTool(nil)
                } label: {
                    Label("全部工具", systemImage: facets.tool == nil ? "checkmark" : "sparkles")
                }

                Divider()

                ForEach(availableTools, id: \.self) { tool in
                    Button {
                        onSetTool(tool)
                    } label: {
                        Label(
                            "\(HomeDashboardModel.toolTitle(tool)) · \(toolCount(tool))",
                            systemImage: facets.tool == tool ? "checkmark" : HomeDashboardModel.toolSymbol(tool)
                        )
                    }
                }
            } label: {
                Label(
                    facets.tool.map { "AI · \(HomeDashboardModel.toolTitle($0))" } ?? "AI 工具",
                    systemImage: "sparkles"
                )
            }
            .disabled(availableTools.isEmpty)

            if !availableFrameworks.isEmpty {
                Menu {
                    Button {
                        onSetFramework(nil)
                    } label: {
                        Label(
                            "全部框架",
                            systemImage: selectedFramework == nil ? "checkmark" : "chevron.left.forwardslash.chevron.right"
                        )
                    }

                    Divider()

                    ForEach(availableFrameworks, id: \.self) { framework in
                        Button {
                            onSetFramework(framework)
                        } label: {
                            Label(
                                "\(framework) · \(frameworkCount(framework))",
                                systemImage: selectedFramework == framework ? "checkmark" : "tag"
                            )
                        }
                    }
                } label: {
                    Label(
                        selectedFramework.map { "框架 · \($0)" } ?? "框架",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }
            }

            if facets.hasAny || selectedFramework != nil || extraActiveFilterCount > 0 {
                Divider()
                Button(role: .destructive) {
                    onClearFacets()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var activeFilterChips: some View {
        HStack(spacing: FizzSpacing.row) {
            if let group = facets.group {
                ActiveFilterChip(
                    text: group,
                    tint: ProjectGrouping.color(for: group)
                ) {
                    onSetGroup(nil)
                }
            }
            if let color = facets.color {
                ActiveFilterChip(text: color.label, tint: color.color) {
                    onSetColor(nil)
                }
            }
            if let tool = facets.tool {
                ActiveFilterChip(text: HomeDashboardModel.toolTitle(tool), tint: Color.secondary) {
                    onSetTool(nil)
                }
            }
            if let selectedFramework {
                ActiveFilterChip(text: selectedFramework, tint: Color.secondary) {
                    onSetFramework(nil)
                }
            }

            FizzActionButton(title: "清除", height: .compact, action: onClearFacets)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("活动筛选")
    }
}

private struct ActiveFilterChip: View {
    let text: String
    let tint: Color
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(text)
                    .font(FizzTypography.micro)
                    .lineLimit(1)
                FizzIcon(.xs, symbol: "xmark")
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: FizzControlHeight.compact.rawValue)
            .background(
                hovering ? FizzTheme.selectedFill : FizzTheme.mutedFill,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("移除 \(text) 筛选")
        .accessibilityLabel("移除 \(text) 筛选")
    }
}
