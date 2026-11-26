import SwiftUI

struct ScanReportView: View {
    let report: DiscoveryReport
    let managedPaths: Set<String>
    @Binding var selected: Set<String>
    let onRescan: () -> Void

    @State private var toolFilter: DetectedTool?
    @State private var kindFilter: ProjectKind?

    private var availableTools: [(tool: DetectedTool, count: Int)] {
        DetectedTool.allCases.compactMap { tool in
            let count = report.projects.filter { $0.tools.contains(tool) }.count
            return count > 0 ? (tool, count) : nil
        }
    }

    private var availableKinds: [(kind: ProjectKind, count: Int)] {
        ProjectKind.allCases.compactMap { kind in
            let count = report.projects.filter { $0.kind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
    }

    private var filteredProjects: [DiscoveredProject] {
        report.projects.filter { project in
            if let toolFilter, !project.tools.contains(toolFilter) { return false }
            if let kindFilter, project.kind != kindFilter { return false }
            return true
        }
    }

    private var groupedProjects: [(kind: ProjectKind, items: [DiscoveredProject])] {
        ProjectKind.allCases.compactMap { kind in
            let items = filteredProjects.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterChips

            if !report.permissionDeniedPaths.isEmpty {
                permissionRecoveryCard
            }

            if report.reachedLimit {
                HStack(spacing: 6) {
                    FizzIcon(symbol: "info.circle", size: 12)
                        .foregroundStyle(.blue)
                    Text("已达到单次预览上限（300 个候选），建议缩小目录范围或先加入常用项目。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous))
            }

            HStack(spacing: 10) {
                Text("共发现 \(report.projects.count) 个项目 · 当前显示 \(filteredProjects.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("全选高置信") {
                    selected = ProjectDiscovery.defaultSelection(
                        projects: report.projects,
                        excluding: managedPaths,
                        highConfidenceOnly: true
                    )
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)

                Button("清空") {
                    selected.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(selected.isEmpty)
            }

            if groupedProjects.isEmpty {
                ContentUnavailableView(
                    "当前筛选下没有项目",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("切换或清除顶部筛选条件后再试。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedProjects, id: \.kind.id) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    FizzIcon(symbol: group.kind.symbol, size: 12)
                                        .foregroundStyle(group.kind.color)
                                    Text(group.kind.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("\(group.items.count)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                Divider()

                                ForEach(group.items) { candidate in
                                    candidateRow(candidate)
                                    if candidate.id != group.items.last?.id {
                                        Divider()
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                            .fizzCard(radius: FizzRadius.card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("识别工具")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                    .padding(.top, 4)

                FlowLayout(spacing: 6) {
                    chipButton(
                        title: "全部",
                        symbol: "sparkles",
                        tint: .secondary,
                        active: toolFilter == nil
                    ) {
                        toolFilter = nil
                    }

                    ForEach(DetectedTool.allCases) { tool in
                        let count = availableTools.first(where: { $0.tool == tool })?.count ?? 0
                        chipButton(
                            title: count > 0 ? "\(tool.title) \(count)" : tool.title,
                            symbol: tool.symbol,
                            tint: tool.tint,
                            active: toolFilter == tool,
                            dimmed: count == 0
                        ) {
                            toolFilter = toolFilter == tool ? nil : tool
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Text("识别类型")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                    .padding(.top, 4)

                FlowLayout(spacing: 6) {
                    chipButton(
                        title: "全部",
                        symbol: "square.grid.2x2",
                        tint: .secondary,
                        active: kindFilter == nil
                    ) {
                        kindFilter = nil
                    }

                    ForEach(ProjectKind.allCases) { kind in
                        let count = availableKinds.first(where: { $0.kind == kind })?.count ?? 0
                        chipButton(
                            title: count > 0 ? "\(kind.title) \(count)" : kind.title,
                            symbol: kind.symbol,
                            tint: kind.color,
                            active: kindFilter == kind,
                            dimmed: count == 0
                        ) {
                            kindFilter = kindFilter == kind ? nil : kind
                        }
                    }
                }
            }
        }
        .padding(12)
        .fizzCard(radius: FizzRadius.card)
    }

    private func chipButton(
        title: String,
        symbol: String,
        tint: Color,
        active: Bool,
        dimmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                FizzIcon(symbol: symbol, size: 10)
                Text(title)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Color.white : (dimmed ? Color.secondary.opacity(0.6) : tint))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                active ? tint : tint.opacity(dimmed ? 0.05 : 0.11),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "已选中" : "未选中")
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityRemoveTraits(active ? [] : .isSelected)
    }

    private var permissionRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "lock.shield", size: 14)
                    .foregroundStyle(.orange)
                Text("部分受保护目录未获读取权限（\(report.permissionDeniedPaths.count) 处）")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button("重新扫描", action: onRescan)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            Text(report.permissionDeniedPaths.map(PathTools.displayPath).joined(separator: " · "))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button("打开「文件和文件夹」设置") {
                    SystemPermissionService.openFilesAndFoldersSettings()
                }
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
                .controlSize(.small)

                Button("打开完整磁盘访问") {
                    SystemPermissionService.openFullDiskAccessSettings()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }

    private func candidateRow(_ candidate: DiscoveredProject) -> some View {
        let managed = managedPaths.contains(candidate.path)
        let isSelected = selected.contains(candidate.path)

        return HStack(spacing: 10) {
            FizzIcon(symbol: "folder.fill", size: 16)
                .foregroundStyle(managed ? .green : (isSelected ? FizzTheme.accent : candidate.kind.color))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.name)
                        .font(.system(size: 12.5, weight: .semibold))

                    if candidate.hasGit {
                        TagChip(text: "git", tint: .green, compact: true)
                    }

                    if !candidate.highConfidence {
                        TagChip(text: "弱标记", tint: .secondary, compact: true)
                    }

                    ForEach(candidate.tools) { tool in
                        TagChip(text: tool.shortTitle, tint: tool.tint, compact: true)
                    }
                }

                Text(PathTools.displayPath(candidate.path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            if managed {
                Label("已加入", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Toggle("", isOn: Binding(
                    get: { selected.contains(candidate.path) },
                    set: { isOn in
                        if isOn {
                            selected = ProjectDiscovery.selecting(candidate.path, in: selected)
                        } else {
                            selected.remove(candidate.path)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(candidate.name)
                .accessibilityHint("选择是否把 \(PathTools.displayPath(candidate.path)) 加入项目")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? FizzTheme.selectedFill.opacity(0.55) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !managed else { return }
            selected = ProjectDiscovery.toggling(candidate.path, in: selected)
        }
        .accessibilityLabel(candidate.name)
        .accessibilityValue(managed ? "已加入" : (isSelected ? "已选中" : "未选中"))
        .accessibilityElement(children: .contain)
    }
}
