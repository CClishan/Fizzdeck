import Foundation
import SwiftUI

struct SidebarView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedGroups: Set<String> = []
    @State private var disk: DiskCapacity?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    brand
                    navigation
                    projectGroups
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .background(FizzTheme.sidebar.ignoresSafeArea())
        .task {
            disk = DiskProbe.current()
        }
        .onAppear {
            revealSelection()
        }
        .onChange(of: store.selectedProject?.path) {
            revealSelection()
        }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            FizzLogo(size: 28)

            Text("FizzDeck")
                .font(.system(size: 16, weight: .semibold))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private var navigation: some View {
        VStack(spacing: 1) {
            SidebarNavRow(
                title: "总览",
                symbol: "square.grid.2x2",
                selected: store.selectedHomeFilter == .all
            ) {
                store.selectedPath = RepositoryStore.homeSelection
            }

            ForEach(HomeFilter.allCases.filter { $0 != .all }) { filter in
                SidebarNavRow(
                    title: filter.title,
                    symbol: filter.symbol,
                    selected: store.selectedHomeFilter == filter
                ) {
                    store.selectedPath = RepositoryStore.selection(for: filter)
                }
            }
        }
    }

    private var projectGroups: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(groups) { group in
                SidebarGroupHeader(
                    group: group,
                    expanded: expandedGroups.contains(group.name)
                ) {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                        if expandedGroups.contains(group.name) {
                            expandedGroups.removeAll()
                        } else {
                            expandedGroups = [group.name]
                        }
                    }
                }

                if expandedGroups.contains(group.name) {
                    ForEach(group.items) { project in
                        SidebarProjectRow(
                            project: project,
                            selected: store.selectedPath == project.path
                        ) {
                            store.selectedPath = project.path
                        }
                        .contextMenu {
                            Button(project.starred ? "取消星标" : "设为星标") {
                                store.toggleStar(project)
                            }
                            Menu("标签颜色") {
                                Button("无标签") { store.setColor(nil, for: project) }
                                ForEach(TagColor.allCases) { color in
                                    Button(color.label) { store.setColor(color, for: project) }
                                }
                            }
                            ProjectGroupingMenu(project: project)
                            Divider()
                            ProjectQuickActions(project: project)
                            Divider()
                            Button("从看板移除") {
                                Task { await store.removeFromBoard(project) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Group {
                if store.phase == .scanning {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在扫描")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                } else if let disk {
                    HStack(spacing: 5) {
                        Text(Format.bytes(disk.free))
                            .fontWeight(.medium)
                        Text("可用")
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 8)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(FizzTheme.hairline)
                                Capsule()
                                    .fill(FizzTheme.accent.opacity(0.74))
                                    .frame(width: max(4, proxy.size.width * disk.usedFraction))
                            }
                        }
                        .frame(width: 48, height: 4)
                    }
                    .help(store.scannedAt.map { "\(Format.relative($0))更新" } ?? "尚未扫描")
                } else {
                    HStack {
                        Text("尚未扫描")
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(.system(size: 10.5).monospacedDigit())
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            SidebarSettingsRow()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var groups: [SidebarGroup] {
        ProjectGrouping.ordered(store.filteredProjects.map(\.group)).compactMap { group in
            let items = store.filteredProjects.filter { $0.group == group }
            return items.isEmpty ? nil : SidebarGroup(name: group, items: items)
        }
    }

    private func revealSelection() {
        guard let group = store.selectedProject?.group else { return }
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            expandedGroups = [group]
        }
    }
}

private struct SidebarGroup: Identifiable {
    let name: String
    let items: [RepoProject]

    var id: String { name }
}

private struct SidebarNavRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                FizzIcon(symbol: symbol, size: 13)
                    .frame(width: 17)

                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

private struct SidebarGroupHeader: View {
    let group: SidebarGroup
    let expanded: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ProjectGrouping.color(for: group.name).opacity(0.66))
                    .frame(width: 5, height: 5)

                Text(group.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                FizzIcon(symbol: "chevron.right", size: 8)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SidebarSettingsRow: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            HStack(spacing: 9) {
                FizzIcon(symbol: "slider.horizontal.3", size: 13)
                    .frame(width: 17)

                Text("设置")
                    .font(.system(size: 13))

                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(0.55))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("打开设置（⌘,）")
        .accessibilityLabel("设置")
    }
}

private struct SidebarProjectRow: View {
    let project: RepoProject
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(project.displayName)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if project.port == .running {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.leading, 22)
            .padding(.trailing, 9)
            .frame(height: 27)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct DiskCapacity {
    let free: Int64
    let total: Int64

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(free) / Double(total)))
    }
}

private enum DiskProbe {
    static func current() -> DiskCapacity? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]),
        let free = values.volumeAvailableCapacityForImportantUsage,
        let total = values.volumeTotalCapacity
        else { return nil }
        return DiskCapacity(free: free, total: Int64(total))
    }
}
