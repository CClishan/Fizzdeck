import AppKit
import Foundation

enum ResumeTarget: String, CaseIterable, Identifiable, Sendable {
    case auto
    case cli
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: FizzL10n.text("自动", "Automatic")
        case .cli: FizzL10n.text("仅 CLI", "CLI Only")
        case .desktop: FizzL10n.text("仅 Codex Desktop", "Codex Desktop Only")
        }
    }
}

enum SessionResumePreferences {
    static let codexTargetKey = "fizzdeck.codexResumeTarget"

    static func codexTarget(defaults: UserDefaults = .standard) -> ResumeTarget {
        guard let raw = defaults.string(forKey: codexTargetKey),
              let target = ResumeTarget(rawValue: raw)
        else { return .auto }
        return target
    }

    static func setCodexTarget(
        _ target: ResumeTarget,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(target.rawValue, forKey: codexTargetKey)
    }
}

enum RuntimeAvailability: Equatable, Sendable {
    case available
    case broken(String)
    case missing

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

struct ToolResumeCapability: Equatable, Sendable {
    let cli: RuntimeAvailability
    let desktopAvailable: Bool

    func shouldUseDesktop(for target: ResumeTarget) -> Bool {
        target == .desktop || (target == .auto && !cli.isAvailable && desktopAvailable)
    }
}

struct SessionResumeResult: Equatable, Sendable {
    let success: Bool
    let message: String
    let fallbackCommand: String?
    let needsAutomationPermission: Bool
}

private actor RuntimeProbeCache {
    static let shared = RuntimeProbeCache()
    private var entries: [String: (capability: ToolResumeCapability, expiresAt: Date)] = [:]

    func get(_ tool: String) -> ToolResumeCapability? {
        guard let entry = entries[tool], entry.expiresAt > Date() else { return nil }
        return entry.capability
    }

    func set(_ tool: String, capability: ToolResumeCapability) {
        entries[tool] = (capability, Date().addingTimeInterval(60))
    }

    func invalidate() {
        entries.removeAll()
    }
}

enum SessionResumeService {
    static func invalidateProbeCache() async {
        await RuntimeProbeCache.shared.invalidate()
    }

    static func probe(tool: String) async -> ToolResumeCapability {
        if let cached = await RuntimeProbeCache.shared.get(tool) {
            return cached
        }
        let capability = await performProbe(tool: tool)
        await RuntimeProbeCache.shared.set(tool, capability: capability)
        return capability
    }

    static func fallbackCommand(for session: SessionRecord, projectPath: String) -> String? {
        guard let cmd = session.resumeCommand else { return nil }
        let cwd = PathTools.normalize(session.cwd ?? projectPath)
        return "cd \(TerminalLauncher.shellQuote(cwd)) && \(cmd)"
    }

