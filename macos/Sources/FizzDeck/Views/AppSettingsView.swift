import AppKit
import SwiftUI

struct AppSettingsView: View {
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: SettingsPage = .general
    @Namespace private var selectionNamespace

    var body: some View {
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
            .padding(12)
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
            .background(FizzTheme.page)
        }
        .frame(width: 720, height: 500)
        .preferredColorScheme(appearance.colorScheme)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: page)
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
        case .general: "通用"
        case .sessions: "会话与终端"
        case .aiAndMarks: "AI 与标记"
        case .about: "关于"
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
    }
}

private struct GeneralSettingsPage: View {
    @AppStorage(AppearancePreferences.key) private var appearance: AppAppearance = .system
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @State private var loginState = LoginItemService.state
    @State private var loginError: String?
    @State private var notificationPermission: NotificationPermission = .unknown
    @State private var fullDiskAccess = SystemPermissionService.hasFullDiskAccess

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

                    Divider()
                        .padding(.leading, 34)

                    SettingsPickerRow(
                        symbol: "text.bubble",
                        title: "界面术语",
                        detail: "默认使用人话描述版本与运行状态，悬停可看对应专业术语；熟悉 Git 可切换专业模式。"
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
            VStack(alignment: .leading, spacing: 18) {
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

                SettingsCard {
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
                }

                Spacer(minLength: 0)
            }
            .padding(28)
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
                    VStack(alignment: .leading, spacing: 10) {
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
                            updateActions
                        }

                        if case .downloading(let progress, let received, let total) = updater.state {
                            VStack(alignment: .leading, spacing: 5) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(FizzTheme.accent)
                                    .animation(
                                        FizzMotion.resolved(reduceMotion, .easeOut(duration: 0.22)),
                                        value: progress
                                    )

                                HStack {
                                    Text("\(Format.bytes(received)) / \(Format.bytes(total))")
                                    Spacer(minLength: 8)
                                    Text("\(Int((progress * 100).rounded()))%")
                                        .monospacedDigit()
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
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
            "无法自动安装",
            isPresented: Binding(
                get: { updater.notice != nil },
                set: { if !$0 { updater.clearNotice() } }
            )
        ) {
            Button("好") {
                updater.clearNotice()
            }
        } message: {
            Text(updater.notice ?? "")
        }
    }

    @ViewBuilder
    private var updateActions: some View {
        switch updater.state {
        case .idle:
            checkButton
        case .checking:
            Button {
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("检查中…")
                }
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
            .disabled(true)
        case .upToDate:
            checkButton
        case .available(let release):
            Button("前往 Release") {
                openURL(release.pageURL)
            }
            .buttonStyle(.glass)

            Button("下载更新") {
                updater.startDownload()
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
            .disabled(release.dmgAsset == nil)
            .help(release.dmgAsset == nil ? "这个版本没有可用的 arm64 DMG" : "下载更新")
        case .downloading:
            Button("取消") {
                updater.cancelDownload()
            }
            .buttonStyle(.glass)

            Button {
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("下载中…")
                }
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
            .disabled(true)
        case .verifying:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("校验中…")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        case .readyToInstall:
            Button("安装并重启") {
                Task { await updater.installAndRestart() }
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("正在安装…")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        case .failed:
            Button("重新检查") {
                Task { await updater.check() }
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
        }
    }

    private var checkButton: some View {
        Button("立即检查") {
            Task { await updater.check() }
        }
        .buttonStyle(.glassProminent)
        .tint(FizzTheme.accent)
    }

    private var updateStatusText: String {
        switch updater.state {
        case .idle:
            "手动检查是否有新版本。"
        case .checking:
            "正在连接 GitHub…"
        case .upToDate:
            "已是最新版本。"
        case .available(let release):
            "发现新版本 v\(release.version)，可下载并自动校验。"
        case .downloading(_, let received, let total):
            "正在下载更新 · \(Format.bytes(received)) / \(Format.bytes(total))"
        case .verifying:
            "正在校验 SHA-256、应用标识与签名…"
        case .readyToInstall:
            "更新已通过校验，可以安装并重启。"
        case .installing:
            "正在替换应用并重启…"
        case .failed(let message):
            message
        }
    }

    private var updateStatusColor: Color {
        switch updater.state {
        case .idle, .checking:
            return .secondary
        case .upToDate:
            return .green
        case .available, .downloading, .verifying, .readyToInstall, .installing:
            return FizzTheme.accent
        case .failed:
            return .orange
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("AI 与标记")
                    .font(.system(size: 19, weight: .semibold))

                marksSection
                aiSummarySection

                if summaryEnabled {
                    providerSection
                    diagnosticsSection
                }

                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .onAppear {
            hasStoredAPIKey = !(KeychainStore.load(account: SummaryPreferences.keychainAccount) ?? "").isEmpty
            summaryEngine.refreshUsageTotals()
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
            PromptPreviewSheet(sampleText: SummaryPromptBuilder.sampleRedactedPromptPreview())
        }
    }

    private var marksSection: some View {
        SettingsCard {
            Text("隐形标记与版本安全")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                SettingsIcon(symbol: "bookmark.circle")
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 完成或出错时自动做一次轻量记录点")
                        .font(.system(size: 13, weight: .medium))
                    Text("默认使用 Git 原生对象留档，不会写入项目代码目录，也不影响提交记录。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $implicitMarksEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()
                .padding(.leading, 34)

            HStack(spacing: 12) {
                SettingsIcon(symbol: "checkmark.bubble")
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动弹出「建议存个版本」提示")
                        .font(.system(size: 13, weight: .medium))
                    Text("关闭后仍可在进展卡片和顶部按钮手动存个版本。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { !saveVersionToastDisabled },
                    set: { saveVersionToastDisabled = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private var aiSummarySection: some View {
        SettingsCard {
            HStack(spacing: 12) {
                SettingsIcon(symbol: "sparkles")
                VStack(alignment: .leading, spacing: 3) {
                    Text("启用 AI 智能总结（实验性 · 默认关闭）")
                        .font(.system(size: 13, weight: .medium))
                    Text("用更通俗的语言概括每次对话成果与项目进度；未开启或调用失败时自动使用本地规则摘要。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { summaryEnabled },
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
            }

            Divider()
                .padding(.leading, 34)

            HStack(spacing: 12) {
                SettingsIcon(symbol: "eye.slash")
                VStack(alignment: .leading, spacing: 3) {
                    Text("仅发送最小脱敏字段，绝不上传源码与完整对话")
                        .font(.system(size: 12, weight: .medium))
                    Text("只包含项目名、文件名、变动计数与脱敏后的一句话意图。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("查看发送示例") {
                    showingPromptPreview = true
                }
                .controlSize(.small)
            }
        }
    }

    private var providerSection: some View {
        SettingsCard {
            SettingsPickerRow(
                symbol: "cpu",
                title: "总结引擎",
                detail: "优先推荐使用本机已登录的 Agent CLI，无需额外填写密钥。"
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
                    title: "CLI 工具",
                    detail: "所有汇总都在 ~/.repodeck/llm-workdir 中隔离运行，不会污染项目对话记录。"
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
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Base URL（如 https://api.openai.com/v1）", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型名称（如 gpt-4o-mini / deepseek-chat）", text: $apiModel)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        SecureField(
                            hasStoredAPIKey ? "已保存在钥匙串中（输入新 Key 可覆盖）" : "填入 API Key（存入 macOS 钥匙串）",
                            text: $apiKeyDraft
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("保存 Key") {
                            let ok = KeychainStore.save(
                                account: SummaryPreferences.keychainAccount,
                                secret: apiKeyDraft
                            )
                            hasStoredAPIKey = !(KeychainStore.load(account: SummaryPreferences.keychainAccount) ?? "").isEmpty
                            apiKeyDraft = ""
                            keySavedFeedback = ok ? "已存入系统钥匙串" : "保存失败，请检查钥匙串权限"
                        }
                        .controlSize(.small)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if hasStoredAPIKey {
                            Button("清除") {
                                KeychainStore.delete(account: SummaryPreferences.keychainAccount)
                                hasStoredAPIKey = false
                                keySavedFeedback = "已从钥匙串移除"
                            }
                            .controlSize(.small)
                        }
                    }

                    if let keySavedFeedback {
                        Text(keySavedFeedback)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 34)
            case .localModel:
                VStack(alignment: .leading, spacing: 10) {
                    TextField("本地服务地址（如 http://127.0.0.1:11434/v1）", text: $localBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("本地模型名称（如 qwen2.5:7b）", text: $localModel)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.leading, 34)
            }

            Divider()
                .padding(.leading, 34)

            HStack(spacing: 12) {
                SettingsIcon(symbol: "bolt.horizontal")
                VStack(alignment: .leading, spacing: 2) {
                    if let testFeedback {
                        Text(testFeedback)
                            .font(.system(size: 11.5))
                            .foregroundStyle(testSucceeded ? .green : .orange)
                    } else {
                        Text("发送极短的「回复 OK」测试，验证配置是否畅通。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Button(isTestingConnection ? "测试中…" : "测试连接") {
                    Task {
                        isTestingConnection = true
                        defer { isTestingConnection = false }
                        let result = await summaryEngine.testConnection()
                        switch result {
                        case .success(let text):
                            testSucceeded = true
                            testFeedback = text
                        case .failure(let err):
                            testSucceeded = false
                            testFeedback = err.errorDescription ?? "连接失败"
                        }
                    }
                }
                .controlSize(.small)
                .disabled(isTestingConnection)
            }
        }
    }

    private var diagnosticsSection: some View {
        SettingsCard {
            HStack(spacing: 12) {
                SettingsIcon(symbol: "chart.pie")
                VStack(alignment: .leading, spacing: 3) {
                    Text("近 30 天 FizzDeck 自身汇总消耗")
                        .font(.system(size: 13, weight: .medium))
                    let usage = summaryEngine.monthlySelfUsage
                    let costText = usage.hasCostData ? (Format.cost(usage.estimatedCostUSD, estimated: true) ?? "$0") : "计入本地/CLI"
                    Text("共 \(usage.callCount) 次调用 · \(Format.tokens(usage.totalTokens)) · \(costText)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("清空摘要缓存") {
                    summaryEngine.clearCache()
                }
                .controlSize(.small)
            }

            if let lastError = summaryEngine.lastError, !lastError.isEmpty {
                Divider()
                    .padding(.leading, 34)
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "exclamationmark.circle")
                    Text("最近一次静默回退原因：\(lastError)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "lock.shield", size: 18)
                    .foregroundStyle(FizzTheme.accent)
                Text("开启 AI 智能总结前确认")
                    .font(.system(size: 16, weight: .semibold))
            }

            Text("开启后，FizzDeck 会调用你选择的模型把对话和改动翻译成更易懂的大白话：")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("仅发送项目名、文件名、变更计数和脱敏后的起始意图", systemImage: "checkmark.circle")
                Label("绝不发送完整代码、环境变量或完整聊天记录", systemImage: "checkmark.circle")
                Label("自动过滤常见密钥与令牌；调用失败会静默回退到本地规则摘要", systemImage: "checkmark.circle")
            }
            .font(.system(size: 12))

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button("暂不开启") {
                    onCancel()
                    dismiss()
                }
                Button("我已知晓并开启") {
                    onAccept()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

private struct PromptPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sampleText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("实际发送内容示例（已脱敏）")
                .font(.system(size: 15, weight: .semibold))

            ScrollView {
                Text(sampleText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                            .fill(FizzTheme.cardFill)
                    )
            }
            .frame(height: 220)

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
