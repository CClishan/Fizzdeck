import Foundation

/// The provider boundary accepts numeric totals only. Local Markdown includes paths and names.
struct WeeklyRecapFigures: Equatable, Sendable {
    let projects: Int
    let sessions: Int
    let files: Int
    let versions: Int
    let cost: SessionCostTotal

    init(_ recap: WeeklyRecap) {
        projects = recap.activeProjects.count
        sessions = recap.sessionCount
        files = recap.changedFileCount
        versions = recap.savedVersionCount
        cost = recap.cost
    }

    var request: SummaryRequest {
        SummaryRequest(
            systemPrompt: FizzL10n.text("用一两句简短中文润色这份活动统计。只使用给出的数字，不推断项目内容、成效或阻塞。不调用工具。返回 JSON 对象，唯一字段 summary 是润色后的文字。", "Summarize these activity totals in one or two short English sentences. Use only the supplied figures. Do not infer project details, outcomes, or blockers. Do not call tools. Return a JSON object with a single summary field."),
            userPrompt: SecretRedactor.redact(FizzL10n.text("活跃项目：\(projects)；对话：\(sessions)；涉及文件：\(files)；提交：\(versions)；估算费用：\(cost.description)。", "Active projects: \(projects); sessions: \(sessions); files: \(files); commits: \(versions); estimated cost: \(cost.description).")).text,
            maxOutputTokens: 180, jsonMode: true
        )
    }
}

extension WeeklyRecapService {
    @MainActor
    static func polish(
        _ figures: WeeklyRecapFigures, consentFor providerKind: SummaryProviderKind?,
        defaults: UserDefaults = .standard, usageFile: URL = AppPaths.selfUsageFile,
        providerFor: (SummaryProviderKind) -> any SummaryProvider = {
            $0 == .agentCLI ? AgentCLISummaryProvider() : OpenAICompatibleSummaryProvider()
        }
    ) async -> String? {
        guard let providerKind, !Task.isCancelled, figures.projects > 0,
              SummaryPreferences.isEnabled(in: defaults), SummaryPreferences.consentAccepted(in: defaults),
              providerKind == SummaryPreferences.providerKind(in: defaults) else { return nil }
        let config = SummaryPreferences.loadConfiguration(defaults: defaults)
        guard let response = try? await providerFor(config.kind).generate(figures.request, config: config) else { return nil }
        SelfUsageLedger.record(SelfUsageEntry(
            timestamp: Date(), providerKind: config.kind, model: response.model ?? config.model,
            inputTokens: response.inputTokens, outputTokens: response.outputTokens, estimatedCostUSD: response.estimatedCostUSD
        ), to: usageFile)
        // Some CLIs also write terminal diagnostics. Only a structured reply can become copyable text.
        struct Reply: Decodable { let summary: String }
        guard !Task.isCancelled else { return nil }
        let decoder = JSONDecoder()
        let raw = response.text
        let reply = (try? decoder.decode(Reply.self, from: Data(raw.utf8)))
            ?? raw.split(whereSeparator: \.isNewline).reversed().lazy.compactMap { line in
                try? decoder.decode(Reply.self, from: Data(line.utf8))
            }.first
        guard let text = reply?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 600 else { return nil }
        return SecretRedactor.redact(text).text
    }
}
