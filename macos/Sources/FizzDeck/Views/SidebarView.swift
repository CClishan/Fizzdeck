import Foundation
import SwiftUI

enum SidebarLayout {
    static let collapsedKey = "fizzdeck.sidebarCollapsed"
    static let expandedWidth: CGFloat = 236
    static let collapsedWidth: CGFloat = 58
    static let outerInset: CGFloat = 9
    static let cornerRadius: CGFloat = FizzRadius.frame
}

private let sidebarLabelInk = Color.primary.opacity(0.78)
private let sidebarDetailInk = Color.primary.opacity(0.64)

struct SidebarView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    let collapsed: Bool

    @State private var collapsedGroups: Set<String> = []
    @State private var disk: DiskCapacity?
    @Namespace private var selectionNamespace

    var body: some View {
        Group {
            if collapsed {
                rail
            } else {
                expanded
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: SidebarLayout.cornerRadius, style: .continuous))
        .glassEffect(
            .regular,
            in: .rect(cornerRadius: SidebarLayout.cornerRadius, style: .continuous)
        )
        .fizzAdaptiveShadow(.subtle)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.standard), value: collapsed)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: store.destination)
        .task {
            disk = DiskProbe.current()
            while !Task.isCancelled {
                await store.refreshActiveAISessions()
                try? await Task.sleep(for: .seconds(15))
            }
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
                FizzIcon(.sm, symbol: "magnifyingglass")
                    .foregroundStyle(sidebarLabelInk)
                    .frame(width: 36, height: 30)
                    .background(
                        FizzTheme.mutedFill,
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                            .strokeBorder(FizzTheme.stroke, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(FizzL10n.text("搜索项目和动作（⌘K）", "Search projects and actions (⌘K)"))
            .accessibilityLabel(FizzL10n.text("搜索", "Search"))

            VStack(spacing: 2) {
                SidebarRailButton(
                    symbol: "house",
                    label: FizzL10n.text("工作台", "Workbench"),
                    selected: store.destination.isDashboard,
                    showsDot: runningCount > 0,
                    selectionNamespace: selectionNamespace
                ) {
                    store.openDashboard()
                }

                SidebarRailButton(
                    symbol: "bubble.left.and.bubble.right",
                    label: FizzCopy.conversationsNavTitle,
                    selected: store.destination.isConversations,
                    showsDot: !store.activeAIProjectPaths.isEmpty,
                    selectionNamespace: selectionNamespace
                ) {
                    store.openConversations()
                }

                SidebarRailButton(
                    symbol: "square.grid.2x2",
                    label: FizzL10n.text("项目库", "Library"),
                    selected: store.destination.isLibrary,
                    showsDot: false,
                    selectionNamespace: selectionNamespace
                ) {
                    store.openLibrary()
                }

                SidebarRailButton(
                    symbol: "stethoscope",
                    label: store.focusedDoctorIssueCount > 0 ? FizzL10n.text("体检（\(store.focusedDoctorIssueCount) 个问题）", "Doctor (\(SessionSummaryText.englishCount(store.focusedDoctorIssueCount, "issue")))") : FizzL10n.text("体检", "Doctor"),
                    selected: store.destination.isCleanup,
                    showsDot: store.focusedDoctorIssueCount > 0,
                    selectionNamespace: selectionNamespace
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
                    ForEach(focusedProjects) { project in
                        SidebarRailProjectButton(
                            project: project,
                            selected: store.selectedPath == project.path,
                            selectionNamespace: selectionNamespace
                        ) {
                            store.selectedPath = project.path
                        }
                        .contextMenu {
                            projectMenu(project)
                        }
                    }

                    if !focusedProjects.isEmpty && !railProjects.isEmpty {
                        Rectangle()
                            .fill(FizzTheme.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }

                    ForEach(railProjects) { project in
                        SidebarRailProjectButton(
                            project: project,
                            selected: store.selectedPath == project.path,
                            selectionNamespace: selectionNamespace
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
                FizzIcon(.sm, symbol: "magnifyingglass")
                    .foregroundStyle(sidebarLabelInk)

                Text(FizzL10n.text("搜索", "Search"))
                    .font(FizzTypography.font(12))
                    .foregroundStyle(sidebarLabelInk)

                Spacer(minLength: 4)

                Text("⌘K")
                    .font(FizzTypography.micro(.regular))
                    .foregroundStyle(sidebarDetailInk)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                FizzTheme.mutedFill,
                in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(FizzL10n.text("搜索项目和动作（⌘K）", "Search projects and actions (⌘K)"))
        .accessibilityLabel(FizzL10n.text("搜索", "Search"))
    }

    private var globalLinks: some View {
        VStack(spacing: 1) {
            SidebarSignalRow(
                symbol: "house",
                title: FizzL10n.text("工作台", "Workbench"),
                detail: runningCount > 0 ? FizzL10n.text("\(runningCount) 运行中", "\(runningCount) running") : nil,
                selected: store.destination.isDashboard,
                selectionNamespace: selectionNamespace
            ) {
                store.openDashboard()
            }

            SidebarSignalRow(
                symbol: "bubble.left.and.bubble.right",
                title: FizzCopy.conversationsNavTitle,
                detail: store.activeAIProjectPaths.isEmpty ? nil : FizzL10n.text("\(store.activeAIProjectPaths.count) 进行中", "\(store.activeAIProjectPaths.count) active"),
                selected: store.destination.isConversations,
                selectionNamespace: selectionNamespace
            ) {
                store.openConversations()
            }

            SidebarSignalRow(
                symbol: "square.grid.2x2",
                title: FizzL10n.text("项目库", "Library"),
                detail: "\(store.projects.count)",
                selected: store.destination.isLibrary,
                selectionNamespace: selectionNamespace
            ) {
                store.openLibrary()
            }

            SidebarSignalRow(
                symbol: "stethoscope",
                title: FizzL10n.text("体检", "Doctor"),
                detail: store.focusedDoctorIssueCount > 0
                    ? "\(store.focusedDoctorIssueCount)"
                    : (cleanupBytes > 0 ? Format.bytes(cleanupBytes) : FizzL10n.text("良好", "Healthy")),
                selected: store.destination.isCleanup,
                selectionNamespace: selectionNamespace
            ) {
                store.openCleanup()
            }
        }
    }

    private var projectSections: some View {
        let partition = focusPartition
        return VStack(alignment: .leading, spacing: 12) {
            if !partition.focused.isEmpty {
                focusSection(partition)
            }

            if !runningProjects.isEmpty || !activeAIProjects.isEmpty {
                runningSection
            }

            ForEach(groups) { group in
                groupSection(group)
            }
        }
    }

    private func focusSection(_ partition: FocusPartition) -> some View {
        let manualEntries = partition.focused.filter { $0.reason == .manual }
        let autoEntries = partition.focused.filter { $0.reason == .recentActivity }
        let sectionTitle = FizzCopy.focusSectionTitle(copyMode)

        return VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(title: sectionTitle) {
                FizzIcon(.xs, symbol: copyMode == .plain ? "pin.fill" : "star.fill")
                    .foregroundStyle(sidebarLabelInk)
            }

            ForEach(manualEntries) { entry in
                focusRow(entry.project)
            }

            if !autoEntries.isEmpty {
                Text(FizzL10n.text("7 天内活跃（自动）", "Active in the last 7 days (auto)"))
                    .font(FizzTypography.micro(.regular))
                    .foregroundStyle(sidebarDetailInk)
                    .padding(.leading, 9)
                    .padding(.top, manualEntries.isEmpty ? 2 : 5)
                    .padding(.bottom, 1)

                ForEach(autoEntries) { entry in
                    focusRow(entry.project)
                }
            }

            if partition.overflowActiveCount > 0 {
                Button {
                    store.openLibrary()
                } label: {
                    Text(FizzL10n.text("还有 \(partition.overflowActiveCount) 个活跃项目", "\(partition.overflowActiveCount) more active \(partition.overflowActiveCount == 1 ? "project" : "projects")"))
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(sidebarLabelInk)
                        .padding(.horizontal, 9)
                        .frame(height: 22, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FizzL10n.text("\(sectionTitle)项目", "\(sectionTitle) projects"))
    }

    private func focusRow(_ project: RepoProject) -> some View {
        let dot = ProjectFocusPolicy.statusDot(
            for: project,
            testRuns: actions.testRunsSnapshot,
            activeAIProjectPaths: store.activeAIProjectPaths
        )
        return projectRow(
            project,
            portText: project.port == .running ? project.run.map { ":\($0.port)" } : nil,
            statusDot: dot
        )
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(title: FizzL10n.text("正在运行", "Running")) {
                RunningPulseDot()
            }

            ForEach(runningProjects) { project in
                projectRow(
                    project,
                    portText: project.run.map { ":\($0.port)" },
                    tagText: FizzCopy.runningServicesTag
                )
            }

            ForEach(activeAIProjects) { project in
                projectRow(
                    project,
                    tagText: FizzCopy.runningAITag,
                    statusDot: .aiWorking
                )
            }
        }
    }

    private func groupSection(_ group: SidebarGroup) -> some View {
        let isCollapsed = collapsedGroups.contains(group.name)
        let title = ProjectGrouping.title(for: group.name)

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Button {
                    store.openLibrary(LibraryQuery(group: group.name))
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ProjectGrouping.color(for: group.name).opacity(0.66))
                            .frame(width: 5, height: 5)

                        Text(title)
                            .font(FizzTypography.mono(.medium))
                            .foregroundStyle(sidebarLabelInk)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 9)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(FizzL10n.text("在项目库中筛选「\(title)」", "Filter Library by “\(title)”"))
                .accessibilityLabel(FizzL10n.text("筛选 \(title) 分组", "Filter by group: \(title)"))

                Button {
                    toggleGroup(group.name)
                } label: {
                    FizzIcon(.xs, symbol: "chevron.right")
                        .foregroundStyle(sidebarDetailInk)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FizzL10n.text("\(title) 分组", "\(title) group"))
                .accessibilityValue(isCollapsed ? FizzL10n.text("已折叠", "Collapsed") : FizzL10n.text("已展开", "Expanded"))

                Button {
                    Task { await store.addRoot() }
                } label: {
                    FizzIcon(.xs, symbol: "plus")
                        .foregroundStyle(sidebarLabelInk)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(FizzL10n.text("添加项目目录", "Add project folder"))
                .accessibilityLabel(FizzL10n.text("添加项目目录", "Add project folder"))
            }

            if !isCollapsed {
                ForEach(group.items) { project in
                    projectRow(project)
                }
            }
        }
    }

    private func projectRow(
        _ project: RepoProject,
        portText: String? = nil,
        tagText: String? = nil,
        statusDot: ProjectStatusDot = .none
    ) -> some View {
        SidebarProjectRow(
            project: project,
            selected: store.selectedPath == project.path,
            portText: portText,
            tagText: tagText,
            statusDot: statusDot,
            copyMode: copyMode,
            selectionNamespace: selectionNamespace
        ) {
            store.selectedPath = project.path
        }
        .contextMenu {
            projectMenu(project)
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: RepoProject) -> some View {
        Button(project.starred
            ? (copyMode == .plain ? FizzL10n.text("取消关注", "Unfollow") : FizzL10n.text("取消星标", "Unstar"))
            : (copyMode == .plain ? FizzL10n.text("加入关注", "Follow") : FizzL10n.text("设为星标", "Star"))
        ) {
            store.toggleStar(project)
        }

        Button(FizzL10n.text("复制接力卡", "Copy Handoff card")) {
            let result = HandoffCardBuilder.build(project: project, copyMode: copyMode)
            SystemActions.copy(result.markdown)
            ToastCenter.shared.show(
                FizzL10n.text("接力卡已复制", "Handoff card copied"),
                symbol: "doc.on.clipboard.fill",
                tint: Color.secondary,
                subtitle: FizzL10n.text("\(result.characterCount) 字", SessionSummaryText.englishCount(result.characterCount, "character"))
            )
        }

        Menu(FizzL10n.text("标签颜色", "Tag color")) {
            Button(FizzL10n.text("无标签", "No tag")) { store.setColor(nil, for: project) }
            ForEach(TagColor.allCases) { color in
                Button(color.label) { store.setColor(color, for: project) }
            }
        }

        ProjectGroupingMenu(project: project)
        Divider()
        ProjectQuickActions(project: project)
        Divider()

        Button(FizzL10n.text("从看板移除", "Remove from board")) {
            Task { await store.removeFromBoard(project) }
        }
    }

    private var expandedFooter: some View {
        VStack(spacing: 4) {
            if let disk {
                HStack(spacing: 5) {
                    Text(Format.bytes(disk.free))
                        .font(FizzTypography.font(9.5, weight: .medium))
                    Text(FizzL10n.text("可用", "free"))
                        .foregroundStyle(sidebarDetailInk)

                    Spacer(minLength: 8)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(FizzTheme.hairline)
                            Capsule()
                                .fill(Color.secondary.opacity(0.65))
                                .frame(width: max(3, proxy.size.width * disk.usedFraction))
                        }
                    }
                    .frame(width: 40, height: 3)
                }
                .font(FizzTypography.font(9.5))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .help(store.scannedAt.map { FizzL10n.text("\(Format.relative($0))更新", "Updated \(Format.relative($0))") } ?? FizzL10n.text("尚未扫描", "Not scanned yet"))
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

    private var activeAIProjects: [RepoProject] {
        store.projects
            .filter { store.activeAIProjectPaths.contains($0.path) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var focusPartition: FocusPartition {
        ProjectFocusPolicy.partition(projects: store.projects)
    }

    private var focusedProjects: [RepoProject] {
        focusPartition.focused.map(\.project)
    }

    private var railProjects: [RepoProject] {
        let focusedPaths = focusPartition.focusedPaths
        return store.projects.filter { !focusedPaths.contains($0.path) }
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
                .font(FizzTypography.mono(.medium))
                .foregroundStyle(sidebarLabelInk)
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
    var selected = false
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                FizzIcon(.sm, symbol: symbol)
                    .frame(width: 16)

                Text(title)
                    .font(FizzTypography.body(selected ? .medium : .regular))

                Spacer(minLength: 6)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(FizzTypography.micro)
                        .foregroundStyle(sidebarLabelInk)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? Color.primary : sidebarLabelInk)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill)
                        .matchedGeometryEffect(
                            id: "sidebar-expanded-selection",
                            in: selectionNamespace
                        )
                } else if hovering {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(0.55))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
        .fizzKeyboardAction(action: action)
    }
}

private struct SidebarProjectRow: View {
    let project: RepoProject
    let selected: Bool
    let portText: String?
    var tagText: String? = nil
    var statusDot: ProjectStatusDot = .none
    var copyMode: CopyMode = .plain
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ProjectAccentDot(path: project.path)

                Text(project.displayName)
                    .font(FizzTypography.body(selected ? .medium : .regular))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if let tagText {
                    Text(tagText)
                        .font(FizzTypography.font(9, weight: .medium))
                        .foregroundStyle(sidebarLabelInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(FizzTheme.mutedFill, in: Capsule())
                }

                if let portText {
                    Text(portText)
                        .font(FizzTypography.font(9.5))
                        .foregroundStyle(sidebarDetailInk)
                }

                dotIndicator
            }
            .foregroundStyle(selected ? Color.primary : sidebarLabelInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minHeight: 27)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill)
                        .matchedGeometryEffect(
                            id: "sidebar-expanded-selection",
                            in: selectionNamespace
                        )
                } else if hovering {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(0.55))
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

    @ViewBuilder
    private var dotIndicator: some View {
        switch statusDot {
        case .aiWorking:
            RunningPulseDot()
                .help(FizzL10n.text("AI 正在干活", "AI is working"))
        case .broken:
            FizzStatusDot(tint: FizzTheme.statusDanger)
                .help(FizzL10n.text("跑不起来或上次对话报错", "Run failed or the last conversation ended with an error"))
        case .unsaved:
            FizzStatusDot(tint: FizzTheme.statusWarning)
                .help(FizzCopy.uncommittedChanges(mode: copyMode).text)
        case .none:
            EmptyView()
        }
    }
}

private struct SidebarRailButton: View {
    let symbol: String
    let label: String
    let selected: Bool
    let showsDot: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                FizzIcon(.sm, symbol: symbol)
                    .foregroundStyle(selected ? Color.primary : sidebarLabelInk)
                    .frame(width: 34, height: 30)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .fill(FizzTheme.selectedFill)
                                .matchedGeometryEffect(
                                    id: "sidebar-rail-selection",
                                    in: selectionNamespace
                                )
                        } else if hovering {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .fill(FizzTheme.selectedFill.opacity(0.55))
                        }
                    }

                if showsDot {
                    RunningPulseDot()
                        .padding(2)
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
        .fizzKeyboardAction(action: action)
    }
}

private struct SidebarRailProjectButton: View {
    let project: RepoProject
    let selected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ProjectBadgeIcon(project: project, size: 20, framed: false)
                    .frame(width: 34, height: 28)
                    .overlay(alignment: .bottomLeading) {
                        ProjectAccentDot(path: project.path).padding(2)
                    }
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .fill(FizzTheme.selectedFill)
                                .matchedGeometryEffect(
                                    id: "sidebar-rail-project-selection",
                                    in: selectionNamespace
                                )
                        } else if hovering {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .fill(FizzTheme.selectedFill.opacity(0.55))
                        }
                    }

                if project.port == .running {
                    RunningPulseDot()
                        .padding(2)
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
                FizzIcon(.sm, symbol: "gearshape")
                    .frame(width: 16)

                Text(FizzL10n.text("设置", "Settings"))
                    .font(FizzTypography.body)

                Spacer(minLength: 0)

                Text("⌘,")
                    .font(FizzTypography.font(9.5))
                    .foregroundStyle(sidebarDetailInk)
            }
            .foregroundStyle(sidebarLabelInk)
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
        .help(FizzL10n.text("打开设置（⌘,）", "Open Settings (⌘,)"))
        .accessibilityLabel(FizzL10n.text("设置", "Settings"))
    }
}

private struct SidebarRailSettingsButton: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            FizzIcon(.sm, symbol: "gearshape")
                .foregroundStyle(sidebarLabelInk)
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
        .help(FizzL10n.text("打开设置（⌘,）", "Open Settings (⌘,)"))
        .accessibilityLabel(FizzL10n.text("设置", "Settings"))
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
