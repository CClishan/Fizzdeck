import AppKit
import Foundation

enum PreferredTerminal: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case iterm2
    case ghostty
    case warp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm2: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        }
    }

    var fallbackApplicationPaths: [String] {
        switch self {
        case .terminal:
            ["/System/Applications/Utilities/Terminal.app", "/Applications/Utilities/Terminal.app"]
        case .iterm2:
            ["/Applications/iTerm.app", "/Applications/iTerm2.app"]
        case .ghostty:
            ["/Applications/Ghostty.app"]
        case .warp:
            ["/Applications/Warp.app"]
        }
    }

    var supportsTabFocus: Bool {
        self == .terminal || self == .iterm2
    }

    func applicationURL(
        bundleLookup: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        fileExists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) -> URL? {
        if let url = bundleLookup(bundleIdentifier) {
            return url
        }
        return fallbackApplicationPaths
            .map { URL(fileURLWithPath: $0) }
            .first { fileExists($0.path) }
    }
}

enum TerminalPreferences {
    static let preferredTerminalKey = "fizzdeck.preferredTerminal"

    static func preferredTerminal(defaults: UserDefaults = .standard) -> PreferredTerminal {
        guard let raw = defaults.string(forKey: preferredTerminalKey),
              let terminal = PreferredTerminal(rawValue: raw)
        else { return .terminal }
        return terminal
    }

    static func setPreferredTerminal(
        _ terminal: PreferredTerminal,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(terminal.rawValue, forKey: preferredTerminalKey)
    }
}

enum AutomationPermissionState: String, Sendable {
    case unknown
    case granted
    case denied
}

enum AutomationPermissionStore {
    static let keyPrefix = "fizzdeck.automation."

    static func state(
        for terminal: PreferredTerminal,
        defaults: UserDefaults = .standard
    ) -> AutomationPermissionState {
        guard let raw = defaults.string(forKey: keyPrefix + terminal.rawValue),
              let state = AutomationPermissionState(rawValue: raw)
        else { return .unknown }
        return state
    }

    static func record(
        _ state: AutomationPermissionState,
        for terminal: PreferredTerminal,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(state.rawValue, forKey: keyPrefix + terminal.rawValue)
    }
}

