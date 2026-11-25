import SwiftUI

struct ContentView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(228)
                .navigationTitle("FizzDeck")
        } detail: {
            ZStack {
                FizzBackground()

                Group {
                    if let filter = store.selectedHomeFilter {
                        HomeDashboardView(filter: filter)
                    } else if let project = store.selectedProject {
                        ProjectDetailView(project: project)
                    } else {
                        WelcomeView()
                    }
                }
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .title)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if let project = store.selectedProject {
                    Button {
                        store.selectedPath = RepositoryStore.homeSelection
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("退出项目")
                    .accessibilityLabel("退出项目")

                    Button {
                        Task { await store.rescanProjects([project]) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重新扫描 \(project.displayName)")
                    .accessibilityLabel("重新扫描项目")
                    .disabled(store.phase == .scanning)
                } else {
                    Button {
                        Task { await store.scan() }
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .help("重新扫描受管目录")
                    .disabled(store.phase == .scanning)

                    Button {
                        Task { await store.addRoot() }
                    } label: {
                        Label("文件夹", systemImage: "folder")
                    }
                    .help("查看已加入文件夹，或扫描新目录")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.toggleCommandPalette()
                } label: {
                    Image(systemName: "magnifyingglass")
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
            .buttonStyle(.borderedProminent)
        }
    }
}
