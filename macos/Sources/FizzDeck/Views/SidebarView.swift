import Foundation
import SwiftUI

enum SidebarLayout {
    static let collapsedKey = "fizzdeck.sidebarCollapsed"
    static let expandedWidth: CGFloat = 236
    static let collapsedWidth: CGFloat = 58
    static let outerInset: CGFloat = 9
    static let cornerRadius: CGFloat = FizzRadius.frame
}

struct SidebarView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let collapsed: Bool

    @State private var collapsedGroups: Set<String> = []
    @State private var disk: DiskCapacity?

    var body: some View {
        Group {
            if collapsed {
                rail
            } else {
                expanded
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: SidebarLayout.cornerRadius, style: .continuous)
                .fill(FizzTheme.sidebar)
        }
        .clipShape(RoundedRectangle(cornerRadius: SidebarLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SidebarLayout.cornerRadius, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
        .fizzAdaptiveShadow(.raised)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.standard), value: collapsed)
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

    private var expanded: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    searchButton
                    globalLinks

                    projectSections
                }
                .padding(.horizontal, 9)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            expandedFooter
        }
    }

    private var rail: some View {
        VStack(spacing: 6) {
            Button {
                store.toggleCommandPalette()
            } label: {
                FizzIcon(symbol: "magnifyingglass", size: FizzIconScale.nav)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 30)
                    .background(
                        FizzTheme.recessedFill,
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                            .strokeBorder(FizzTheme.stroke, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("搜索项目和动作（⌘K）")
            .accessibilityLabel("搜索")

            VStack(spacing: 2) {
                SidebarRailButton(
                    symbol: "house",
                    label: "工作台",
                    selected: store.destination.isDashboard,
                    showsDot: runningCount > 0
                ) {
                    store.openDashboard()
                }

                SidebarRailButton(
                    symbol: "square.grid.2x2",
                    label: "项目库",
                    selected: store.destination.isLibrary,
                    showsDot: false
                ) {
                    store.openLibrary()
                }

                SidebarRailButton(
                    symbol: "archivebox",
                    label: "可清理 \(Format.bytes(cleanupBytes))",
                    selected: store.destination.isCleanup,
                    showsDot: cleanupBytes > 0
                ) {
                    store.openCleanup()
                }
            }

            Rectangle()
                .fill(FizzTheme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(starredProjects) { project in
                        SidebarRailProjectButton(
                            project: project,
                            selected: store.selectedPath == project.path
                        ) {
                            store.selectedPath = project.path
                        }
                        .contextMenu {
                            projectMenu(project)
                        }
                    }

                    if !starredProjects.isEmpty && !railProjects.isEmpty {
                        Rectangle()
                            .fill(FizzTheme.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }

                    ForEach(railProjects) { project in
                        SidebarRailProjectButton(
                            project: project,
                            selected: store.selectedPath == project.path
                        ) {
                            store.selectedPath = project.path
                        }
                        .contextMenu {
                            projectMenu(project)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            SidebarRailSettingsButton()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var searchButton: some View {
        Button {
            store.toggleCommandPalette()
        } label: {
            HStack(spacing: 6) {
                FizzIcon(symbol: "magnifyingglass", size: FizzIconScale.nav)
                    .foregroundStyle(.secondary)

                Text("搜索")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("⌘K")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                FizzTheme.recessedFill,
                in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("搜索项目和动作（⌘K）")
        .accessibilityLabel("搜索")
    }

    private var globalLinks: some View {
        VStack(spacing: 1) {
            SidebarSignalRow(
                symbol: "house",
                title: "工作台",
                detail: runningCount > 0 ? "\(runningCount) 运行中" : nil,
                detailColor: .green,
                selected: store.destination.isDashboard
            ) {
                store.openDashboard()
            }

            SidebarSignalRow(
                symbol: "square.grid.2x2",
                title: "项目库",
                detail: "\(store.projects.count)",
                selected: store.destination.isLibrary
            ) {
                store.openLibrary()
            }

            SidebarSignalRow(
                symbol: "archivebox",
                title: "可清理",
                detail: Format.bytes(cleanupBytes),
                selected: store.destination.isCleanup
            ) {
                store.openCleanup()
            }
        }
    }

    private var projectSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !starredProjects.isEmpty {
                starredSection
            }

            if !runningProjects.isEmpty {
                runningSection
            }

            ForEach(groups) { group in
                groupSection(group)
            }
        }
    }

    private var starredSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(title: "星标") {
                FizzIcon(symbol: "star.fill", size: FizzIconScale.micro)
                    .foregroundStyle(.yellow)
            }

            ForEach(starredProjects) { project in
                projectRow(
                    project,
                    portText: project.port == .running ? project.run.map { ":\($0.port)" } : nil
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("星标项目")
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(title: "正在运行") {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
            }

            ForEach(runningProjects) { project in
                projectRow(
                    project,
                    portText: project.run.map { ":\($0.port)" }
                )
            }
        }
    }

    private func groupSection(_ group: SidebarGroup) -> some View {
        let isCollapsed = collapsedGroups.contains(group.name)

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Button {
                    store.openLibrary(LibraryQuery(group: group.name))
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ProjectGrouping.color(for: group.name).opacity(0.66))
                            .frame(width: 5, height: 5)

                        Text(group.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 9)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("在项目库中筛选「\(group.name)」")
                .accessibilityLabel("筛选 \(group.name) 分组")

                Button {
                    toggleGroup(group.name)
                } label: {
                    FizzIcon(symbol: "chevron.right", size: FizzIconScale.micro)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.name) 分组")
                .accessibilityValue(isCollapsed ? "已折叠" : "已展开")

                Button {
                    Task { await store.addRoot() }
                } label: {
                    FizzIcon(symbol: "plus", size: FizzIconScale.micro)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("添加项目目录")
                .accessibilityLabel("添加项目目录")
            }

            if !isCollapsed {
                ForEach(group.items) { project in
                    projectRow(project)
                }
            }
        }
    }

    private func projectRow(_ project: RepoProject, portText: String? = nil) -> some View {
        SidebarProjectRow(
            project: project,
            selected: store.selectedPath == project.path,
            portText: portText
        ) {
            store.selectedPath = project.path
        }
        .contextMenu {
            projectMenu(project)
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: RepoProject) -> some View {
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

    private var expandedFooter: some View {
        VStack(spacing: 4) {
            if let disk {
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
                                .frame(width: max(3, proxy.size.width * disk.usedFraction))
                        }
                    }
                    .frame(width: 40, height: 3)
                }
                .font(.system(size: 9.5).monospacedDigit())
                .padding(.horizontal, 8)
                .frame(height: 20)
                .help(store.scannedAt.map { "\(Format.relative($0))更新" } ?? "尚未扫描")
            }

            SidebarSettingsRow()
        }
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            Rectangle()
                .fill(FizzTheme.hairline)
                .frame(height: 1)
        }
    }

    private var runningProjects: [RepoProject] {
        store.projects
            .filter { $0.port == .running }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var runningCount: Int {
        runningProjects.count
    }

    private var cleanupBytes: Int64 {
        store.projects.reduce(0) { $0 + $1.cleanup.reusableBytes }
    }

    private var starredProjects: [RepoProject] {
        store.projects.filter(\.starred)
    }

    private var railProjects: [RepoProject] {
        store.projects.filter { !$0.starred }
    }

    private var groups: [SidebarGroup] {
        ProjectGrouping.ordered(store.projects.map(\.group)).compactMap { group in
            let items = store.projects.filter { $0.group == group }
            return items.isEmpty ? nil : SidebarGroup(name: group, items: items)
        }
    }

    private func toggleGroup(_ name: String) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            if collapsedGroups.contains(name) {
                collapsedGroups.remove(name)
            } else {
                collapsedGroups.insert(name)
            }
        }
    }

    private func revealSelection() {
        guard let group = store.selectedProject?.group,
              collapsedGroups.contains(group)
        else { return }

        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            _ = collapsedGroups.remove(group)
        }
    }
}

private struct SidebarSectionHeader<Marker: View>: View {
    let title: String
    @ViewBuilder let marker: () -> Marker

    var body: some View {
        HStack(spacing: 6) {
            marker()
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SidebarGroup: Identifiable {
    let name: String
    let items: [RepoProject]

    var id: String { name }
}

private struct SidebarSignalRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var detailColor: Color = .secondary
    var selected = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                FizzIcon(symbol: symbol, size: FizzIconScale.nav)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))

                Spacer(minLength: 6)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct SidebarProjectRow: View {
    let project: RepoProject
    let selected: Bool
    let portText: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ProjectBadgeIcon(project: project, size: 20, framed: false)

                Text(project.displayName)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let portText {
                    Text(portText)
                        .font(.system(size: 9.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 7)
            .frame(height: 27)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(project.displayName)
        .accessibilityLabel(project.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct SidebarRailButton: View {
    let symbol: String
    let label: String
    let selected: Bool
    let showsDot: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                FizzIcon(symbol: symbol, size: FizzIconScale.nav)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(width: 34, height: 30)
                    .background {
                        if selected || hovering {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                        }
                    }

                if showsDot {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct SidebarRailProjectButton: View {
    let project: RepoProject
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ProjectBadgeIcon(project: project, size: 20, framed: false)
                    .frame(width: 34, height: 28)
                    .background {
                        if selected || hovering {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                        }
                    }

                if project.port == .running {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 38, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(project.displayName)
        .accessibilityLabel(project.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct SidebarSettingsRow: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            HStack(spacing: 8) {
                FizzIcon(symbol: "gearshape", size: FizzIconScale.nav)
                    .frame(width: 16)

                Text("设置")
                    .font(.system(size: 12.5))

                Spacer(minLength: 0)

                Text("⌘,")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(0.55))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("打开设置（⌘,）")
        .accessibilityLabel("设置")
    }
}

private struct SidebarRailSettingsButton: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            FizzIcon(symbol: "gearshape", size: FizzIconScale.nav)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 30)
                .background {
                    if hovering {
                        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                            .fill(FizzTheme.selectedFill.opacity(0.55))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("打开设置（⌘,）")
        .accessibilityLabel("设置")
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
