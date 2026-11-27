import SwiftUI

struct ContentView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SidebarLayout.collapsedKey) private var sidebarCollapsed = false

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
                        FizzIcon(symbol: "sidebar.left", size: FizzIconScale.toolbar)
                    }
                    .help(sidebarCollapsed ? "展开侧栏" : "折叠侧栏")
                    .accessibilityLabel(sidebarCollapsed ? "展开侧栏" : "折叠侧栏")
                }

                if let project = store.selectedProject {
                    Button {
                        store.openDashboard()
                    } label: {
                        FizzIcon(symbol: "chevron.left", size: FizzIconScale.toolbar)
                    }
                    .help("返回工作台")
                    .accessibilityLabel("返回工作台")

                    Button {
                        Task {
                            await store.rescanProjects([project])
                            announceProjectRescan(project)
                        }
                    } label: {
                        FizzIcon(symbol: "arrow.clockwise", size: FizzIconScale.toolbar)
                            .symbolEffect(
                                .rotate,
                                options: .repeating,
                                isActive: store.phase == .scanning && !reduceMotion
                            )
                    }
                    .help("重新扫描 \(project.displayName)")
                    .accessibilityLabel("重新扫描项目")
                    .disabled(store.phase == .scanning)
                } else {
                    Button {
                        Task {
                            await store.scan()
                            announceWorkspaceRescan()
                        }
                    } label: {
                        Label {
                            Text("重新扫描")
                        } icon: {
                            FizzIcon(symbol: "arrow.clockwise", size: FizzIconScale.toolbar)
                                .symbolEffect(
                                    .rotate,
                                    options: .repeating,
                                    isActive: store.phase == .scanning && !reduceMotion
                                )
                        }
                    }
                    .help("重新扫描受管目录")
                    .disabled(store.phase == .scanning)

                    Button {
                        Task { await store.addRoot() }
                    } label: {
                        Label {
                            Text("文件夹")
                        } icon: {
                            FizzIcon(symbol: "folder", size: FizzIconScale.toolbar)
                        }
                    }
                    .help("查看已加入文件夹，或扫描新目录")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.toggleCommandPalette()
                } label: {
                    FizzIcon(symbol: "magnifyingglass", size: FizzIconScale.toolbar)
                }
                .help("搜索项目、分支、远程或动作（⌘K）")
                .accessibilityLabel("搜索")
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
        .onReceive(NotificationCenter.default.publisher(for: AppRouting.openProjectNotification)) { _ in
            openPendingProject()
        }
        .onAppear {
            openPendingProject()
        }
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
            WorkbenchDashboardView()
        case .conversations:
            ConversationsWorkspaceView()
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
            "重新扫描完成",
            symbol: "arrow.clockwise.circle.fill",
            tint: FizzTheme.accent,
            subtitle: "\(store.projects.count) 个项目 · \(Format.relative(store.scannedAt ?? Date()))",
            microViz: .bars(values: counts, improved: false)
        )
    }

    private func announceProjectRescan(_ project: RepoProject) {
        let values = project.weekly
            .sorted { $0.key < $1.key }
            .suffix(8)
            .map { Double($0.value) }
        ToastCenter.shared.show(
            "已刷新 \(project.displayName)",
            symbol: "arrow.clockwise.circle.fill",
            tint: FizzTheme.accent,
            subtitle: project.branch ?? project.group,
            microViz: .bars(values: values, improved: false)
        )
    }

    private func openPendingProject() {
        guard let request = AppRouting.consumePendingProject() else { return }
        store.selectedPath = request.path
        store.requestedTab = request.tab
        store.isCommandPalettePresented = false
    }
}

private struct WelcomeView: View {
    @Environment(RepositoryStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("把本地项目收进 FizzDeck", systemImage: "square.stack.3d.up")
        } description: {
            Text("扫描常用目录，查看体积、Git 状态、AI 会话和可清理项。文件不会被修改。")
        } actions: {
            Button("添加项目目录") {
                Task { await store.addRoot() }
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
        }
    }
}
