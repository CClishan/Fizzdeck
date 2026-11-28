import Foundation

enum SummaryProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case agentCLI
    case openAICompatible
    case localModel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agentCLI: FizzL10n.text("Agent CLI（推荐 · 免 Key）", "Agent CLI (no key needed)")
        case .openAICompatible: FizzL10n.text("OpenAI 兼容 API（Keychain）", "OpenAI-compatible API (Keychain)")
        case .localModel: FizzL10n.text("本地模型（Ollama / LM Studio）", "Local model (Ollama or LM Studio)")
        }
    }

    var shortTitle: String {
        switch self {
        case .agentCLI: "Agent CLI"
        case .openAICompatible: "API Key"
        case .localModel: FizzL10n.text("本地模型", "Local model")
        }
    }
}

enum AgentCLIKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: FizzL10n.text("自动选择（Claude / Codex / Gemini）", "Automatic (Claude, Codex, or Gemini)")
        case .claude: "Claude Code (claude -p)"
        case .codex: "Codex CLI (codex exec)"
        case .gemini: "Gemini CLI (gemini -p)"
        }
    }

    var binaryName: String? {
        switch self {
        case .auto: nil
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        }
    }
}

struct SummaryProviderConfiguration: Sendable, Equatable {
    let kind: SummaryProviderKind
    let agentCLI: AgentCLIKind
    let baseURL: String
    let model: String
    let apiKey: String?
    let timeoutSeconds: TimeInterval
    let workdir: URL

    init(
        kind: SummaryProviderKind,
        agentCLI: AgentCLIKind = .auto,
        baseURL: String = "",
        model: String = "",
        apiKey: String? = nil,
        timeoutSeconds: TimeInterval = 25,
        workdir: URL = AppPaths.llmWorkdir
    ) {
        self.kind = kind
        self.agentCLI = agentCLI
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
        self.workdir = workdir
    }
}

enum SummaryPreferences {
    static let enabledKey = "fizzdeck.summary.enabled"
    static let consentAcceptedKey = "fizzdeck.summary.consentAccepted"
    static let providerKindKey = "fizzdeck.summary.providerKind"
    static let agentCLIKey = "fizzdeck.summary.agentCLI"
    static let apiBaseURLKey = "fizzdeck.summary.apiBaseURL"
    static let apiModelKey = "fizzdeck.summary.apiModel"
    static let localBaseURLKey = "fizzdeck.summary.localBaseURL"
    static let localModelKey = "fizzdeck.summary.localModel"
    static let keychainAccount = "fizzdeck.summary.openai.apikey"

    static let defaultAPIBaseURL = "https://api.openai.com/v1"
    static let defaultAPIModel = "gpt-4o-mini"
    static let defaultLocalBaseURL = "http://127.0.0.1:11434/v1"
    static let defaultLocalModel = "qwen2.5:7b"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: enabledKey)
    }

    static func consentAccepted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: consentAcceptedKey)
    }

    static func setConsentAccepted(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: consentAcceptedKey)
    }

    static func providerKind(in defaults: UserDefaults = .standard) -> SummaryProviderKind {
        guard let raw = defaults.string(forKey: providerKindKey),
              let kind = SummaryProviderKind(rawValue: raw) else {
            return .agentCLI
        }
        return kind
    }

    static func setProviderKind(_ kind: SummaryProviderKind, in defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: providerKindKey)
    }

    static func agentCLI(in defaults: UserDefaults = .standard) -> AgentCLIKind {
        guard let raw = defaults.string(forKey: agentCLIKey),
              let cli = AgentCLIKind(rawValue: raw) else {
            return .auto
        }
        return cli
    }

    static func setAgentCLI(_ cli: AgentCLIKind, in defaults: UserDefaults = .standard) {
        defaults.set(cli.rawValue, forKey: agentCLIKey)
    }

    static func apiBaseURL(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: apiBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultAPIBaseURL : value
    }

    static func apiModel(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: apiModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultAPIModel : value
    }

    static func localBaseURL(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: localBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultLocalBaseURL : value
    }

    static func localModel(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: localModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultLocalModel : value
    }

    static func loadConfiguration(
        defaults: UserDefaults = .standard,
        apiKeyLoader: () -> String? = { KeychainStore.load(account: keychainAccount) },
        workdir: URL = AppPaths.llmWorkdir
    ) -> SummaryProviderConfiguration {
        let kind = providerKind(in: defaults)
        switch kind {
        case .agentCLI:
            return SummaryProviderConfiguration(
                kind: .agentCLI,
                agentCLI: agentCLI(in: defaults),
                workdir: workdir
            )
        case .openAICompatible:
            return SummaryProviderConfiguration(
                kind: .openAICompatible,
                baseURL: apiBaseURL(in: defaults),
                model: apiModel(in: defaults),
                apiKey: apiKeyLoader(),
                workdir: workdir
            )
        case .localModel:
            return SummaryProviderConfiguration(
                kind: .localModel,
                baseURL: localBaseURL(in: defaults),
                model: localModel(in: defaults),
                apiKey: nil,
                workdir: workdir
            )
        }
    }
}

