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
    var availableFrameworks: [HomeDashboardModel.FrameworkChoice] = []
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
                    title: selectionMode ? FizzL10n.text("完成选择", "Done") : FizzL10n.text("批量选择", "Select projects"),
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
        .accessibilityLabel(FizzL10n.text("布局", "Layout"))
    }

    private var coverPreviewToggle: some View {
        Toggle(
            isOn: Binding(
                get: { showsCoverPreview },
                set: { _ in onToggleCoverPreview() }
            )
        ) {
            Text(FizzL10n.text("封面", "Covers"))
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .help(showsCoverPreview ? FizzL10n.text("隐藏封面预览", "Hide cover previews") : FizzL10n.text("显示封面预览", "Show cover previews"))
        .accessibilityLabel(FizzL10n.text("显示封面预览", "Show cover previews"))
        .accessibilityValue(showsCoverPreview ? FizzL10n.text("开启", "On") : FizzL10n.text("关闭", "Off"))
        .fizzKeyboardAction(action: onToggleCoverPreview)
    }

    private var selectedFrameworkTitle: String? {
        selectedFramework.map { key in availableFrameworks.first { $0.id == key }?.title ?? key }
    }

    private var filterMenu: some View {
        FizzMenuButton(title: FizzL10n.text("排序与筛选", "Sort and filter"), symbol: "line.3.horizontal.decrease") {
            Section(FizzL10n.text("排序", "Sort by")) {
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
                        FizzL10n.text("全部分组", "All groups"),
                        systemImage: facets.group == nil ? "checkmark" : "square.grid.2x2"
                    )
                }

                Divider()

                ForEach(availableGroups, id: \.self) { group in
                    Button {
                        onSetGroup(group)
                    } label: {
                        Label(
                            "\(ProjectGrouping.title(for: group)) · \(groupCount(group))",
                            systemImage: facets.group == group ? "checkmark" : "circle.fill"
                        )
                    }
                }
            } label: {
                Label(
                    facets.group.map { ProjectGrouping.title(for: $0) }.map { FizzL10n.text("分组 · \($0)", "Group · \($0)") } ?? FizzL10n.text("分组", "Group"),
                    systemImage: "square.grid.2x2"
                )
            }
            .disabled(availableGroups.isEmpty)

            Menu {
                Button {
                    onSetColor(nil)
                } label: {
                    Label(FizzL10n.text("全部颜色", "All colors"), systemImage: facets.color == nil ? "checkmark" : "circle")
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
                    facets.color.map { FizzL10n.text("颜色 · \($0.label)", "Color · \($0.label)") } ?? FizzL10n.text("颜色", "Color"),
                    systemImage: "paintpalette"
                )
            }

            Menu {
                Button {
                    onSetTool(nil)
                } label: {
                    Label(FizzL10n.text("全部工具", "All tools"), systemImage: facets.tool == nil ? "checkmark" : "sparkles")
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
                    facets.tool.map { "AI · \(HomeDashboardModel.toolTitle($0))" } ?? FizzL10n.text("AI 工具", "AI tools"),
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
                            FizzL10n.text("全部框架", "All frameworks"),
                            systemImage: selectedFramework == nil ? "checkmark" : "chevron.left.forwardslash.chevron.right"
                        )
                    }

                    Divider()

                    ForEach(availableFrameworks) { framework in
                        Button {
                            onSetFramework(framework.id)
                        } label: {
                            Label(
                                "\(framework.title) · \(frameworkCount(framework.id))",
                                systemImage: selectedFramework == framework.id ? "checkmark" : "tag"
                            )
                        }
                    }
                } label: {
                    Label(
                        selectedFrameworkTitle.map { FizzL10n.text("框架 · \($0)", "Framework · \($0)") } ?? FizzL10n.text("框架", "Framework"),
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }
            }

            if facets.hasAny || selectedFramework != nil || extraActiveFilterCount > 0 {
                Divider()
                Button(role: .destructive) {
                    onClearFacets()
                } label: {
                    Label(FizzL10n.text("清除筛选", "Clear filters"), systemImage: "xmark.circle")
                }
            }
        }
    }

    private var activeFilterChips: some View {
        FlowLayout(spacing: FizzSpacing.row) {
            if let group = facets.group {
                ActiveFilterChip(
                    text: ProjectGrouping.title(for: group),
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
            if let selectedFrameworkTitle {
                ActiveFilterChip(text: selectedFrameworkTitle, tint: Color.secondary) {
                    onSetFramework(nil)
                }
            }

            FizzActionButton(title: FizzL10n.text("清除", "Clear"), height: .compact, action: onClearFacets)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FizzL10n.text("活动筛选", "Active filters"))
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
        .help(FizzL10n.text("移除 \(text) 筛选", "Remove \(text) filter"))
        .accessibilityLabel(FizzL10n.text("移除 \(text) 筛选", "Remove \(text) filter"))
    }
}
