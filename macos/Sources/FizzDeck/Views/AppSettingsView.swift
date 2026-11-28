import AppKit
import SwiftUI

struct AppSettingsView: View {
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var page: SettingsPage = .general
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            FizzSheetHeader(title: FizzL10n.text("设置", "Settings")) { dismissWindow() }
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.grid)
            Divider()

            settingsBody

            Divider()
            FizzSheetFooter {
                FizzActionButton(title: FizzL10n.text("完成", "Done"), prominence: .primary, keyboardNavigation: true) { dismissWindow() }
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 720, height: 500)
        .navigationTitle(FizzL10n.text("设置", "Settings"))
        .background(FizzTheme.page)
        .preferredColorScheme(appearance.colorScheme)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: page)
    }

    private var settingsBody: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPage.allCases) { item in
                    SettingsNavigationRow(
                        page: item,
                        selected: page == item,
                        selectionNamespace: selectionNamespace
                    ) {
                        page = item
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(FizzSpacing.grid)
            .frame(width: 170)
            .background(FizzTheme.sidebar)

            Divider()

            Group {
                switch page {
                case .general:
                    GeneralSettingsPage()
                case .sessions:
                    SessionsSettingsPage()
                case .aiAndMarks:
                    AIAndMarksSettingsPage()
                case .about:
                    AboutSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case sessions
    case aiAndMarks
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: FizzL10n.text("通用", "General")
        case .sessions: FizzL10n.text("会话与终端", "Sessions & Terminal")
        case .aiAndMarks: FizzL10n.text("AI 与标记", "AI & Checkpoints")
        case .about: FizzL10n.text("关于", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .sessions: "terminal"
        case .aiAndMarks: "sparkles"
        case .about: "info.circle"
        }
    }
}

private struct SettingsNavigationRow: View {
    let page: SettingsPage
    let selected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: FizzSpacing.row) {
                FizzIcon(.md, symbol: page.symbol)
                    .frame(width: 17)

                Text(page.title)
                    .font(FizzTypography.body(selected ? .medium : .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, FizzSpacing.row)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill)
                        .matchedGeometryEffect(
                            id: "settings-selection",
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
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .fizzKeyboardAction(action: action)
    }
}

private struct GeneralSettingsPage: View {
    @AppStorage("fizzdeck.language") private var language: FizzLanguage = .system
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @State private var loginState = LoginItemService.state
    @State private var loginError: String?
    @State private var notificationPermission: NotificationPermission = .unknown
    @State private var fullDiskAccess = SystemPermissionService.hasFullDiskAccess

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                SettingsCard {
                    SettingsPickerRow(symbol: "globe", title: FizzL10n.text("界面语言", "Interface language")) {
                        Picker(FizzL10n.text("界面语言", "Interface language"), selection: $language) {
                            ForEach(FizzLanguage.allCases) { choice in
                                Text(verbatim: choice.title).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                        .onChange(of: language) { _, choice in FizzL10n.use(choice) }
                    }

                    Divider().padding(.leading, 34)

                    SettingsPickerRow(
                        symbol: "circle.lefthalf.filled",
                        title: FizzL10n.text("外观", "Appearance"),
                        detail: FizzL10n.text("跟随系统，或固定浅色 / 低饱和炭黑暗色。", "Match your Mac or choose Light or Dark.")
                    ) {
                        Picker("", selection: appearanceBinding) {
                            ForEach(AppAppearance.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }

                    Divider()
                        .padding(.leading, 34)

                    SettingsPickerRow(
                        symbol: "text.bubble",
                        title: FizzL10n.text("界面术语", "Terminology"),
                        detail: FizzL10n.text("默认使用人话描述版本与运行状态，悬停可看对应专业术语；熟悉 Git 可切换专业模式。", "Use plain language or Git terms. Hover over a label to see its Git equivalent.")
                    ) {
                        Picker("", selection: $copyMode) {
                            ForEach(CopyMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }
                }

                SettingsCard {
                    HStack(spacing: FizzSpacing.grid) {
                        SettingsIcon(symbol: "power")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(FizzL10n.text("登录时启动", "Open at login"))
                                .font(FizzTypography.body(.medium))
                            Text(loginDetail)
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: FizzSpacing.grid)

                        if loginState == .requiresApproval {
                            FizzActionButton(title: FizzL10n.text("打开系统设置", "Open System Settings"), height: .compact) {
                                LoginItemService.openSettings()
                            }
                        }

                        Toggle("", isOn: loginBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(FizzL10n.text("登录时启动", "Open at login"))
                            .disabled(loginState == .unavailable)
                    }

                    if let loginError {
                        Text(loginError)
                            .font(FizzTypography.caption)
                            .fizzStatus(FizzTheme.statusWarning)
                    }
                }

                SettingsCard {
                    SettingsPermissionRow(
                        symbol: "bell",
                        title: FizzL10n.text("通知", "Notifications"),
                        detail: FizzL10n.text("显示待处理提醒和失败结果。", "Show reminders and let you know when something fails."),
                        status: notificationStatusText,
                        statusColor: notificationStatusColor,
                        actionTitle: notificationActionTitle
                    ) {
                        handleNotificationAction()
                    }

                    Divider()
                        .padding(.leading, 34)

                    SettingsPermissionRow(
                        symbol: "lock.shield",
                        title: FizzL10n.text("完整磁盘访问", "Full Disk Access"),
                        detail: FizzL10n.text("用于扫描受保护目录中的项目。", "Scan projects in protected folders."),
                        status: fullDiskAccessStatus,
                        statusColor: fullDiskAccessColor,
                        actionTitle: FizzL10n.text("打开设置", "Open Settings")
                    ) {
                        SystemPermissionService.openFullDiskAccessSettings()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(FizzSpacing.page)
        }
        .task {
            await refreshPermissions()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await refreshPermissions() }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginState == .enabled || loginState == .requiresApproval },
            set: { enabled in
                do {
                    try LoginItemService.setEnabled(enabled)
                    loginState = LoginItemService.state
                    loginError = nil
                } catch {
                    loginState = LoginItemService.state
                    loginError = error.localizedDescription
                }
            }
        )
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appearance },
            set: { value in
                appearance = value
                AppearancePreferences.apply(value)
            }
        )
    }

    private var loginDetail: String {
        switch loginState {
        case .enabled:
            return FizzL10n.text("FizzDeck 会随 macOS 登录启动。", "FizzDeck opens when you log in to your Mac.")
        case .requiresApproval:
            return FizzL10n.text("登录项已登记，等待系统允许。", "Waiting for approval in System Settings.")
        case .disabled:
            return FizzL10n.text("不会随 macOS 自动启动。", "FizzDeck stays closed when you log in.")
        case .unavailable:
            return FizzL10n.text("暂时无法读取登录项状态。", "The login item status is unavailable.")
        }
    }

    private var notificationStatusText: String {
        switch notificationPermission {
        case .allowed: FizzL10n.text("已允许", "Allowed")
        case .denied: FizzL10n.text("已拒绝", "Denied")
        case .notDetermined: FizzL10n.text("未设置", "Not set")
        case .unknown: FizzL10n.text("未知", "Unknown")
        }
    }

    private var notificationStatusColor: Color {
        switch notificationPermission {
        case .allowed: FizzTheme.statusSuccess
        case .denied: FizzTheme.statusWarning
        case .notDetermined, .unknown: .secondary
        }
    }

    private var notificationActionTitle: String? {
        switch notificationPermission {
        case .allowed: nil
        case .notDetermined: FizzL10n.text("允许", "Allow")
        case .denied, .unknown: FizzL10n.text("打开设置", "Open Settings")
        }
    }

    private var fullDiskAccessStatus: String {
        switch fullDiskAccess {
        case true: FizzL10n.text("已授权", "Granted")
        case false: FizzL10n.text("未授权", "Not granted")
        case nil: FizzL10n.text("需确认", "Unconfirmed")
        }
    }

    private var fullDiskAccessColor: Color {
        switch fullDiskAccess {
        case true: FizzTheme.statusSuccess
        case false: FizzTheme.statusWarning
        case nil: .secondary
        }
    }

    private func handleNotificationAction() {
        if notificationPermission == .notDetermined {
            Task {
                notificationPermission = await SystemPermissionService.requestNotifications()
            }
        } else {
            SystemPermissionService.openNotificationSettings()
        }
    }

    @MainActor
    private func refreshPermissions() async {
        loginState = LoginItemService.state
        notificationPermission = await SystemPermissionService.notificationPermission()
        fullDiskAccess = SystemPermissionService.hasFullDiskAccess
    }
}

private struct SessionsSettingsPage: View {
    @State private var preferredTerminal: PreferredTerminal = .terminal
    @State private var availableTerminals: [PreferredTerminal] = [.terminal]
    @State private var codexTarget: ResumeTarget = .auto
    @State private var automationPermission: AutomationPermissionState = .unknown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                SettingsCard {
                    SettingsPickerRow(
                        symbol: "terminal",
                        title: FizzL10n.text("默认终端", "Default terminal"),
                        detail: FizzL10n.text("打开项目目录和继续会话时使用，只显示已安装项。", "Open project folders and resume sessions in an installed terminal.")
                    ) {
                        Picker("", selection: terminalBinding) {
                            ForEach(availableTerminals) { terminal in
                                Text(terminal.title).tag(terminal)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }

                    Divider()
                        .padding(.leading, 34)

                    SettingsPermissionRow(
                        symbol: "hand.raised",
                        title: FizzL10n.text("自动化权限", "Automation"),
                        detail: automationDetail,
                        status: automationStatusText,
                        statusColor: automationStatusColor,
                        actionTitle: preferredTerminal == .warp ? nil : FizzL10n.text("打开设置", "Open Settings")
                    ) {
                        SystemPermissionService.openAutomationSettings()
                    }
                }

                SettingsCard {
                    SettingsPickerRow(
                        symbol: "arrow.uturn.backward",
                        title: FizzL10n.text("Codex 默认继续方式", "Resume Codex in"),
                        detail: FizzL10n.text("自动会优先 CLI；也可固定使用 CLI 或 Codex Desktop。", "Automatic tries the CLI first. You can also choose Codex Desktop.")
                    ) {
                        Picker("", selection: codexTargetBinding) {
                            ForEach(ResumeTarget.allCases) { target in
                                Text(target.title).tag(target)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(FizzSpacing.page)
        }
        .task {
            refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refresh()
        }
    }

    private var terminalBinding: Binding<PreferredTerminal> {
        Binding(
            get: { preferredTerminal },
            set: { terminal in
                preferredTerminal = terminal
                TerminalPreferences.setPreferredTerminal(terminal)
                automationPermission = AutomationPermissionStore.state(for: terminal)
            }
        )
    }

    private var codexTargetBinding: Binding<ResumeTarget> {
        Binding(
            get: { codexTarget },
            set: { target in
                codexTarget = target
                SessionResumePreferences.setCodexTarget(target)
            }
        )
    }

    private var automationDetail: String {
        preferredTerminal == .warp
            ? FizzL10n.text("Warp 通过 URL 打开目录，不需要自动化权限。", "Warp opens folders by URL and doesn’t need Automation access.")
            : FizzL10n.text("用于定位终端标签页和自动恢复会话；仅在需要时由 macOS 询问。", "macOS asks for access when FizzDeck needs to find a terminal tab or resume a session.")
    }

    private var automationStatusText: String {
        if preferredTerminal == .warp { return FizzL10n.text("无需授权", "Not required") }
        switch automationPermission {
        case .granted: return FizzL10n.text("已允许", "Allowed")
        case .denied: return FizzL10n.text("上次被拒", "Previously denied")
        case .unknown: return FizzL10n.text("按需授权", "Ask when needed")
        }
    }

    private var automationStatusColor: Color {
        if preferredTerminal == .warp { return .secondary }
        switch automationPermission {
        case .granted: return FizzTheme.statusSuccess
        case .denied: return FizzTheme.statusWarning
        case .unknown: return .secondary
        }
    }

    @MainActor
    private func refresh() {
        availableTerminals = TerminalLauncher.installedTerminals()
        if availableTerminals.isEmpty {
            availableTerminals = [.terminal]
        }
        preferredTerminal = TerminalLauncher.effectiveTerminal()
        codexTarget = SessionResumePreferences.codexTarget()
        automationPermission = AutomationPermissionStore.state(for: preferredTerminal)
    }
}

private struct AboutSettingsPage: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var updater = AppUpdateController()

    var body: some View {
        ScrollView {
            VStack(spacing: FizzSpacing.section) {
                VStack(spacing: FizzSpacing.row) {
                    FizzLogo(size: 64)

                    Text("FizzDeck")
                        .font(FizzTypography.pageTitle)
                    Text(FizzL10n.text("版本 \(AppVersion.display)", "Version \(AppVersion.display)"))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, FizzSpacing.grid)

                SettingsCard {
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        HStack(spacing: FizzSpacing.grid) {
                            SettingsIcon(symbol: "arrow.triangle.2.circlepath")

                            VStack(alignment: .leading, spacing: 3) {
                                Text(FizzL10n.text("检查更新", "Software Update"))
                                    .font(FizzTypography.body(.medium))
                                Text(updateStatusText)
                                    .font(FizzTypography.caption)
                                    .fizzStatus(updateStatusColor)
                            }

                            Spacer(minLength: FizzSpacing.grid)
                            updateActions
                        }

                        if case .downloading(let progress, let received, let total) = updater.state {
                            VStack(alignment: .leading, spacing: 5) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(Color.secondary)
                                    .animation(
                                        FizzMotion.resolved(reduceMotion, .easeOut(duration: 0.22)),
                                        value: progress
                                    )

                                HStack {
                                    Text("\(Format.bytes(received)) / \(Format.bytes(total))")
                                    Spacer(minLength: FizzSpacing.row)
                                    Text("\(Int((progress * 100).rounded()))%")
                                }
                                .font(FizzTypography.micro)
                                .foregroundStyle(.secondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                SettingsCard {
                    AboutLinkRow(
                        symbol: "house",
                        title: FizzL10n.text("主页", "Website"),
                        value: "koroo.top/fizzdeck",
                        url: URL(string: "https://koroo.top/fizzdeck")!
                    )

                    Divider()
                        .padding(.leading, 34)

                    AboutLinkRow(
                        symbol: "at",
                        title: FizzL10n.text("关注 @koroo", "Follow @koroo"),
                        value: "koroo.top",
                        url: URL(string: "https://koroo.top")!
                    )

                    Divider()
                        .padding(.leading, 34)

                    AboutLinkRow(
                        symbol: "chevron.left.forwardslash.chevron.right",
                        title: "GitHub",
                        value: "CClishan/Fizzdeck",
                        url: URL(string: "https://github.com/CClishan/Fizzdeck")!
                    )
                }
            }
            .padding(FizzSpacing.page)
            .animation(
                FizzMotion.resolved(reduceMotion, FizzMotion.spring),
                value: updater.state
            )
        }
        .task {
            if case .idle = updater.state {
                await updater.check()
            }
        }
        .alert(
            FizzL10n.text("无法自动安装", "Couldn’t install the update"),
            isPresented: Binding(
                get: { updater.notice != nil },
                set: { if !$0 { updater.clearNotice() } }
            )
        ) {
            Button(FizzL10n.text("好", "OK")) {
                updater.clearNotice()
            }
        } message: {
            Text(updater.notice ?? "")
        }
    }

    @ViewBuilder
    private var updateActions: some View {
        switch updater.state {
        case .idle, .upToDate:
            checkButton
        case .checking, .verifying, .installing:
            ProgressView().controlSize(.small)
        case .available(let release):
            FizzActionButton(title: FizzL10n.text("前往 Release", "View Release"), height: .compact) {
                openURL(release.pageURL)
            }

            FizzActionButton(title: FizzL10n.text("下载更新", "Download Update"), height: .compact, prominence: .primary) {
                updater.startDownload()
            }
            .disabled(release.dmgAsset == nil)
            .help(release.dmgAsset == nil ? FizzL10n.text("这个版本没有可用的 arm64 DMG", "This release has no Apple silicon disk image.") : FizzL10n.text("下载更新", "Download Update"))
        case .downloading:
            FizzActionButton(title: FizzL10n.text("取消下载", "Cancel Download"), height: .compact) {
                updater.cancelDownload()
            }
        case .readyToInstall:
            FizzActionButton(title: FizzL10n.text("安装并重启", "Install and Restart"), height: .compact, prominence: .primary) {
                Task { await updater.installAndRestart() }
            }
        case .failed:
            FizzActionButton(title: FizzL10n.text("重新检查", "Check Again"), height: .compact, prominence: .primary) {
                Task { await updater.check() }
            }
        }
    }

    private var checkButton: some View {
        FizzActionButton(title: FizzL10n.text("立即检查", "Check Now"), height: .compact, prominence: .primary) {
            Task { await updater.check() }
        }
    }

    private var updateStatusText: String {
        switch updater.state {
        case .idle:
            FizzL10n.text("手动检查是否有新版本。", "Check for a new version of FizzDeck.")
        case .checking:
            FizzL10n.text("正在连接 GitHub…", "Connecting to GitHub…")
        case .upToDate:
            FizzL10n.text("已是最新版本。", "FizzDeck is up to date.")
        case .available(let release):
            FizzL10n.text("发现新版本 v\(release.version)，可下载并自动校验。", "Version \(release.version) is available. FizzDeck verifies the download before installing.")
        case .downloading(_, let received, let total):
            FizzL10n.text("正在下载更新 · \(Format.bytes(received)) / \(Format.bytes(total))", "Downloading update · \(Format.bytes(received)) of \(Format.bytes(total))")
        case .verifying:
            FizzL10n.text("正在校验 SHA-256、应用标识与签名…", "Verifying the checksum, app identity, and signature…")
        case .readyToInstall:
            FizzL10n.text("更新已通过校验，可以安装并重启。", "Update verified. Ready to install and restart.")
        case .installing:
            FizzL10n.text("正在替换应用并重启…", "Installing the update and restarting…")
        case .failed(let message):
            message
        }
    }

    private var updateStatusColor: Color {
        switch updater.state {
        case .idle, .checking:
            return .secondary
        case .upToDate:
            return FizzTheme.statusSuccess
        case .available, .downloading, .verifying, .readyToInstall, .installing:
            return Color.secondary
        case .failed:
            return FizzTheme.statusWarning
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            content
        }
        .padding(FizzSpacing.panel)
        .fizzCard(radius: FizzRadius.card)
    }
}

private struct SettingsIcon: View {
    let symbol: String

    var body: some View {
        FizzIcon(.md, symbol: symbol)
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
    }
}

private struct SettingsPermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let status: String
    let statusColor: Color
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: FizzSpacing.grid) {
            SettingsIcon(symbol: symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FizzTypography.body(.medium))
                Text(detail)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: FizzSpacing.grid)

            Text(status)
                .font(FizzTypography.caption)
                .fizzStatus(statusColor)

            if let actionTitle {
                FizzActionButton(title: actionTitle, height: .compact, action: action)
            }
        }
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let picker: Content

    init(
        symbol: String,
        title: String,
        detail: String = "",
        @ViewBuilder picker: () -> Content
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.picker = picker()
    }

    var body: some View {
        HStack(spacing: FizzSpacing.grid) {
            SettingsIcon(symbol: symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FizzTypography.body(.medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: FizzSpacing.grid)

            picker.accessibilityLabel(title)
        }
    }
}

private struct AboutLinkRow: View {
    @Environment(\.openURL) private var openURL

    let symbol: String
    let title: String
    let value: String
    let url: URL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: symbol)

                Text(title)
                    .font(FizzTypography.body(.medium))

                Spacer(minLength: FizzSpacing.grid)

                Text(value)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)

                FizzIcon(.xs, symbol: "arrow.up.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AIAndMarksSettingsPage: View {
    @AppStorage(MarkPreferences.implicitMarksEnabledKey) private var implicitMarksEnabled = true
    @AppStorage(MarkPreferences.saveVersionToastDisabledKey) private var saveVersionToastDisabled = false
    @AppStorage(SummaryPreferences.enabledKey) private var summaryEnabled = false
    @AppStorage(SummaryPreferences.consentAcceptedKey) private var consentAccepted = false
    @AppStorage(SummaryPreferences.providerKindKey) private var providerKind: SummaryProviderKind = .agentCLI
    @AppStorage(SummaryPreferences.agentCLIKey) private var agentCLI: AgentCLIKind = .auto
    @AppStorage(SummaryPreferences.apiBaseURLKey) private var apiBaseURL = SummaryPreferences.defaultAPIBaseURL
    @AppStorage(SummaryPreferences.apiModelKey) private var apiModel = SummaryPreferences.defaultAPIModel
    @AppStorage(SummaryPreferences.localBaseURLKey) private var localBaseURL = SummaryPreferences.defaultLocalBaseURL
    @AppStorage(SummaryPreferences.localModelKey) private var localModel = SummaryPreferences.defaultLocalModel

    @State private var summaryEngine = SummaryEngine.shared
    @State private var apiKeyDraft = ""
    @State private var hasStoredAPIKey = false
    @State private var showingConsentSheet = false
    @State private var showingPromptPreview = false
    @State private var isTestingConnection = false
    @State private var testFeedback: String?
    @State private var testSucceeded = false
    @State private var keySavedFeedback: String?

    private var canUseSummary: Bool { summaryEnabled && consentAccepted }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                Text(FizzL10n.text("AI 与标记", "AI & Checkpoints"))
                    .font(FizzTypography.pageTitle)

                marksSection
                aiSummarySection

                if canUseSummary {
                    providerSection
                    diagnosticsSection
                }

                Spacer(minLength: 0)
            }
            .padding(FizzSpacing.page)
        }
        .onAppear {
            hasStoredAPIKey = !(KeychainStore.load(account: SummaryPreferences.keychainAccount) ?? "").isEmpty
            summaryEngine.refreshUsageTotals()
        }
        .onChange(of: FizzL10n.isEnglish) {
            testFeedback = nil
            keySavedFeedback = nil
        }
        .sheet(isPresented: $showingConsentSheet) {
            SummaryConsentSheet(
                onCancel: {
                    summaryEnabled = false
                },
                onAccept: {
                    consentAccepted = true
                    summaryEnabled = true
                }
            )
        }
        .sheet(isPresented: $showingPromptPreview) {
            PromptPreviewSheet()
        }
    }

    private var marksSection: some View {
        SettingsCard {
            Text(FizzL10n.text("隐形标记与版本安全", "Checkpoints and version history"))
                .font(FizzTypography.cardTitle)
                .foregroundStyle(.secondary)

            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: "bookmark.circle")
                VStack(alignment: .leading, spacing: 3) {
                    Text(FizzL10n.text("AI 完成或出错时自动做一次轻量记录点", "Create a checkpoint when AI finishes or fails"))
                        .font(FizzTypography.body(.medium))
                    Text(FizzL10n.text("默认使用 Git 原生对象留档，不会写入项目代码目录，也不影响提交记录。", "Checkpoints use Git objects without changing your project files or commit history."))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: FizzSpacing.grid)
                Toggle("", isOn: $implicitMarksEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(FizzL10n.text("自动记录对话标记", "Create session checkpoints"))
            }

            Divider()
                .padding(.leading, 34)

            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: "checkmark.bubble")
                VStack(alignment: .leading, spacing: 3) {
                    Text(FizzL10n.text("自动弹出「建议存个版本」提示", "Remind me to save a version"))
                        .font(FizzTypography.body(.medium))
                    Text(FizzL10n.text("关闭后仍可在进展卡片和顶部按钮手动存个版本。", "You can always save a version from the progress card or toolbar."))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: FizzSpacing.grid)
                Toggle("", isOn: Binding(
                    get: { !saveVersionToastDisabled },
                    set: { saveVersionToastDisabled = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(FizzL10n.text("建议存个版本", "Remind me to save a version"))
            }
        }
    }

    private var aiSummarySection: some View {
        SettingsCard {
            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: "sparkles")
                VStack(alignment: .leading, spacing: 3) {
                    Text(FizzL10n.text("启用 AI 智能总结（实验性 · 默认关闭）", "AI summaries (experimental)"))
                        .font(FizzTypography.body(.medium))
                    Text(FizzL10n.text("用更通俗的语言概括每次对话成果与项目进度；未开启或调用失败时自动使用本地规则摘要。", "Summarize sessions and project progress in plain language. Local summaries are used when AI is off or unavailable."))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: FizzSpacing.grid)
                Toggle("", isOn: Binding(
                    get: { canUseSummary },
                    set: { newValue in
                        if newValue && !consentAccepted {
                            showingConsentSheet = true
                        } else {
                            summaryEnabled = newValue
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(FizzL10n.text("启用 AI 智能总结", "Enable AI summaries"))
            }

            Divider()
                .padding(.leading, 34)

            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: "eye.slash")
                VStack(alignment: .leading, spacing: 3) {
                    Text(FizzL10n.text("仅发送最小脱敏字段，绝不上传源码与完整对话", "Only redacted details are sent"))
                        .font(FizzTypography.body(.medium))
                    Text(FizzL10n.text("只包含项目名、文件名、变动计数与脱敏后的一句话意图。", "Includes project and file names, change counts, and a short redacted task description. No source code or full chats."))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: FizzSpacing.grid)
                FizzActionButton(title: FizzL10n.text("查看发送示例", "View Example"), height: .compact) {
                    showingPromptPreview = true
                }
            }
        }
    }

    private var providerSection: some View {
        SettingsCard {
            SettingsPickerRow(
                symbol: "cpu",
                title: FizzL10n.text("总结引擎", "Summary provider"),
                detail: FizzL10n.text("优先推荐使用本机已登录的 Agent CLI，无需额外填写密钥。", "Use a CLI you’re already signed in to. No API key is needed.")
            ) {
                Picker("", selection: $providerKind) {
                    ForEach(SummaryProviderKind.allCases) { item in
                        Text(item.shortTitle).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }

            Divider()
                .padding(.leading, 34)

            switch providerKind {
            case .agentCLI:
                SettingsPickerRow(
                    symbol: "terminal",
                    title: FizzL10n.text("CLI 工具", "CLI tool"),
                    detail: FizzL10n.text("所有汇总都在 ~/.repodeck/llm-workdir 中隔离运行，不会污染项目对话记录。", "Summaries run in ~/.repodeck/llm-workdir, outside your project’s session history.")
                ) {
                    Picker("", selection: $agentCLI) {
                        ForEach(AgentCLIKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            case .openAICompatible:
                VStack(alignment: .leading, spacing: FizzSpacing.row) {
                    TextField(FizzL10n.text("Base URL（如 https://api.openai.com/v1）", "Base URL (e.g. https://api.openai.com/v1)"), text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField(FizzL10n.text("模型名称（如 gpt-4o-mini / deepseek-chat）", "Model (e.g. gpt-4o-mini or deepseek-chat)"), text: $apiModel)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: FizzSpacing.row) {
                        SecureField(
                            hasStoredAPIKey ? FizzL10n.text("已保存在钥匙串中（输入新 Key 可覆盖）", "Key saved in Keychain. Enter a new key to replace it.") : FizzL10n.text("填入 API Key（存入 macOS 钥匙串）", "API key (stored in Keychain)"),
                            text: $apiKeyDraft
                        )
                        .textFieldStyle(.roundedBorder)

                        if hasStoredAPIKey {
                            FizzActionButton(title: FizzL10n.text("清除", "Clear"), height: .compact, role: .destructive) {
                                KeychainStore.delete(account: SummaryPreferences.keychainAccount)
                                hasStoredAPIKey = false
                                keySavedFeedback = FizzL10n.text("已从钥匙串移除", "Key removed from Keychain.")
                            }
                        }

                        FizzActionButton(title: FizzL10n.text("保存 Key", "Save Key"), height: .compact, prominence: .primary) {
                            let ok = KeychainStore.save(
                                account: SummaryPreferences.keychainAccount,
                                secret: apiKeyDraft
                            )
                            hasStoredAPIKey = !(KeychainStore.load(account: SummaryPreferences.keychainAccount) ?? "").isEmpty
                            apiKeyDraft = ""
                            keySavedFeedback = ok ? FizzL10n.text("已存入系统钥匙串", "Key saved to Keychain.") : FizzL10n.text("保存失败，请检查钥匙串权限", "Couldn’t save the key. Check Keychain access.")
                        }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let keySavedFeedback {
                        Text(keySavedFeedback)
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 34)
            case .localModel:
                VStack(alignment: .leading, spacing: FizzSpacing.row) {
                    TextField(FizzL10n.text("本地服务地址（如 http://127.0.0.1:11434/v1）", "Local server URL (e.g. http://127.0.0.1:11434/v1)"), text: $localBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField(FizzL10n.text("本地模型名称（如 qwen2.5:7b）", "Local model (e.g. qwen2.5:7b)"), text: $localModel)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.leading, 34)
            }

            Divider()
                .padding(.leading, 34)

            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: "bolt.horizontal")
                VStack(alignment: .leading, spacing: 2) {
                    if let testFeedback {
                        Text(testFeedback)
                            .font(FizzTypography.body)
                            .fizzStatus(testSucceeded ? FizzTheme.statusSuccess : FizzTheme.statusWarning)
                    } else {
                        Text(FizzL10n.text("发送极短的「回复 OK」测试，验证配置是否畅通。", "Send a short prompt to check the connection."))
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: FizzSpacing.grid)
                FizzActionButton(title: isTestingConnection ? FizzL10n.text("测试中…", "Testing…") : FizzL10n.text("测试连接", "Test Connection"), height: .compact) {
                    Task {
                        guard canUseSummary, !isTestingConnection else { return }
                        isTestingConnection = true
                        defer { isTestingConnection = false }
                        let wasEnglish = FizzL10n.isEnglish
                        let result = await summaryEngine.testConnection()
                        guard wasEnglish == FizzL10n.isEnglish else { return }
                        switch result {
                        case .success(let text):
                            testSucceeded = true
                            testFeedback = text
                        case .failure(let err):
                            testSucceeded = false
                            testFeedback = err.errorDescription ?? FizzL10n.text("连接失败", "Connection failed")
                        }
                    }
                }
                .disabled(isTestingConnection)
            }
        }
    }

    private var diagnosticsSection: some View {
        SettingsCard {
            HStack(spacing: FizzSpacing.grid) {
                SettingsIcon(symbol: "chart.pie")
                VStack(alignment: .leading, spacing: 3) {
                    Text(FizzL10n.text("近 30 天 FizzDeck 自身汇总消耗", "FizzDeck summary usage · last 30 days"))
                        .font(FizzTypography.body(.medium))
                    let usage = summaryEngine.monthlySelfUsage
                    let costText = usage.hasCostData ? (Format.cost(usage.estimatedCostUSD, estimated: true) ?? "$0") : FizzL10n.text("计入本地/CLI", "Local or CLI usage")
                    Text(FizzL10n.text("共 \(usage.callCount) 次调用 · \(Format.tokens(usage.totalTokens)) · \(costText)", "\(SessionSummaryText.englishCount(usage.callCount, "call")) · \(Format.tokens(usage.totalTokens, locale: FizzL10n.locale)) tokens · \(costText)"))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: FizzSpacing.grid)
                FizzActionButton(title: FizzL10n.text("清空摘要缓存", "Clear Summary Cache"), height: .compact) {
                    summaryEngine.clearCache()
                }
            }

            if let lastError = summaryEngine.lastError, !lastError.isEmpty {
                Divider()
                    .padding(.leading, 34)
                HStack(spacing: FizzSpacing.grid) {
                    SettingsIcon(symbol: "exclamationmark.circle")
                    Text(FizzL10n.text("最近一次静默回退原因：\(lastError)", "Last fallback: \(lastError)"))
                        .font(FizzTypography.caption)
                        .fizzStatus(FizzTheme.statusWarning)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct SummaryConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FizzSheetHeader(title: FizzL10n.text("开启 AI 智能总结前确认", "Enable AI summaries?"), onClose: cancel)
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)

            Divider()

            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                Text(FizzL10n.text("开启后，FizzDeck 会调用你选择的模型把对话和改动翻译成更易懂的大白话：", "FizzDeck will use your chosen model to summarize sessions and changes."))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: FizzSpacing.row) {
                    Label(FizzL10n.text("仅发送项目名、文件名、变更计数和脱敏后的起始意图", "Sends project and file names, change counts, and a redacted task description."), systemImage: "checkmark.circle")
                    Label(FizzL10n.text("绝不发送完整代码、环境变量或完整聊天记录", "Never sends full source code, environment variables, or chat histories."), systemImage: "checkmark.circle")
                    Label(FizzL10n.text("自动过滤常见密钥与令牌；调用失败会静默回退到本地规则摘要", "Filters common keys and tokens. Uses a local summary if the request fails."), systemImage: "checkmark.circle")
                }
            }
            .font(FizzTypography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FizzSpacing.page)

            Divider()

            FizzSheetFooter {
                FizzActionButton(title: FizzL10n.text("暂不开启", "Not Now"), role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)

                FizzActionButton(title: FizzL10n.text("我已知晓并开启", "Enable AI Summaries"), prominence: .primary) {
                    onAccept()
                    dismiss()
                }
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 440)
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}

private struct PromptPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            FizzSheetHeader(title: FizzL10n.text("实际发送内容示例（已脱敏）", "Example of a redacted request")) { dismiss() }
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)

            Divider()

            ScrollView {
                Text(verbatim: SummaryPromptBuilder.sampleRedactedPromptPreview())
                    .font(FizzTypography.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(FizzSpacing.grid)
                    .background(
                        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                            .fill(FizzTheme.cardFill)
                    )
            }
            .frame(height: 220)
            .padding(FizzSpacing.page)

            Divider()

            FizzSheetFooter {
                FizzActionButton(title: FizzL10n.text("关闭", "Close"), prominence: .primary, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 460)
    }
}