    static func resume(
        session: SessionRecord,
        projectPath: String,
        preferredTarget: ResumeTarget = .auto
    ) async -> SessionResumeResult {
        let cwd = PathTools.normalize(session.cwd ?? projectPath)
        let fallback = fallbackCommand(for: session, projectPath: cwd)

        guard DetectedTool(rawValue: session.tool)?.supportsResume == true,
              let resumeCmd = session.resumeCommand
        else {
            return SessionResumeResult(
                success: false,
                message: FizzL10n.text("暂不支持直接恢复 \(session.tool) 会话。", "Direct resume is not available for \(session.tool) sessions."),
                fallbackCommand: fallback,
                needsAutomationPermission: false
            )
        }

        let target: ResumeTarget = {
            if preferredTarget == .auto, session.tool == "codex" {
                return SessionResumePreferences.codexTarget()
            }
            return preferredTarget
        }()

        // 1. Check live CLI process or recently launched terminal session
        let liveMap = await SessionProcessService.liveProcessesDetailed(
            for: [session],
            projectPath: cwd
        )
        let liveProcesses = liveMap[session.stableID] ?? []
        if !liveProcesses.isEmpty {
            let launched = await LaunchedSessionStore.shared.info(for: session.stableID)
            let tty = liveProcesses.compactMap(\.tty).first ?? launched?.tty
            if let tty {
                let recordedTerminal = launched?.terminal.flatMap(PreferredTerminal.init(rawValue:))
                let effective = TerminalLauncher.effectiveTerminal()
                let focusTarget = recordedTerminal
                    ?? (effective.supportsTabFocus ? effective : nil)
                guard let terminal = focusTarget else {
                    return SessionResumeResult(
                        success: true,
                        message: FizzL10n.text("会话正在终端（\(tty)）运行中，请切换至对应窗口", "This session is running in \(tty). Switch to its terminal window."),
                        fallbackCommand: nil,
                        needsAutomationPermission: false
                    )
                }
                return await focusTerminal(
                    tty: tty,
                    terminal: terminal,
                    fallbackCommand: fallback
                )
            }
            let pids = liveProcesses.map { String($0.pid) }.joined(separator: ", ")
            return SessionResumeResult(
                success: true,
                message: FizzL10n.text("会话进程已在运行（PID \(pids)）", "Session process is already running (PID \(pids))"),
                fallbackCommand: nil,
                needsAutomationPermission: false
            )
        }

        // 2. Probe availability and route
        let capability = await probe(tool: session.tool)

        switch session.tool {
        case "codex":
            if capability.shouldUseDesktop(for: target) {
                return await openCodexDesktop(sessionID: session.id, fallback: fallback)
            }
            if capability.cli.isAvailable {
                return await launchInTerminal(session: session, cwd: cwd, command: resumeCmd, fallback: fallback)
            }
            return unavailableResult(toolTitle: target == .cli ? "Codex CLI" : "Codex", availability: capability.cli, fallback: fallback)

        case "claude":
            if capability.shouldUseDesktop(for: target) {
                return await activateClaudeDesktop(available: capability.desktopAvailable, fallback: fallback)
            }
            if capability.cli.isAvailable {
                return await launchInTerminal(session: session, cwd: cwd, command: resumeCmd, fallback: fallback)
            }
            return unavailableResult(toolTitle: "Claude Code CLI", availability: capability.cli, fallback: fallback)

        case "grok":
            if target == .desktop {
                return SessionResumeResult(
                    success: false,
                    message: FizzL10n.text("Grok 暂不支持桌面端直达，可使用 CLI 或复制恢复命令。", "Grok doesn’t support desktop links. Use the CLI or copy the resume command."),
                    fallbackCommand: fallback,
                    needsAutomationPermission: false
                )
            }
            guard capability.cli.isAvailable else {
                return unavailableResult(toolTitle: "Grok CLI", availability: capability.cli, fallback: fallback)
            }
            return await launchInTerminal(session: session, cwd: cwd, command: resumeCmd, fallback: fallback)

        case "gemini":
            if target == .desktop {
                return SessionResumeResult(
                    success: false,
                    message: FizzL10n.text("Gemini CLI 暂不支持桌面端直达，可使用 CLI 或复制恢复命令。", "Gemini CLI doesn’t support desktop links. Use the CLI or copy the resume command."),
                    fallbackCommand: fallback,
                    needsAutomationPermission: false
                )
            }
            guard capability.cli.isAvailable else {
                return unavailableResult(toolTitle: "Gemini CLI", availability: capability.cli, fallback: fallback)
            }
            return await launchInTerminal(session: session, cwd: cwd, command: resumeCmd, fallback: fallback)

        default:
            return SessionResumeResult(
                success: false,
                message: FizzL10n.text("暂不支持直接恢复 \(session.tool) 会话。", "Direct resume is not available for \(session.tool) sessions."),
                fallbackCommand: fallback,
                needsAutomationPermission: false
            )
        }
    }

    private static func performProbe(tool: String) async -> ToolResumeCapability {
        let cliResult = await Shell.runInLoginShell(
            "command -v \(tool) >/dev/null 2>&1 || exit 127; \(tool) --version",
            timeout: 5
        )
        let availability: RuntimeAvailability
        if let cliResult {
            if cliResult.succeeded {
                availability = .available
            } else if cliResult.status == 127 {
                availability = .missing
            } else {
                let firstLine = cliResult.text
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? "exit \(cliResult.status)"
                availability = .broken(String(firstLine.prefix(120)))
            }
        } else {
            availability = .missing
        }

        let desktopAvailable: Bool = await MainActor.run {
            switch tool {
            case "codex":
                if let url = URL(string: "codex://threads/probe") {
                    return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
                }
                return false
            case "claude":
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
                    || FileTools.isDirectory(URL(fileURLWithPath: "/Applications/Claude.app"))
            default:
                return false
            }
        }

        return ToolResumeCapability(cli: availability, desktopAvailable: desktopAvailable)
    }

