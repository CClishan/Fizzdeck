import AppKit
import SwiftUI

@main
struct FizzDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = RepositoryStore()
    @State private var actions = ProjectActions()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(actions)
                .preferredColorScheme(.light)
                .frame(minWidth: 1000, minHeight: 660)
                .task {
                    await store.prepare()
                }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("总览") {
                    store.selectedPath = RepositoryStore.homeSelection
                }
                .keyboardShortcut("0", modifiers: [.command])
                Button("重新扫描") {
                    Task { await store.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
