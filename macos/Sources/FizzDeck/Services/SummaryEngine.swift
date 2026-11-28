import CryptoKit
import Foundation
import Observation

struct SessionAISummary: Codable, Sendable, Equatable {
    let sessionStableID: String
    let headline: String
    let blockerOrNext: String?
    let isAIGenerated: Bool
    let generatedAt: Date
    let fingerprint: String
}

struct ProjectStatusAISummary: Codable, Sendable, Equatable {
    let projectPath: String
    let headline: String
    let suggestion: String?
    let isAIGenerated: Bool
    let generatedAt: Date
    let fingerprint: String
}

struct SelfUsageEntry: Codable, Sendable, Equatable {
    let timestamp: Date
    let providerKind: SummaryProviderKind
    let model: String?
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double?
}

struct SelfUsageTotals: Sendable, Equatable {
    let callCount: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
    let hasCostData: Bool

    static let zero = SelfUsageTotals(
        callCount: 0,
        totalTokens: 0,
        estimatedCostUSD: 0,
        hasCostData: false
    )
}

enum SelfUsageLedger {
    private static let maxEntries = 2_000
    private static let retentionDays = 90

    static func load(from file: URL = AppPaths.selfUsageFile) -> [SelfUsageEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SelfUsageEntry].self, from: data)) ?? []
    }

    static func record(
        _ entry: SelfUsageEntry,
        to file: URL = AppPaths.selfUsageFile,
        now: Date = Date()
    ) {
        var entries = load(from: file)
        entries.append(entry)
        let cutoff = now.addingTimeInterval(-Double(retentionDays * 24 * 60 * 60))
        entries = entries.filter { $0.timestamp >= cutoff }
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: file, options: [.atomic])
        }
    }

    static func totals(
        in windowDays: Int,
        from file: URL = AppPaths.selfUsageFile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SelfUsageTotals {
        let cutoff: Date = if windowDays == 7 {
            DashboardMetrics.sevenDayWindowStart(now: now, calendar: calendar)
        } else {
            calendar.date(byAdding: .day, value: -max(1, windowDays), to: now) ?? now
        }

        return totals(since: cutoff, through: now, from: file)
    }

    static func totals(since start: Date, through end: Date, from file: URL = AppPaths.selfUsageFile) -> SelfUsageTotals {
        let recent = load(from: file).filter { $0.timestamp >= start && $0.timestamp <= end }
        guard !recent.isEmpty else { return .zero }

        let totalTokens = recent.reduce(0) { $0 + max(0, $1.inputTokens) + max(0, $1.outputTokens) }
        var totalCost = 0.0
        var hasCostData = false
        for item in recent {
            if let cost = item.estimatedCostUSD {
                totalCost += max(0, cost)
                hasCostData = true
            }
        }

        return SelfUsageTotals(
            callCount: recent.count,
            totalTokens: totalTokens,
            estimatedCostUSD: totalCost,
            hasCostData: hasCostData
        )
    }

    static func weeklyTotals(
        from file: URL = AppPaths.selfUsageFile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SelfUsageTotals {
        totals(in: 7, from: file, now: now, calendar: calendar)
    }

    static func monthlyTotals(
        from file: URL = AppPaths.selfUsageFile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SelfUsageTotals {
        totals(in: 30, from: file, now: now, calendar: calendar)
    }
}

enum SummaryCacheStore {
    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sessionFingerprint(for session: SessionRecord) -> String {
        [
            session.stableID,
            String(Int(session.modified.timeIntervalSince1970)),
            String(session.turnCount ?? 0),
            session.endedWithError ? "err" : "ok",
            String(session.touchedFiles.count),
        ].joined(separator: "|")
    }

    static func projectFingerprint(for project: RepoProject) -> String {
        [
            PathTools.canonical(project.path),
            project.lastCommit?.hash ?? "",
            String(project.dirtyCount),
            String(project.ahead),
            String(project.behind),
            String(Int((project.sessions.lastSessionAt ?? .distantPast).timeIntervalSince1970)),
            String(project.sessions.sessionCount),
        ].joined(separator: "|")
    }

    static func loadSession(
        stableID: String,
        fingerprint: String,
        directory: URL = AppPaths.summariesDir
    ) -> SessionAISummary? {
        let file = cacheFile(kind: "sessions", key: stableID, directory: directory)
        guard let cached: SessionAISummary = decode(from: file),
              cached.fingerprint == fingerprint,
              !cached.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return cached
    }

    static func saveSession(
        _ summary: SessionAISummary,
        directory: URL = AppPaths.summariesDir
    ) {
        let file = cacheFile(kind: "sessions", key: summary.sessionStableID, directory: directory)
        encode(summary, to: file)
    }

    static func loadProject(
        projectPath: String,
        fingerprint: String,
        directory: URL = AppPaths.summariesDir
    ) -> ProjectStatusAISummary? {
        let file = cacheFile(kind: "projects", key: PathTools.canonical(projectPath), directory: directory)
        guard let cached: ProjectStatusAISummary = decode(from: file),
              cached.fingerprint == fingerprint,
              !cached.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return cached
    }

    static func saveProject(
        _ summary: ProjectStatusAISummary,
        directory: URL = AppPaths.summariesDir
    ) {
        let file = cacheFile(kind: "projects", key: PathTools.canonical(summary.projectPath), directory: directory)
        encode(summary, to: file)
    }

    static func clearAll(directory: URL = AppPaths.summariesDir) {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func cacheFile(kind: String, key: String, directory: URL) -> URL {
        directory
            .appendingPathComponent(kind, isDirectory: true)
            .appendingPathComponent("\(sha256Hex(key)).json")
    }

    private static func decode<T: Decodable>(from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? data.write(to: file, options: [.atomic])
        }
    }
}

enum SummaryPromptBuilder {
    static let maxPromptCharacters = 3_800

    static func sessionPrompt(
        session: SessionRecord,
        projectName: String,
        copyMode: CopyMode = .plain
    ) -> SummaryRequest {
        let toolTitle = HomeDashboardModel.toolTitle(session.tool)
        let redactedIntent = SecretRedactor.redact(String((session.primaryIntent ?? "未记录起始描述").prefix(240))).text
        let redactedLastUser = SecretRedactor.redact(String((session.lastUser ?? "").prefix(240))).text
        let files = session.touchedFiles.prefix(8).map {
            SecretRedactor.redact(URL(fileURLWithPath: $0).lastPathComponent).text
        }
        let redactedError = session.lastError.map {
            SecretRedactor.redact(String($0.prefix(200))).text
        }

        var lines: [String] = [
            "项目: \(projectName)",
            "工具: \(toolTitle)",
            "起始目标: \(redactedIntent)",
        ]
        if !redactedLastUser.isEmpty, redactedLastUser != redactedIntent {
            lines.append("最近提问: \(redactedLastUser)")
        }
        if let duration = session.durationMinutes, duration > 0 {
            lines.append("耗时: 约 \(duration) 分钟")
        }
        if let turns = session.turnCount, turns > 0 {
            lines.append("对话轮数: \(turns)")
        }
        if !files.isEmpty {
            lines.append("涉及文件名: \(files.joined(separator: ", "))")
        }
        if session.endedWithError {
            lines.append("异常状态: 以失败结束\(redactedError.map { " (\($0))" } ?? "")")
        }

        let toneRule = copyMode == .plain
            ? "面向非程序员初学者，用温和的大白话，避免 git 术语。"
            : "简洁准确，可保留少量技术关键词。"
        let systemPrompt = """
        你是工作台摘要助手。\(toneRule)
        只根据提供的少量结构化元信息，返回 JSON 对象：{"headline": "...", "blockerOrNext": "..."}。
        要求：headline 不超过 35 个字，说清做了什么；blockerOrNext 可为空字符串或 1 句下一步建议（不超过 35 个字）。不要编造未提及的文件内容。
        """

        return SummaryRequest(
            systemPrompt: systemPrompt,
            userPrompt: clampPrompt(lines.joined(separator: "\n")),
            maxOutputTokens: 180,
            jsonMode: true
        )
    }

    static func projectStatusPrompt(
        project: RepoProject,
        recentSessionHeadline: String? = nil,
        copyMode: CopyMode = .plain
    ) -> SummaryRequest {
        var seenFiles = Set<String>()
        let changedNames = project.sessions.recentSessions
            .prefix(3)
            .flatMap(\.touchedFiles)
            .map { SecretRedactor.redact(URL(fileURLWithPath: $0).lastPathComponent).text }
            .filter { seenFiles.insert($0).inserted }
            .prefix(8)
        let intent = SecretRedactor.redact(
            String((recentSessionHeadline ?? project.sessions.lastUserMessage ?? "近期无会话记录").prefix(220))
        ).text

        var lines: [String] = [
            "项目: \(project.displayName)",
            "分支: \(project.branch ?? "未命名")",
            "未保存改动文件数: \(project.dirtyCount)",
            "领先远程提交数: \(project.ahead)",
            "落后远程提交数: \(project.behind)",
            "最近工作概括: \(intent)",
        ]
        if !changedNames.isEmpty {
            lines.append("待保存文件名: \(changedNames.joined(separator: ", "))")
        }

        let toneRule = copyMode == .plain
            ? "面向非程序员用户，严禁使用 commit/dirty/ahead/branch 等行话。"
            : "简洁明了，突出当前状态和下一步动作。"
        let systemPrompt = """
        你是项目进度总结助手。\(toneRule)
        根据提供的轻量状态计数，返回 JSON 对象：{"headline": "...", "suggestion": "..."}。
        要求：headline 不超过 36 个字，一句说清现在的状态；suggestion 不超过 30 个字，给出最建议的下一步（没有则为空字符串）。
        """

        return SummaryRequest(
            systemPrompt: systemPrompt,
            userPrompt: clampPrompt(lines.joined(separator: "\n")),
            maxOutputTokens: 180,
            jsonMode: true
        )
    }

    static func commitMessagePrompt(
        projectName: String,
        changedFiles: [String],
        latestIntent: String?,
        copyMode: CopyMode = .plain
    ) -> SummaryRequest {
        let files = changedFiles.prefix(10).map {
            SecretRedactor.redact(URL(fileURLWithPath: $0).lastPathComponent).text
        }
        let intent = SecretRedactor.redact(String((latestIntent ?? "").prefix(220))).text

        var lines = [
            "项目: \(projectName)",
            "改动文件名: \(files.isEmpty ? "若干文件" : files.joined(separator: ", "))",
        ]
        if !intent.isEmpty {
            lines.append("最近任务意图: \(intent)")
        }

        let systemPrompt = copyMode == .plain
            ? "生成一句简短的中文版本保存说明（不超过 28 个字），通俗说明改了什么，只输出纯文本。"
            : "生成一句简明中文 commit message（不超过 36 个字），只输出纯文本。"

        return SummaryRequest(
            systemPrompt: systemPrompt,
            userPrompt: clampPrompt(lines.joined(separator: "\n")),
            maxOutputTokens: 80,
            jsonMode: false
        )
    }

    static func handoffPrompt(
        project: RepoProject,
        sessionLimit: Int = 3,
        copyMode: CopyMode = .plain
    ) -> SummaryRequest {
        let baseCard = HandoffCardBuilder.build(
            project: project,
            sessionLimit: sessionLimit,
            copyMode: copyMode,
            maxCharacters: 1_200
        )
        let systemPrompt = """
        请把下面的项目接力信息整理得更适合直接粘贴给下一位 AI 编程助手继续干活，保留全部事实与文件路径，不要编造信息，直接输出 Markdown。
        """
        return SummaryRequest(
            systemPrompt: systemPrompt,
            userPrompt: clampPrompt(baseCard.markdown),
            maxOutputTokens: 450,
            jsonMode: false
        )
    }

    static func sampleRedactedPromptPreview() -> String {
        let sample = SessionRecord(
            tool: "claude",
            id: "demo-preview",
            cwd: nil,
            startedAt: Date().addingTimeInterval(-1_500),
            modified: Date(),
            lastUser: "顺便检查 sk-live-demo1234567890abcdef 和密码不要写死",
            model: "claude-sonnet-4",
            firstUser: "把登录按钮的样式改圆润一点，然后补一个退出提示",
            touchedFiles: ["LoginView.swift", "SessionBanner.swift"],
            lastError: nil,
            endedWithError: false,
            turnCount: 6,
            durationMinutes: 25
        )
        let req = sessionPrompt(session: sample, projectName: "my-first-app", copyMode: .plain)
        return req.userPrompt
    }

    static func clampPrompt(_ text: String) -> String {
        let redacted = SecretRedactor.redact(text).text
        guard redacted.count > maxPromptCharacters else {
            return redacted
        }
        return String(redacted.prefix(maxPromptCharacters - 1)) + "…"
    }
}

@MainActor
@Observable
final class SummaryEngine {
    static let shared = SummaryEngine()

    private(set) var sessionSummaries: [String: SessionAISummary] = [:]
    private(set) var projectSummaries: [String: ProjectStatusAISummary] = [:]
    private(set) var lastError: String?
    private(set) var inFlightKeys: Set<String> = []
    private(set) var monthlySelfUsage: SelfUsageTotals = .zero

    private let cacheDirectory: URL
    private let usageFile: URL
    private let defaults: UserDefaults
    private let workdir: URL
    private let cliProvider: any SummaryProvider
    private let httpProvider: any SummaryProvider
    private let apiKeyLoader: @Sendable () -> String?

    init(
        cacheDirectory: URL = AppPaths.summariesDir,
        usageFile: URL = AppPaths.selfUsageFile,
        defaults: UserDefaults = .standard,
        workdir: URL = AppPaths.llmWorkdir,
        cliProvider: any SummaryProvider = AgentCLISummaryProvider(),
        httpProvider: any SummaryProvider = OpenAICompatibleSummaryProvider(),
        apiKeyLoader: @escaping @Sendable () -> String? = {
            KeychainStore.load(account: SummaryPreferences.keychainAccount)
        }
    ) {
        self.cacheDirectory = cacheDirectory
        self.usageFile = usageFile
        self.defaults = defaults
        self.workdir = workdir
        self.cliProvider = cliProvider
        self.httpProvider = httpProvider
        self.apiKeyLoader = apiKeyLoader
        self.monthlySelfUsage = SelfUsageLedger.monthlyTotals(from: usageFile)
    }

    func refreshUsageTotals() {
        monthlySelfUsage = SelfUsageLedger.monthlyTotals(from: usageFile)
    }

    func clearCache() {
        SummaryCacheStore.clearAll(directory: cacheDirectory)
        sessionSummaries.removeAll()
        projectSummaries.removeAll()
        lastError = nil
    }

    func cachedOrRuleBasedSessionSummary(
        for session: SessionRecord,
        projectName: String,
        copyMode: CopyMode = .plain
    ) -> SessionAISummary {
        let fingerprint = SummaryCacheStore.sessionFingerprint(for: session)
        if let memory = sessionSummaries[session.stableID], memory.fingerprint == fingerprint {
            return memory
        }
        if SummaryPreferences.isEnabled(in: defaults),
           let disk = SummaryCacheStore.loadSession(
            stableID: session.stableID,
            fingerprint: fingerprint,
            directory: cacheDirectory
           ) {
            sessionSummaries[session.stableID] = disk
            return disk
        }
        return Self.ruleBasedSessionSummary(for: session, projectName: projectName, copyMode: copyMode)
    }

    func cachedOrRuleBasedProjectSummary(
        for project: RepoProject,
        copyMode: CopyMode = .plain
    ) -> ProjectStatusAISummary {
        let fingerprint = SummaryCacheStore.projectFingerprint(for: project)
        let key = PathTools.canonical(project.path)
        if let memory = projectSummaries[key], memory.fingerprint == fingerprint {
            return memory
        }
        if SummaryPreferences.isEnabled(in: defaults),
           let disk = SummaryCacheStore.loadProject(
            projectPath: project.path,
            fingerprint: fingerprint,
            directory: cacheDirectory
           ) {
            projectSummaries[key] = disk
            return disk
        }
        return Self.ruleBasedProjectSummary(for: project, copyMode: copyMode)
    }

    @discardableResult
    func summarizeSessionIfNeeded(
        _ session: SessionRecord,
        projectName: String,
        copyMode: CopyMode = .plain
    ) async -> SessionAISummary {
        let fingerprint = SummaryCacheStore.sessionFingerprint(for: session)
        if let existing = sessionSummaries[session.stableID], existing.fingerprint == fingerprint, existing.isAIGenerated {
            return existing
        }
        if let cached = SummaryCacheStore.loadSession(
            stableID: session.stableID,
            fingerprint: fingerprint,
            directory: cacheDirectory
        ) {
            sessionSummaries[session.stableID] = cached
            return cached
        }

        let fallback = Self.ruleBasedSessionSummary(for: session, projectName: projectName, copyMode: copyMode)
        guard SummaryPreferences.isEnabled(in: defaults),
              SummaryPreferences.consentAccepted(in: defaults) else {
            return fallback
        }

        let inflightKey = "session:\(session.stableID)"
        guard !inFlightKeys.contains(inflightKey) else {
            return fallback
        }
        inFlightKeys.insert(inflightKey)
        defer { inFlightKeys.remove(inflightKey) }

        let request = SummaryPromptBuilder.sessionPrompt(
            session: session,
            projectName: projectName,
            copyMode: copyMode
        )

        do {
            let response = try await execute(request)
            let parsed = Self.parseSessionPayload(response.text)
            guard !parsed.headline.isEmpty else {
                return fallback
            }
            let summary = SessionAISummary(
                sessionStableID: session.stableID,
                headline: parsed.headline,
                blockerOrNext: parsed.secondary,
                isAIGenerated: true,
                generatedAt: Date(),
                fingerprint: fingerprint
            )
            sessionSummaries[session.stableID] = summary
            SummaryCacheStore.saveSession(summary, directory: cacheDirectory)
            lastError = nil
            return summary
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return fallback
        }
    }

    @discardableResult
    func summarizeProjectStatusIfNeeded(
        _ project: RepoProject,
        copyMode: CopyMode = .plain
    ) async -> ProjectStatusAISummary {
        await computeProjectStatus(project, copyMode: copyMode, bypassCache: false)
    }

    @discardableResult
    func forceRefreshProjectStatus(
        _ project: RepoProject,
        copyMode: CopyMode = .plain
    ) async -> ProjectStatusAISummary {
        await computeProjectStatus(project, copyMode: copyMode, bypassCache: true)
    }

    private func computeProjectStatus(
        _ project: RepoProject,
        copyMode: CopyMode,
        bypassCache: Bool
    ) async -> ProjectStatusAISummary {
        let fingerprint = SummaryCacheStore.projectFingerprint(for: project)
        let key = PathTools.canonical(project.path)
        if !bypassCache {
            if let existing = projectSummaries[key], existing.fingerprint == fingerprint, existing.isAIGenerated {
                return existing
            }
            if let cached = SummaryCacheStore.loadProject(
                projectPath: project.path,
                fingerprint: fingerprint,
                directory: cacheDirectory
            ) {
                projectSummaries[key] = cached
                return cached
            }
        }

        let fallback = Self.ruleBasedProjectSummary(for: project, copyMode: copyMode)
        guard SummaryPreferences.isEnabled(in: defaults),
              SummaryPreferences.consentAccepted(in: defaults) else {
            return fallback
        }

        let inflightKey = "project:\(key)"
        guard !inFlightKeys.contains(inflightKey) else {
            return fallback
        }
        inFlightKeys.insert(inflightKey)
        defer { inFlightKeys.remove(inflightKey) }

        let recentHeadline = project.sessions.recentSessions.first.map {
            cachedOrRuleBasedSessionSummary(for: $0, projectName: project.displayName, copyMode: copyMode).headline
        }
        let request = SummaryPromptBuilder.projectStatusPrompt(
            project: project,
            recentSessionHeadline: recentHeadline,
            copyMode: copyMode
        )

        do {
            let response = try await execute(request)
            let parsed = Self.parseProjectPayload(response.text)
            guard !parsed.headline.isEmpty else {
                return fallback
            }
            let summary = ProjectStatusAISummary(
                projectPath: project.path,
                headline: parsed.headline,
                suggestion: parsed.secondary,
                isAIGenerated: true,
                generatedAt: Date(),
                fingerprint: fingerprint
            )
            projectSummaries[key] = summary
            SummaryCacheStore.saveProject(summary, directory: cacheDirectory)
            lastError = nil
            return summary
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return fallback
        }
    }

    func generateHandoffMarkdown(
        for project: RepoProject,
        sessionLimit: Int = 3,
        copyMode: CopyMode = .plain
    ) async -> String? {
        guard SummaryPreferences.isEnabled(in: defaults),
              SummaryPreferences.consentAccepted(in: defaults) else {
            return nil
        }
        let request = SummaryPromptBuilder.handoffPrompt(
            project: project,
            sessionLimit: sessionLimit,
            copyMode: copyMode
        )
        do {
            let response = try await execute(request)
            let cleaned = SecretRedactor.redact(
                response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            ).text
            lastError = nil
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func generateCommitMessage(
        for project: RepoProject,
        changedFiles: [String],
        copyMode: CopyMode = .plain
    ) async -> String? {
        guard SummaryPreferences.isEnabled(in: defaults),
              SummaryPreferences.consentAccepted(in: defaults) else {
            return nil
        }
        let request = SummaryPromptBuilder.commitMessagePrompt(
            projectName: project.displayName,
            changedFiles: changedFiles,
            latestIntent: project.sessions.lastUserMessage,
            copyMode: copyMode
        )
        do {
            let response = try await execute(request)
            let firstLine = response.text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“” ")) }
                .first { !$0.isEmpty } ?? ""
            let redacted = SecretRedactor.redact(firstLine).text
            guard !redacted.isEmpty else { return nil }
            lastError = nil
            return String(redacted.prefix(60))
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func testConnection() async -> Result<String, SummaryProviderError> {
        let request = SummaryRequest(
            systemPrompt: "你是连通性检测助手，只回复一行简短确认文字。",
            userPrompt: "请回复：连接正常",
            maxOutputTokens: 24,
            jsonMode: false
        )
        do {
            let response = try await execute(request)
            lastError = nil
            return .success("\(response.providerLabel) 可用：\(String(response.text.prefix(40)))")
        } catch let error as SummaryProviderError {
            lastError = error.errorDescription
            return .failure(error)
        } catch {
            let wrapped = SummaryProviderError.transportError(error.localizedDescription)
            lastError = wrapped.errorDescription
            return .failure(wrapped)
        }
    }

    private func execute(_ request: SummaryRequest) async throws -> SummaryResponse {
        let config = SummaryPreferences.loadConfiguration(
            defaults: defaults,
            apiKeyLoader: apiKeyLoader,
            workdir: workdir
        )
        let provider: any SummaryProvider = config.kind == .agentCLI ? cliProvider : httpProvider
        let response = try await provider.generate(request, config: config)

        let entry = SelfUsageEntry(
            timestamp: Date(),
            providerKind: config.kind,
            model: response.model ?? (config.model.isEmpty ? response.providerLabel : config.model),
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            estimatedCostUSD: response.estimatedCostUSD
        )
        SelfUsageLedger.record(entry, to: usageFile)
        monthlySelfUsage = SelfUsageLedger.monthlyTotals(from: usageFile)
        return response
    }

    static func ruleBasedSessionSummary(
        for session: SessionRecord,
        projectName: String,
        copyMode: CopyMode
    ) -> SessionAISummary {
        let fingerprint = SummaryCacheStore.sessionFingerprint(for: session)
        let intent = session.primaryIntent.map { SecretRedactor.redact($0).text }
        let headline: String
        if let intent, !intent.isEmpty {
            headline = String(intent.prefix(48))
        } else if !session.touchedFiles.isEmpty {
            let firstFile = URL(fileURLWithPath: session.touchedFiles[0]).lastPathComponent
            headline = session.touchedFiles.count == 1
                ? "调整了 \(firstFile)"
                : "修改了 \(firstFile) 等 \(session.touchedFiles.count) 个文件"
        } else {
            headline = "\(projectName) · \(HomeDashboardModel.toolTitle(session.tool)) 对话"
        }

        let blockerOrNext: String? = if session.endedWithError {
            session.lastError.map { "上次失败：\(SecretRedactor.redact(String($0.prefix(60))).text)" }
                ?? (copyMode == .plain ? "上次结束时遇到问题，点开对话可继续排查" : "上次会话异常结束")
        } else if !session.touchedFiles.isEmpty {
            "涉及 \(session.touchedFiles.count) 个文件"
        } else {
            nil
        }

        return SessionAISummary(
            sessionStableID: session.stableID,
            headline: headline,
            blockerOrNext: blockerOrNext,
            isAIGenerated: false,
            generatedAt: Date(),
            fingerprint: fingerprint
        )
    }

    static func ruleBasedProjectSummary(
        for project: RepoProject,
        copyMode: CopyMode
    ) -> ProjectStatusAISummary {
        let fingerprint = SummaryCacheStore.projectFingerprint(for: project)
        let headline = FizzCopy.projectStatusSummary(
            dirtyCount: project.dirtyCount,
            ahead: project.ahead,
            behind: project.behind,
            mode: copyMode
        )

        let suggestion: String? = if project.dirtyCount > 0 {
            copyMode == .plain ? "点「存个版本」把这些改动安全记下来" : "建议提交当前工作区改动"
        } else if project.ahead > 0 {
            copyMode == .plain ? "还有版本没同步到云端，有空推上去更安心" : "可将本地提交推送到远端"
        } else if project.behind > 0 {
            copyMode == .plain ? "云端有新进展，拉取一下保持最新" : "建议拉取远端最新提交"
        } else {
            nil
        }

        return ProjectStatusAISummary(
            projectPath: project.path,
            headline: headline,
            suggestion: suggestion,
            isAIGenerated: false,
            generatedAt: Date(),
            fingerprint: fingerprint
        )
    }

    static func parseSessionPayload(_ raw: String) -> (headline: String, secondary: String?) {
        if let json = decodeJSONDictionary(raw),
           let headline = nonEmptyTrimmed(json["headline"]) {
            let blocker = nonEmptyTrimmed(json["blockerOrNext"]) ?? nonEmptyTrimmed(json["next"])
            return (SecretRedactor.redact(headline).text, blocker.map { SecretRedactor.redact($0).text })
        }
        return parsePlainLines(raw)
    }

    static func parseProjectPayload(_ raw: String) -> (headline: String, secondary: String?) {
        if let json = decodeJSONDictionary(raw),
           let headline = nonEmptyTrimmed(json["headline"]) {
            let suggestion = nonEmptyTrimmed(json["suggestion"]) ?? nonEmptyTrimmed(json["next"])
            return (SecretRedactor.redact(headline).text, suggestion.map { SecretRedactor.redact($0).text })
        }
        return parsePlainLines(raw)
    }

    private static func decodeJSONDictionary(_ raw: String) -> [String: String]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 3 {
                text = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start ... end])
        }
        guard let data = text.data(using: .utf8),
              let rawObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: String] = [:]
        for (key, value) in rawObj {
            if let str = value as? String {
                result[key] = str
            }
        }
        return result
    }

    private static func parsePlainLines(_ raw: String) -> (headline: String, secondary: String?) {
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else {
            return ("", nil)
        }
        let headline = SecretRedactor.redact(String(first.prefix(64))).text
        let second = lines.dropFirst().first.map { SecretRedactor.redact(String($0.prefix(64))).text }
        return (headline, second)
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