enum TerminalAppleScript {
    static func launch(
        terminal: PreferredTerminal,
        scriptPath: String,
        cwd: String
    ) -> String? {
        let command = "exec \(TerminalLauncher.shellQuote(scriptPath))"
        switch terminal {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                set newTab to do script "\(escape(command))"
                set tabTTY to tty of newTab
                set winID to id of front window
                return tabTTY & "|" & (winID as string)
            end tell
            """
        case .iterm2:
            return """
            tell application id "com.googlecode.iterm2"
                activate
                if (count of windows) is 0 then
                    set targetWindow to (create window with default profile)
                else
                    set targetWindow to current window
                    tell targetWindow to create tab with default profile
                end if
                tell current session of targetWindow
                    write text "\(escape(command))"
                    return tty
                end tell
            end tell
            """
        case .ghostty:
            let ghosttyCommand = "/bin/zsh \(TerminalLauncher.shellQuote(scriptPath))"
            return """
            tell application id "com.mitchellh.ghostty"
                activate
                set surfaceConfig to new surface configuration
                set initial working directory of surfaceConfig to "\(escape(cwd))"
                set command of surfaceConfig to "\(escape(ghosttyCommand))"
                set newWindow to (new window with configuration surfaceConfig)
                try
                    return tty of focused terminal of selected tab of newWindow
                on error
                    return ""
                end try
            end tell
            """
        case .warp:
            return nil
        }
    }

    static func focus(terminal: PreferredTerminal, tty: String) -> String? {
        switch terminal {
        case .terminal:
            return """
            tell application "Terminal"
                set targetTTY to "\(escape(tty))"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (tty of t) is targetTTY then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "FOCUSED"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """
        case .iterm2:
            return """
            tell application id "com.googlecode.iterm2"
                set targetTTY to "\(escape(tty))"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is targetTTY then
                                select s
                                set index of w to 1
                                activate
                                return "FOCUSED"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """
        case .ghostty, .warp:
            return nil
        }
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct TerminalLaunchOutcome: Equatable, Sendable {
    let success: Bool
    let message: String
    let needsAutomationPermission: Bool
    let tty: String?
    let windowID: Int?
}

struct TerminalFocusOutcome: Equatable, Sendable {
    let success: Bool
    let message: String
    let needsAutomationPermission: Bool
}

enum TerminalLauncher {
    static func effectiveTerminal(defaults: UserDefaults = .standard) -> PreferredTerminal {
        let preferred = TerminalPreferences.preferredTerminal(defaults: defaults)
        let installed = installedTerminals()
        guard !installed.isEmpty else { return .terminal }
        return resolve(preferred: preferred, installed: installed)
    }

    static func resolve(
        preferred: PreferredTerminal,
        installed: [PreferredTerminal]
    ) -> PreferredTerminal {
        installed.contains(preferred) ? preferred : .terminal
    }

    static func installedTerminals() -> [PreferredTerminal] {
        installedTerminals(
            bundleLookup: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    static func installedTerminals(
        bundleLookup: (String) -> URL?,
        fileExists: (String) -> Bool
    ) -> [PreferredTerminal] {
        PreferredTerminal.allCases.filter {
            $0.applicationURL(bundleLookup: bundleLookup, fileExists: fileExists) != nil
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func launchScriptContents(
        cwd: String,
        command: String,
        scriptPath: String? = nil
    ) -> String {
        var lines = [
            "#!/bin/zsh",
            "clear",
            "cd \(shellQuote(cwd)) || {",
            "  echo 'FizzDeck: 无法进入项目目录 \(cwd.replacingOccurrences(of: "'", with: ""))'",
            "  exec \"${SHELL:-/bin/zsh}\" -l",
            "}",
            "echo \"→ \(escapeDoubleQuoted(command))\"",
            command,
            "status=$?",
        ]
        if let scriptPath {
            lines.append("rm -f \(shellQuote(scriptPath)) >/dev/null 2>&1 || true")
        }
        lines.append(contentsOf: [
            "if [ $status -ne 0 ]; then",
            "  echo \"\"",
            "  echo \"FizzDeck: 会话命令退出（exit $status），保留终端以便排查。\"",
            "  exec \"${SHELL:-/bin/zsh}\" -l",
            "fi",
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    static func cleanupLaunchers(
        in directory: URL = AppPaths.launchersDir,
        now: Date = Date(),
        olderThan: TimeInterval = 24 * 60 * 60,
        fileManager: FileManager = .default
    ) -> Int {
        guard olderThan > 0,
              let entries = try? fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else { return 0 }

        var removed = 0
        for entry in entries {
            guard entry.lastPathComponent.hasPrefix("resume-"),
                  entry.pathExtension == "command"
            else { continue }

            let values = try? entry.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate,
                  now.timeIntervalSince(modified) > olderThan
            else { continue }

            if (try? fileManager.removeItem(at: entry)) != nil {
                removed += 1
            }
        }
        return removed
    }

    static func writeLaunchScript(tool: String, cwd: String, command: String) throws -> URL {
        cleanupLaunchers()
        try FileTools.manager.createDirectory(
            at: AppPaths.launchersDir,
            withIntermediateDirectories: true
        )
        let safeTool = tool.filter { $0.isLetter || $0.isNumber }
        let scriptURL = AppPaths.launchersDir.appendingPathComponent(
            "resume-\(safeTool.isEmpty ? "session" : safeTool)-\(UUID().uuidString).command"
        )
        let content = launchScriptContents(
            cwd: cwd,
            command: command,
            scriptPath: scriptURL.path
        )
        try content.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileTools.manager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    static func warpURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "warp"
        components.host = "action"
        components.path = "/new_tab"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }

    static func openDirectory(_ path: String, terminal: PreferredTerminal? = nil) {
        let target = terminal ?? effectiveTerminal()
        if target == .warp,
           target.applicationURL() != nil,
           let url = warpURL(path: path) {
            NSWorkspace.shared.open(url)
            return
        }
        guard let application = target.applicationURL() else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: application,
            configuration: configuration
        )
    }

    static func launch(
        tool: String,
        cwd: String,
        command: String,
        terminal: PreferredTerminal
    ) async -> TerminalLaunchOutcome {
        if terminal == .warp {
            return await launchWarp(cwd: cwd)
        }
        guard let application = terminal.applicationURL() else {
            return TerminalLaunchOutcome(
                success: false,
                message: "未检测到 \(terminal.title)，请更换默认终端或复制命令运行。",
                needsAutomationPermission: false,
                tty: nil,
                windowID: nil
            )
        }

        let scriptURL: URL
        do {
            scriptURL = try writeLaunchScript(tool: tool, cwd: cwd, command: command)
        } catch {
            return TerminalLaunchOutcome(
                success: false,
                message: "生成启动脚本失败：\(error.localizedDescription)",
                needsAutomationPermission: false,
                tty: nil,
                windowID: nil
            )
        }

        guard let source = TerminalAppleScript.launch(
            terminal: terminal,
            scriptPath: scriptURL.path,
            cwd: cwd
        ) else {
            return TerminalLaunchOutcome(
                success: false,
                message: "\(terminal.title) 暂不支持自动恢复会话，请复制命令运行。",
                needsAutomationPermission: false,
                tty: nil,
                windowID: nil
            )
        }

        switch await runAppleScript(source) {
        case let .success(output):
            AutomationPermissionStore.record(.granted, for: terminal)
            let parsed = parseLaunchOutput(output, terminal: terminal)
            return TerminalLaunchOutcome(
                success: true,
                message: "已在 \(terminal.title) 中恢复会话",
                needsAutomationPermission: false,
                tty: parsed.tty,
                windowID: parsed.windowID
            )

        case let .failure(errorCode, _):
            if errorCode == -1743 {
                AutomationPermissionStore.record(.denied, for: terminal)
            }
            if terminal == .terminal {
                let opened = await open([scriptURL], withApplication: application)
                return TerminalLaunchOutcome(
                    success: opened,
                    message: opened
                        ? (errorCode == -1743
                            ? "已通过 Terminal 启动会话（开启「自动化」权限后支持精确聚焦）"
                            : "已通过 Terminal 启动会话")
                        : "无法启动 Terminal，请复制命令在终端运行。",
                    needsAutomationPermission: errorCode == -1743,
                    tty: nil,
                    windowID: nil
                )
            }
            try? FileManager.default.removeItem(at: scriptURL)
            let opened = await open([URL(fileURLWithPath: cwd)], withApplication: application)
            return TerminalLaunchOutcome(
                success: false,
                message: errorCode == -1743
                    ? (opened
                        ? "已打开 \(terminal.title) 项目目录；开启「自动化」权限后可自动恢复会话。"
                        : "已激活 \(terminal.title)；开启「自动化」权限后可自动恢复会话。")
                    : (opened
                        ? "已打开 \(terminal.title) 项目目录；自动启动失败，请复制命令运行。"
                        : "已激活 \(terminal.title)；自动启动失败，请复制命令运行。"),
                needsAutomationPermission: errorCode == -1743,
                tty: nil,
                windowID: nil
            )
        }
    }

    static func focus(
        tty: String,
        terminal: PreferredTerminal
    ) async -> TerminalFocusOutcome {
        guard terminal.supportsTabFocus else {
            let activated = await activate(terminal)
            return TerminalFocusOutcome(
                success: true,
                message: activated
                    ? "会话正在 \(terminal.title)（\(tty)）运行，已激活应用；\(terminal.title) 暂不支持按标签定位。"
                    : "会话正在 \(terminal.title)（\(tty)）运行中，请手动切换窗口。",
                needsAutomationPermission: false
            )
        }

        guard let source = TerminalAppleScript.focus(terminal: terminal, tty: tty) else {
            return TerminalFocusOutcome(
                success: true,
                message: "会话正在 \(terminal.title)（\(tty)）运行中，请切换至对应窗口。",
                needsAutomationPermission: false
            )
        }

        switch await runAppleScript(source) {
        case let .success(output):
            AutomationPermissionStore.record(.granted, for: terminal)
            let focused = output.trimmingCharacters(in: .whitespacesAndNewlines) == "FOCUSED"
            return TerminalFocusOutcome(
                success: true,
                message: focused
                    ? "已聚焦到运行中的会话标签页"
                    : "会话正在终端（\(tty)）运行中，请切换至对应窗口",
                needsAutomationPermission: false
            )

        case let .failure(errorCode, _):
            if errorCode == -1743 {
                AutomationPermissionStore.record(.denied, for: terminal)
            }
            _ = await activate(terminal)
            return TerminalFocusOutcome(
                success: true,
                message: errorCode == -1743
                    ? "已激活 \(terminal.title)（开启「自动化」权限后可精确聚焦到 \(tty) 标签页）"
                    : "已激活 \(terminal.title)",
                needsAutomationPermission: errorCode == -1743
            )
        }
    }

    private static func launchWarp(cwd: String) async -> TerminalLaunchOutcome {
        guard let application = PreferredTerminal.warp.applicationURL() else {
            return TerminalLaunchOutcome(
                success: false,
                message: "未检测到 Warp，请更换默认终端或复制命令运行。",
                needsAutomationPermission: false,
                tty: nil,
                windowID: nil
            )
        }

        if let url = warpURL(path: cwd) {
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            if opened {
                return TerminalLaunchOutcome(
                    success: false,
                    message: "已在 Warp 打开项目目录；Warp 不支持自动执行命令，请复制命令运行。",
                    needsAutomationPermission: false,
                    tty: nil,
                    windowID: nil
                )
            }
        }

        _ = await open([URL(fileURLWithPath: cwd)], withApplication: application)
        return TerminalLaunchOutcome(
            success: false,
            message: "已在 Warp 打开项目目录；无法自动恢复会话，请复制命令运行。",
            needsAutomationPermission: false,
            tty: nil,
            windowID: nil
        )
    }

    private static func parseLaunchOutput(
        _ output: String,
        terminal: PreferredTerminal
    ) -> (tty: String?, windowID: Int?) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch terminal {
        case .terminal:
            let parts = trimmed.split(separator: "|", maxSplits: 1).map(String.init)
            let tty = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let windowID = parts.count > 1
                ? Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                : nil
            return (tty?.isEmpty == false ? tty : nil, windowID)
        case .iterm2, .ghostty:
            return (trimmed.isEmpty ? nil : trimmed, nil)
        case .warp:
            return (nil, nil)
        }
    }

    private static func open(_ urls: [URL], withApplication application: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            try await NSWorkspace.shared.open(
                urls,
                withApplicationAt: application,
                configuration: configuration
            )
            return true
        } catch {
            return false
        }
    }

    private static func activate(_ terminal: PreferredTerminal) async -> Bool {
        guard let application = terminal.applicationURL() else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: application,
                configuration: configuration
            )
            return true
        } catch {
            return false
        }
    }

    private enum AppleScriptOutcome {
        case success(String)
        case failure(Int, String)
    }

    private static func runAppleScript(_ source: String) async -> AppleScriptOutcome {
        await MainActor.run {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                return .failure(-1, "Invalid AppleScript")
            }
            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
                let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
                return .failure(number, message)
            }
            return .success(descriptor.stringValue ?? "")
        }
    }

    private static func escapeDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}
