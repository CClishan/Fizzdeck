import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let store: RepositoryStore
    let actions: ProjectActions

    @State private var now = Date()

    private var attentionCount: Int {
        ProjectAttentionQueue
            .items(projects: store.projects, testRuns: actions.testRuns)
            .filter {
                !store.isAttentionSuppressed(
                    for: $0.project,
                    kind: $0.kind,
                    at: now
                )
            }
            .count
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attentionCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
            Text("\(attentionCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FizzDeck，待处理 \(attentionCount) 项")
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                now = Date()
            }
        }
    }
}

struct MenuBarMenu: View {
    let store: RepositoryStore
    let actions: ProjectActions

    @Environment(\.openWindow) private var openWindow

    private var recentProjects: [RepoProject] {
        Array(store.projects.prefix(6))
    }

    var body: some View {
        Button("打开总览") {
            show(nil)
        }
        Button("重新扫描") {
            Task { await store.scan() }
        }
        .disabled(store.phase == .scanning)

        if !recentProjects.isEmpty {
            Divider()
            Section("最近项目") {
                ForEach(recentProjects) { project in
                    Button(project.displayName) {
                        show(project)
                    }
                }
            }
        }

        Divider()
        Button("退出 FizzDeck") {
            NSApp.terminate(nil)
        }
    }

    private func show(_ project: RepoProject?) {
        store.isCommandPalettePresented = false
        if let project {
            store.openProject(project)
        } else {
            store.selectedPath = RepositoryStore.homeSelection
            store.requestedTab = nil
        }
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.title == "FizzDeck"
        }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
