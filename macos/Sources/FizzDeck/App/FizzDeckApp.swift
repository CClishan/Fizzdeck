import AppKit
import SwiftUI
import UserNotifications

@main
struct FizzDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = RepositoryStore()
    @State private var actions = ProjectActions()

    var body: some Scene {
        WindowGroup("FizzDeck", id: "main") {
            ContentView()
                .environment(store)
                .environment(actions)
                .preferredColorScheme(.light)
                .frame(minWidth: 1000, minHeight: 660)
                .background(WindowFrameGuard())
                .task {
                    await store.prepare()
                }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button(store.isCommandPalettePresented ? "关闭快速打开" : "快速打开…") {
                    store.toggleCommandPalette()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("总览") {
                    store.selectedPath = RepositoryStore.homeSelection
                }
                .keyboardShortcut("0", modifiers: [.command])
                Button("重新扫描") {
                    Task { await store.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("在 Terminal 中打开") {
                    if let project = store.selectedProject {
                        SystemActions.openTerminal(project.path)
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(store.selectedProject == nil)
            }
        }

        Settings {
            AppSettingsView()
        }
        .defaultSize(width: 720, height: 500)

        MenuBarExtra {
            MenuBarMenu(store: store, actions: actions)
        } label: {
            MenuBarLabel(store: store, actions: actions)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().delegate = self
        Task { await LocalNotifications.requestAuthorization() }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if let request = AppRouting.projectRequest(from: userInfo) {
                AppRouting.openProject(path: request.path, tab: request.tab)
            } else {
                AppRouting.presentMainWindow()
            }
        }
        completionHandler()
    }
}