struct SummaryRequest: Sendable, Equatable {
    let systemPrompt: String
    let userPrompt: String
    let maxOutputTokens: Int
    let jsonMode: Bool

    init(
        systemPrompt: String,
        userPrompt: String,
        maxOutputTokens: Int = 220,
        jsonMode: Bool = true
    ) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.maxOutputTokens = maxOutputTokens
        self.jsonMode = jsonMode
    }
}

struct SummaryResponse: Sendable, Equatable {
    let text: String
    let model: String?
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double?
    let providerLabel: String
}

enum SummaryProviderError: Error, LocalizedError, Equatable, Sendable {
    case invalidBaseURL, missingModel, missingKey
    case cliNotFound(String), cliLaunchFailed(String), cliExited(Int32)
    case timedOut, nonHTTPResponse, emptySummary
    case httpStatus(Int, String), transportError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: FizzL10n.text("接口地址格式无效，请检查 Base URL", "Invalid endpoint. Check the base URL.")
        case .missingModel: FizzL10n.text("请填写要使用的模型名称", "Enter a model name.")
        case .missingKey: FizzL10n.text("请先填入并保存 API Key", "Enter and save your API key first.")
        case .cliNotFound(let name): FizzL10n.text("本机未检测到可用的 \(name) 命令", "No \(name) command was found on this Mac.")
        case .cliLaunchFailed(let name): FizzL10n.text("调用失败：无法启动 \(name)", "Couldn’t start \(name).")
        case .cliExited(let code): FizzL10n.text("调用失败：退出码 \(code)", "The CLI exited with code \(code).")
        case .timedOut: FizzL10n.text("总结生成超时，已自动回退到规则摘要", "The request timed out. Using a local summary.")
        case .nonHTTPResponse: FizzL10n.text("无法解析模型返回内容：未收到有效的 HTTP 响应", "No valid HTTP response was received.")
        case .emptySummary: FizzL10n.text("无法解析模型返回内容：返回结果中没有摘要文本", "The response contained no summary text.")
        case .httpStatus(let code, let detail): FizzL10n.text("接口返回错误（HTTP \(code)）：\(detail)", "The provider returned HTTP \(code): \(detail)")
        case .transportError(let detail): FizzL10n.text("调用失败：\(detail)", "Request failed: \(detail)")
        }
    }
}

protocol SummaryProvider: Sendable {
    func generate(
        _ request: SummaryRequest,
        config: SummaryProviderConfiguration
    ) async throws -> SummaryResponse
}

struct AgentCLISummaryProvider: SummaryProvider {
    typealias Runner = @Sendable (_ executable: String, _ arguments: [String], _ workdir: URL, _ timeout: TimeInterval) async -> ShellOutput?
    typealias ExecutableLocator = @Sendable (_ command: String) async -> String?

    private let runner: Runner
    private let locateExecutable: ExecutableLocator