    private static func unavailableResult(
        toolTitle: String,
        availability: RuntimeAvailability,
        fallback: String?
    ) -> SessionResumeResult {
        let detail: String
        switch availability {
        case .available:
            detail = FizzL10n.text("\(toolTitle) 可用", "\(toolTitle) is available")
        case let .broken(reason):
            detail = FizzL10n.text("\(toolTitle) 启动异常：\(reason)", "Couldn’t start \(toolTitle): \(reason)")
        case .missing:
            detail = FizzL10n.text("未检测到 \(toolTitle)，请先安装或复制命令在终端运行。", "\(toolTitle) wasn’t found. Install it or copy the command to your terminal.")
        }
        return SessionResumeResult(
            success: false,
            message: detail,
            fallbackCommand: fallback,
            needsAutomationPermission: false
        )
    }

    private static func openCodexDesktop(
        sessionID: String,
        fallback: String?
    ) async -> SessionResumeResult {
        guard let url = URL(string: "codex://threads/\(sessionID)") else {
            return SessionResumeResult(
                success: false,
                message: FizzL10n.text("无效的 Codex 会话链接。", "Invalid Codex session link."),
                fallbackCommand: fallback,
                needsAutomationPermission: false
            )
        }
        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        if opened {
            return SessionResumeResult(
                success: true,
                message: FizzL10n.text("已在 Codex Desktop 打开会话", "Opened the session in Codex Desktop"),
                fallbackCommand: nil,
                needsAutomationPermission: false
            )
        }
        return SessionResumeResult(
            success: false,
            message: FizzL10n.text("无法唤醒 Codex Desktop（codex://），可复制命令在终端运行。", "Couldn’t open Codex Desktop (codex://). Copy the command to your terminal."),
            fallbackCommand: fallback,
            needsAutomationPermission: false
        )
    }

    private static func activateClaudeDesktop(
        available: Bool,
        fallback: String?
    ) async -> SessionResumeResult {
        guard available else {
            return SessionResumeResult(
                success: false,
                message: FizzL10n.text("未安装 Claude Desktop，且 Claude CLI 不可用。", "Neither Claude Desktop nor the Claude CLI is available."),
                fallbackCommand: fallback,
                needsAutomationPermission: false
            )
        }
        let appURL: URL? = await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
                ?? (FileTools.isDirectory(URL(fileURLWithPath: "/Applications/Claude.app"))
                    ? URL(fileURLWithPath: "/Applications/Claude.app")
                    : nil)
        }
        guard let appURL else {
            return SessionResumeResult(
                success: false,
                message: FizzL10n.text("未找到 Claude.app。", "Claude.app wasn’t found."),
                fallbackCommand: fallback,
                needsAutomationPermission: false
            )
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return SessionResumeResult(
            success: true,
            message: FizzL10n.text("已激活 Claude Desktop（桌面端暂不支持按会话 ID 直达，如需精确定位可复制命令）", "Opened Claude Desktop. To resume this exact session, copy its command."),
            fallbackCommand: fallback,
            needsAutomationPermission: false
        )
    }

    private static func launchInTerminal(
        session: SessionRecord,
        cwd: String,
        command: String,
        fallback: String?
    ) async -> SessionResumeResult {
        let terminal = TerminalLauncher.effectiveTerminal()
        let outcome = await TerminalLauncher.launch(
            tool: session.tool,
            cwd: cwd,
            command: command,
            terminal: terminal
        )
        if let tty = outcome.tty {
            await LaunchedSessionStore.shared.record(
                stableID: session.stableID,
                tty: tty,
                windowID: outcome.windowID,
                terminal: terminal.rawValue
            )
        }
        return SessionResumeResult(
            success: outcome.success,
            message: outcome.message,
            fallbackCommand: outcome.success && !outcome.needsAutomationPermission
                ? nil
                : fallback,
            needsAutomationPermission: outcome.needsAutomationPermission
        )
    }

    private static func focusTerminal(
        tty: String,
        terminal: PreferredTerminal,
        fallbackCommand: String?
    ) async -> SessionResumeResult {
        let outcome = await TerminalLauncher.focus(tty: tty, terminal: terminal)
        return SessionResumeResult(
            success: outcome.success,
            message: outcome.message,
            fallbackCommand: outcome.success ? nil : fallbackCommand,
            needsAutomationPermission: outcome.needsAutomationPermission
        )
    }
}
