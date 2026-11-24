import SwiftUI

struct ContentView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = store
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
        .searchable(text: $store.query, prompt: "搜索项目、路径、技术栈")
        .toolbar(removing: .title)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
                    Label("添加目录", systemImage: "plus")
                }
                .help("把一个目录加入看板")
            }
        }
        .overlay {
            if store.isCommandPalettePresented {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .zIndex(10)
            }
        }
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.panel),
            value: store.isCommandPalettePresented
        )
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
