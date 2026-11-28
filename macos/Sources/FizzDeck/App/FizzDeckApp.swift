import AppKit
import SwiftUI
import UserNotifications

@main
struct FizzDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @AppStorage(SidebarLayout.collapsedKey) private var sidebarCollapsed = false
    @FocusedBinding(\.fizzProjectTab) private var projectTab
    @State private var store = RepositoryStore()
    @State private var actions = ProjectActions()

    var body: some Scene {
        WindowGroup("FizzDeck", id: "main") {
            ContentView()
                .font(FizzTypography.body)
                .environment(store)
                .environment(actions)
                .preferredColorScheme(appearance.colorScheme)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .frame(minWidth: 1000, minHeight: 660)
                .background(WindowFrameGuard())
                .task {
                    ShortcutProjectData.liveStore = store
                    await store.prepare()
                }
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button(sidebarCollapsed ? "显示侧栏" : "隐藏侧栏") {
                    sidebarCollapsed.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            CommandGroup(after: .newItem) {
                Button(store.isCommandPalettePresented ? "关闭快速打开" : "快速打开…") {
                    store.toggleCommandPalette()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("工作台") {
                    store.openDashboard()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("项目库") {
                    store.openLibrary()
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("体检") {
                    store.openCleanup()
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("返回工作台") {
                    store.openDashboard()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("上一个项目页签") {
                    projectTab = projectTab?.adjacent(forward: false)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(projectTab == nil)

                Button("下一个项目页签") {
                    projectTab = projectTab?.adjacent(forward: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(projectTab == nil)

                Button("重新扫描") {
                    Task { await store.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("在终端中打开") {
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
                .font(FizzTypography.body)
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
        FizzTypography.registerBundledFonts()
        AppearancePreferences.applyStoredAppearance()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().delegate = self
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
        let request = AppRouting.projectRequest(from: userInfo)
        Task { @MainActor in
            if let request {
                AppRouting.openProject(path: request.path, tab: request.tab)
            } else {
                AppRouting.presentMainWindow()
            }
        }
        completionHandler()
    }
}
