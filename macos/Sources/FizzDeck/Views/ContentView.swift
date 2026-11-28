import OSLog
import SwiftUI

struct ContentView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SidebarLayout.collapsedKey) private var sidebarCollapsed = false

    @State private var pendingRoute: AppRouting.ProjectRequest?
    @State private var handoff: RepoProject?
    @State private var showingWeeklyRecap = false
    private static let routeLog = Logger(subsystem: "com.a003.fizzdeck", category: "routing")

    var body: some View {
        Group {
            if store.isFirstRunPresented {
                FirstRunScanView()
            } else {
                ZStack {
                    FizzBackground()

                    HStack(spacing: 0) {
                        SidebarView(collapsed: sidebarCollapsed)
                            .frame(
                                width: sidebarCollapsed
                                    ? SidebarLayout.collapsedWidth
                                    : SidebarLayout.expandedWidth
                            )
                            .padding(.leading, SidebarLayout.outerInset)
                            .padding(.vertical, SidebarLayout.outerInset)
                            .zIndex(1)

                        detail
                    }
                    .animation(
                        FizzMotion.resolved(reduceMotion, FizzMotion.standard),
                        value: sidebarCollapsed
                    )
                }
                .overlay(alignment: .topTrailing) {
                    ToastOverlayView(center: ToastCenter.shared)
                        .padding(.top, 14)
                        .padding(.trailing, 20)
                }
            }
        }
        .toolbar(removing: .title)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if !store.isFirstRunPresented {
                    Button {
                        sidebarCollapsed.toggle()
                    } label: {
                        FizzIcon(.md, symbol: "sidebar.left")
                    }
                    .help(sidebarCollapsed ? FizzL10n.text("展开侧栏", "Show sidebar") : FizzL10n.text("折叠侧栏", "Hide sidebar"))
                    .accessibilityLabel(sidebarCollapsed ? FizzL10n.text("展开侧栏", "Show sidebar") : FizzL10n.text("折叠侧栏", "Hide sidebar"))
                }

                if let project = store.selectedProject {
                    Button {
                        store.openDashboard()
                    } label: {
                        FizzIcon(.md, symbol: "chevron.left")
                    }
                    .help(FizzL10n.text("返回工作台", "Back to Workbench"))
                    .accessibilityLabel(FizzL10n.text("返回工作台", "Back to Workbench"))

                    Button {
                        Task {
                            await store.rescanProjects([project])
                            announceProjectRescan(project)
                        }
                    } label: {
                        FizzIcon(.md, symbol: "arrow.clockwise")
                            .symbolEffect(
                                .rotate,
                                options: .repeating,
                                isActive: store.phase == .scanning && !reduceMotion
                            )
                    }
                    .help(FizzL10n.text("重新扫描 \(project.displayName)", "Rescan \(project.displayName)"))
                    .accessibilityLabel(FizzL10n.text("重新扫描项目", "Rescan projects"))
                    .disabled(store.phase == .scanning)
                } else {
                    Button {
                        Task {
                            await store.scan()
                            announceWorkspaceRescan()
                        }
                    } label: {
                        Label {
                            Text(FizzL10n.text("重新扫描", "Rescan"))
                        } icon: {
                            FizzIcon(.md, symbol: "arrow.clockwise")
                                .symbolEffect(
                                    .rotate,
                                    options: .repeating,
                                    isActive: store.phase == .scanning && !reduceMotion
                                )
                        }
                    }
                    .help(FizzL10n.text("重新扫描受管目录", "Rescan managed folders"))
                    .disabled(store.phase == .scanning)

                    Button {
                        Task { await store.addRoot() }
                    } label: {
                        Label {
                            Text(FizzL10n.text("文件夹", "Folders"))
                        } icon: {
                            FizzIcon(.md, symbol: "folder")
                        }
                    }
                    .help(FizzL10n.text("查看已加入文件夹，或扫描新目录", "View added folders or scan a new one"))
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.toggleCommandPalette()
                } label: {
                    FizzIcon(.md, symbol: "magnifyingglass")
                }
                .help(FizzL10n.text("搜索项目、分支、远程或动作（⌘K）", "Search projects, branches, remotes, or actions (⌘K)"))
                .accessibilityLabel(FizzL10n.text("搜索", "Search"))
            }
        }
        .overlay {
            if store.isCommandPalettePresented {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .zIndex(10)
            }
        }
        .overlay {
            if store.isFolderManagerPresented {
                AddProjectsSheet()
                    .environment(store)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(20)
            }
        }
        .onOpenURL { url in
            // SwiftUI has already activated/reused the destination window.
            let roots = store.phase == .idle ? RootStore.load() : store.roots
            if let request = AppRouting.projectRequest(from: url, managedRoots: roots) {
                pendingRoute = request
                applyProjectRequest()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppRouting.openProjectNotification)) { _ in
            receiveProjectRequest()
        }
        .onAppear {
            receiveProjectRequest()
        }
        .onChange(of: store.phase) { applyProjectRequest() }
        .sheet(item: $handoff) { HandoffCardSheet(project: $0) }
        .sheet(isPresented: $showingWeeklyRecap) { WeeklyRecapSheet(projects: store.projects) }
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.panel),
            value: store.isCommandPalettePresented
        )
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.panel),
            value: store.isFolderManagerPresented
        )
    }

    private var detail: some View {
        ZStack {
            detailContent
                .id(store.destination)
                .transition(.opacity.combined(with: .scale(scale: 0.992)))
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: store.destination)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.destination {
        case .dashboard:
            WorkbenchDashboardView { showingWeeklyRecap = true }
        case .conversations:
            ConversationsWorkspaceView { showingWeeklyRecap = true }
        case .library(let query):
            LibraryView(query: query)
        case .cleanup:
            DoctorWorkspaceView()
        case .project:
            if let project = store.selectedProject {
                ProjectDetailView(project: project)
            } else {
                WelcomeView()
            }
        }
    }

    private func announceWorkspaceRescan() {
        let counts = Dictionary(grouping: store.projects, by: \.group)
            .values
            .map { Double($0.count) }
            .sorted(by: >)
        ToastCenter.shared.show(
            FizzL10n.text("重新扫描完成", "Rescan complete"),
            symbol: "arrow.clockwise.circle.fill",
            tint: Color.secondary,
            subtitle: FizzL10n.text("\(store.projects.count) 个项目 · \(Format.relative(store.scannedAt ?? Date()))", "\(SessionSummaryText.englishCount(store.projects.count, "project")) · \(Format.relative(store.scannedAt ?? Date()))"),
            microViz: .bars(values: counts, improved: false)
        )
    }

    private func announceProjectRescan(_ project: RepoProject) {
        let values = project.weekly
            .sorted { $0.key < $1.key }
            .suffix(8)
            .map { Double($0.value) }
        ToastCenter.shared.show(
            FizzL10n.text("已刷新 \(project.displayName)", "Refreshed \(project.displayName)"),
            symbol: "arrow.clockwise.circle.fill",
            tint: Color.secondary,
            subtitle: project.branch ?? project.groupTitle,
            microViz: .bars(values: values, improved: false)
        )
    }

    private func receiveProjectRequest() {
        if let request = AppRouting.consumePendingProject() { pendingRoute = request }
        applyProjectRequest()
    }

    private func applyProjectRequest() {
        guard let request = pendingRoute else { return }
        guard let project = store.projects.first(where: { $0.path == request.path }) else {
            if store.phase == .ready { pendingRoute = nil }
            return
        }
        pendingRoute = nil
        if request.showHandoff { handoff = project }
        store.selectedPath = request.path
        store.requestedTab = request.tab
        store.isCommandPalettePresented = false
        Self.routeLog.info("Applied project route: handoff=\(request.showHandoff, privacy: .public), tab=\(request.tab?.rawValue ?? "default", privacy: .public)")
    }
}

private struct WelcomeView: View {
    @Environment(RepositoryStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label(FizzL10n.text("把本地项目收进 FizzDeck", "Add local projects to FizzDeck"), systemImage: "square.stack.3d.up")
        } description: {
            Text(FizzL10n.text("扫描常用目录，查看体积、Git 状态、AI 会话和可清理项。文件不会被修改。", "Scan your folders to see project sizes, Git status, AI sessions, and reclaimable space. Your files stay unchanged."))
        } actions: {
            Button(FizzL10n.text("添加项目目录", "Add project folder")) {
                Task { await store.addRoot() }
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
        }
    }
}