    init(
        locateExecutable: @escaping ExecutableLocator = AgentCLISummaryProvider.defaultLocateExecutable,
        runner: @escaping Runner = AgentCLISummaryProvider.defaultRun
    ) {
        self.locateExecutable = locateExecutable
        self.runner = runner
    }

    func generate(
        _ request: SummaryRequest,
        config: SummaryProviderConfiguration
    ) async throws -> SummaryResponse {
        let resolved = try await resolveCLI(preference: config.agentCLI)
        try? FileManager.default.createDirectory(at: config.workdir, withIntermediateDirectories: true)

        let combinedPrompt = """
        \(request.systemPrompt)

        \(request.userPrompt)
        """
        let arguments = cliArguments(for: resolved.kind, prompt: combinedPrompt)
        let output = await runner(resolved.executable, arguments, config.workdir, config.timeoutSeconds)

        guard let output else {
            throw SummaryProviderError.cliLaunchFailed(resolved.kind.binaryName ?? "CLI")
        }
        if output.timedOut {
            throw SummaryProviderError.timedOut
        }
        guard output.succeeded else {
            let trimmed = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw SummaryProviderError.cliExited(output.status) }
            throw SummaryProviderError.transportError(SecretRedactor.redactedPrefix(trimmed, 160))
        }

        return parseCLIOutput(output.text, cli: resolved.kind)
    }

    func resolveCLI(preference: AgentCLIKind) async throws -> (kind: AgentCLIKind, executable: String) {
        let candidates: [AgentCLIKind] = switch preference {
        case .auto: [.claude, .codex, .gemini]
        case .claude: [.claude]
        case .codex: [.codex]
        case .gemini: [.gemini]
        }

        for candidate in candidates {
            if let binary = candidate.binaryName, let path = await locateExecutable(binary) {
                return (candidate, path)
            }
        }

        let name = preference == .auto
            ? "claude / codex / gemini"
            : (preference.binaryName ?? preference.title)
        throw SummaryProviderError.cliNotFound(name)
    }

    func cliArguments(for cli: AgentCLIKind, prompt: String) -> [String] {
        switch cli {
        case .claude, .auto:
            return ["-p", prompt, "--output-format", "json"]
        case .codex:
            return ["exec", "--skip-git-repo-check", prompt]
        case .gemini:
            return ["-p", prompt]
        }
    }

    func parseCLIOutput(_ rawText: String, cli: AgentCLIKind) -> SummaryResponse {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cli == .claude,
           let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ClaudeCLIJSONOutput.self, from: data),
           let resultText = payload.result?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resultText.isEmpty {
            let inputTokens = (payload.usage?.input_tokens ?? 0)
                + (payload.usage?.cache_read_input_tokens ?? 0)
                + (payload.usage?.cache_creation_input_tokens ?? 0)
            let outputTokens = payload.usage?.output_tokens ?? 0
            return SummaryResponse(
                text: resultText,
                model: payload.model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                estimatedCostUSD: payload.total_cost_usd,
                providerLabel: "Claude CLI"
            )
        }

        return SummaryResponse(
            text: trimmed,
            model: nil,
            inputTokens: 0,
            outputTokens: 0,
            estimatedCostUSD: nil,
            providerLabel: cli == .codex ? "Codex CLI" : (cli == .gemini ? "Gemini CLI" : "Agent CLI")
        )
    }

    static let defaultLocateExecutable: ExecutableLocator = { command in
        let fileManager = FileManager.default
        let searchRoots = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            AppPaths.home.appendingPathComponent(".local/bin").path,
            AppPaths.home.appendingPathComponent(".npm-global/bin").path,
        ]
        for dir in searchRoots {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if let path = await Shell.output("/usr/bin/which", [command], timeout: 2)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static let defaultRun: Runner = { executable, arguments, workdir, timeout in
        await Shell.run(executable, arguments, cwd: workdir, timeout: timeout)
    }
}

private struct ClaudeCLIJSONOutput: Decodable {
    struct Usage: Decodable {
        let input_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let output_tokens: Int?
    }

    let result: String?
    let total_cost_usd: Double?
    let usage: Usage?
    let model: String?
}

