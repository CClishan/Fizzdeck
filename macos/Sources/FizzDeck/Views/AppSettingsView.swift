import AppKit
import SwiftUI

struct AppSettingsView: View {
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @State private var page: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPage.allCases) { item in
                    SettingsNavigationRow(
                        page: item,
                        selected: page == item
                    ) {
                        page = item
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 170)
            .background(FizzTheme.sidebar)

            Divider()

            Group {
                switch page {
                case .general:
                    GeneralSettingsPage()
                case .about:
                    AboutSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FizzTheme.page)
        }
        .frame(width: 720, height: 500)
        .preferredColorScheme(appearance.colorScheme)
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

private struct SettingsNavigationRow: View {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                FizzIcon(symbol: page.symbol, size: 13)
                    .frame(width: 17)

                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill.opacity(hovering && !selected ? 0.55 : 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

private struct GeneralSettingsPage: View {
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @State private var loginState = LoginItemService.state
    @State private var loginError: String?
    @State private var notificationPermission: NotificationPermission = .unknown
    @State private var fullDiskAccess = SystemPermissionService.hasFullDiskAccess
    @State private var preferredTerminal: PreferredTerminal = .terminal
    @State private var availableTerminals: [PreferredTerminal] = [.terminal]
    @State private var codexTarget: ResumeTarget = .auto
    @State private var automationPermission: AutomationPermissionState = .unknown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard {
                    SettingsPickerRow(
                        symbol: "circle.lefthalf.filled",
                        title: "外观",
                        detail: "跟随系统，或固定浅色 / 低饱和炭黑暗色。"
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
                }

                SettingsCard {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "power")

                        VStack(alignment: .leading, spacing: 3) {
                            Text("登录时启动")
                                .font(.system(size: 13, weight: .medium))
                            Text(loginDetail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        if loginState == .requiresApproval {
                            Button("打开系统设置") {
                                LoginItemService.openSettings()
                            }
                            .controlSize(.small)
                        }

                        Toggle("", isOn: loginBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(loginState == .unavailable)
                    }

                    if let loginError {
                        Text(loginError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    }
                }

                SettingsCard {
                    SettingsPermissionRow(
                        symbol: "bell",
                        title: "通知",
                        detail: "显示待处理提醒和失败结果。",
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
                        title: "完整磁盘访问",
                        detail: "用于扫描受保护目录中的项目。",
                        status: fullDiskAccessStatus,
                        statusColor: fullDiskAccessColor,
                        actionTitle: "打开设置"
                    ) {
                        SystemPermissionService.openFullDiskAccessSettings()
                    }
                }

                SettingsCard {
                    SettingsPickerRow(
                        symbol: "terminal",
                        title: "默认终端",
                        detail: "打开项目目录和继续会话时使用，只显示已安装项。"
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

                    SettingsPickerRow(
                        symbol: "arrow.uturn.backward",
                        title: "Codex 默认继续方式",
                        detail: "自动会优先 CLI；也可固定使用 CLI 或 Codex Desktop。"
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

                    Divider()
                        .padding(.leading, 34)

                    SettingsPermissionRow(
                        symbol: "hand.raised",
                        title: "自动化权限",
                        detail: automationDetail,
                        status: automationStatusText,
                        statusColor: automationStatusColor,
                        actionTitle: preferredTerminal == .warp ? nil : "打开设置"
                    ) {
                        SystemPermissionService.openAutomationSettings()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(28)
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
                    loginError = loginState == .requiresApproval
                        ? "登录项已登记，需要在系统设置中允许。"
                        : nil
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

    private var loginDetail: String {
        switch loginState {
        case .enabled:
            return "FizzDeck 会随 macOS 登录启动。"
        case .requiresApproval:
            return "登录项已登记，等待系统允许。"
        case .disabled:
            return "不会随 macOS 自动启动。"
        case .unavailable:
            return "暂时无法读取登录项状态。"
        }
    }

    private var notificationStatusText: String {
        switch notificationPermission {
        case .allowed: "已允许"
        case .denied: "已拒绝"
        case .notDetermined: "未设置"
        case .unknown: "未知"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationPermission {
        case .allowed: .green
        case .denied: .orange
        case .notDetermined, .unknown: .secondary
        }
    }

    private var notificationActionTitle: String? {
        switch notificationPermission {
        case .allowed: nil
        case .notDetermined: "允许"
        case .denied, .unknown: "打开设置"
        }
    }

    private var fullDiskAccessStatus: String {
        switch fullDiskAccess {
        case true: "已授权"
        case false: "未授权"
        case nil: "需确认"
        }
    }

    private var fullDiskAccessColor: Color {
        switch fullDiskAccess {
        case true: .green
        case false: .orange
        case nil: .secondary
        }
    }

    private var automationDetail: String {
        preferredTerminal == .warp
            ? "Warp 通过 URL 打开目录，不需要自动化权限。"
            : "用于定位终端标签页和自动恢复会话；仅在需要时由 macOS 询问。"
    }

    private var automationStatusText: String {
        if preferredTerminal == .warp { return "无需授权" }
        switch automationPermission {
        case .granted: return "已允许"
        case .denied: return "上次被拒"
        case .unknown: return "按需授权"
        }
    }

    private var automationStatusColor: Color {
        if preferredTerminal == .warp { return .secondary }
        switch automationPermission {
        case .granted: return .green
        case .denied: return .orange
        case .unknown: return .secondary
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
    @State private var updateState: UpdateState = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    FizzLogo(size: 64)

                    Text("FizzDeck")
                        .font(.system(size: 20, weight: .semibold))
                    Text("版本 \(AppVersion.display)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                SettingsCard {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "arrow.triangle.2.circlepath")

                        VStack(alignment: .leading, spacing: 3) {
                            Text("检查更新")
                                .font(.system(size: 13, weight: .medium))
                            Text(updateStatusText)
                                .font(.system(size: 10.5))
                                .foregroundStyle(updateStatusColor)
                        }

                        Spacer(minLength: 12)

                        if case let .available(release) = updateState {
                            Button("前往下载") {
                                openURL(release.pageURL)
                            }
                            .buttonStyle(.glass)
                        }

                        Button {
                            Task { await checkForUpdates() }
                        } label: {
                            HStack(spacing: 6) {
                                if isChecking {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text(isChecking ? "检查中…" : "立即检查")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(FizzTheme.accent)
                        .disabled(isChecking)
                    }
                }

                SettingsCard {
                    AboutLinkRow(
                        symbol: "house",
                        title: "主页",
                        value: "koroo.top/fizzdeck",
                        url: URL(string: "https://koroo.top/fizzdeck")!
                    )

                    Divider()
                        .padding(.leading, 34)

                    AboutLinkRow(
                        symbol: "at",
                        title: "关注 @koroo",
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
            .padding(28)
        }
    }

    private var isChecking: Bool {
        if case .checking = updateState { return true }
        return false
    }

    private var updateStatusText: String {
        switch updateState {
        case .idle:
            return "手动检查是否有新版本。"
        case .checking:
            return "正在连接 GitHub…"
        case .upToDate:
            return "已是最新版本。"
        case let .available(release):
            return "发现新版本 v\(release.version)。"
        case .failed:
            return "检查失败，请确认网络后重试。"
        }
    }

    private var updateStatusColor: Color {
        switch updateState {
        case .idle, .checking:
            return .secondary
        case .upToDate:
            return .green
        case .available:
            return FizzTheme.accent
        case .failed:
            return .orange
        }
    }

    @MainActor
    private func checkForUpdates() async {
        guard !isChecking else { return }
        updateState = .checking

        do {
            let release = try await AppUpdateService.latestRelease()
            updateState = AppUpdateService.isNewer(release.version, than: AppVersion.short)
                ? .available(release)
                : .upToDate
        } catch {
            updateState = .failed
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .fizzCard(radius: FizzRadius.card)
    }
}

private struct SettingsIcon: View {
    let symbol: String

    var body: some View {
        FizzIcon(symbol: symbol, size: 15)
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
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(status)
                .font(.system(size: 10.5))
                .foregroundStyle(statusColor)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .controlSize(.small)
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
        detail: String,
        @ViewBuilder picker: () -> Content
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.picker = picker()
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            picker
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
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol)

                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 12)

                Text(value)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                FizzIcon(symbol: "arrow.up.right", size: 9)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum UpdateState {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case failed
}