struct OpenAICompatibleSummaryProvider: SummaryProvider {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    init(transport: @escaping Transport = OpenAICompatibleSummaryProvider.defaultTransport) {
        self.transport = transport
    }

    func generate(
        _ request: SummaryRequest,
        config: SummaryProviderConfiguration
    ) async throws -> SummaryResponse {
        guard let url = Self.endpointURL(from: config.baseURL) else {
            throw SummaryProviderError.invalidBaseURL
        }

        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw SummaryProviderError.missingModel
        }

        let trimmedKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if config.kind == .openAICompatible && trimmedKey.isEmpty {
            throw SummaryProviderError.missingKey
        }

        do {
            return try await performRequest(
                url: url,
                model: model,
                apiKey: config.kind == .localModel ? nil : trimmedKey,
                request: request,
                includeResponseFormat: request.jsonMode,
                timeout: config.timeoutSeconds,
                kind: config.kind
            )
        } catch let SummaryProviderError.httpStatus(code, detail)
            where code == 400 && request.jsonMode && detail.localizedCaseInsensitiveContains("response_format") {
            return try await performRequest(
                url: url,
                model: model,
                apiKey: config.kind == .localModel ? nil : trimmedKey,
                request: request,
                includeResponseFormat: false,
                timeout: config.timeoutSeconds,
                kind: config.kind
            )
        }
    }

    private func performRequest(
        url: URL,
        model: String,
        apiKey: String?,
        request: SummaryRequest,
        includeResponseFormat: Bool,
        timeout: TimeInterval,
        kind: SummaryProviderKind
    ) async throws -> SummaryResponse {
        let payload = ChatCompletionsRequestBody(
            model: model,
            messages: [
                .init(role: "system", content: request.systemPrompt),
                .init(role: "user", content: request.userPrompt),
            ],
            temperature: 0.2,
            max_tokens: request.maxOutputTokens,
            response_format: includeResponseFormat ? .init(type: "json_object") : nil
        )

        var urlRequest = URLRequest(url: url, timeoutInterval: max(5, timeout))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw SummaryProviderError.timedOut
        } catch {
            throw SummaryProviderError.transportError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SummaryProviderError.nonHTTPResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let errorMessage = Self.extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SummaryProviderError.httpStatus(http.statusCode, errorMessage)
        }

        guard let decoded = try? JSONDecoder().decode(ChatCompletionsResponseBody.self, from: data),
              let content = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw SummaryProviderError.emptySummary
        }

        let inputTokens = decoded.usage?.prompt_tokens ?? 0
        let outputTokens = decoded.usage?.completion_tokens ?? 0
        let resolvedModel = decoded.model ?? model
        let estimatedCost: Double? = if kind == .localModel {
            0
        } else {
            PricingCatalog.estimate(
                model: resolvedModel,
                usage: TokenUsage(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    totalTokens: inputTokens + outputTokens
                )
            )
        }

        return SummaryResponse(
            text: content,
            model: resolvedModel,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostUSD: estimatedCost,
            providerLabel: kind == .localModel ? FizzL10n.text("本地模型", "Local model") : FizzL10n.text("OpenAI 兼容 API", "OpenAI-compatible API")
        )
    }

    static func endpointURL(from rawBaseURL: String) -> URL? {
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        let withoutTrailingSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if withoutTrailingSlash.hasSuffix("/chat/completions") {
            return URL(string: withoutTrailingSlash)
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return URL(string: "\(withoutTrailingSlash)/v1/chat/completions")
        }
        return URL(string: "\(withoutTrailingSlash)/chat/completions")
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return SecretRedactor.redactedPrefix(message, 160)
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return SecretRedactor.redactedPrefix(text, 160)
        }
        return nil
    }

    static let defaultTransport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }
}

private struct ChatCompletionsRequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
    let response_format: ResponseFormat?
}

private struct ChatCompletionsResponseBody: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
    }

    let model: String?
    let choices: [Choice]
    let usage: Usage?
}

private struct APIErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable {
        let message: String?
    }

    let error: ErrorDetail?
}
