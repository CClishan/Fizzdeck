import Foundation
import XCTest
@testable import FizzDeck

@MainActor
final class SummaryEngineTests: ChineseInterfaceTestCase {
    private func makeTempDirectory(name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-summary-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "dev.fizzdeck.tests.summary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    private func makeHTTPResponse(url: URL, statusCode: Int, body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }

    func testEndpointURLNormalization() {
        XCTAssertEqual(
            OpenAICompatibleSummaryProvider.endpointURL(from: "https://api.openai.com")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            OpenAICompatibleSummaryProvider.endpointURL(from: "https://api.openai.com/v1/")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            OpenAICompatibleSummaryProvider.endpointURL(from: "http://127.0.0.1:11434/v1/chat/completions")?.absoluteString,
            "http://127.0.0.1:11434/v1/chat/completions"
        )
        XCTAssertNil(OpenAICompatibleSummaryProvider.endpointURL(from: "ftp://example.com"))
        XCTAssertNil(OpenAICompatibleSummaryProvider.endpointURL(from: "not a url"))
    }

    func testOpenAICompatibleProviderAuthHeadersAndErrors() async throws {
        final class RequestRecorder: @unchecked Sendable {
            var captured: [URLRequest] = []
        }

        let recorder = RequestRecorder()
        let provider = OpenAICompatibleSummaryProvider { request in
            recorder.captured.append(request)
            let url = request.url ?? URL(string: "https://example.com")!
            let json = """
            {
              "model": "gpt-4o-mini",
              "choices": [{"message": {"content": "{\\"headline\\":\\"完成了登录页圆角按钮\\",\\"blockerOrNext\\":\\"\\"}"}}],
              "usage": {"prompt_tokens": 120, "completion_tokens": 30}
            }
            """
            return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let req = SummaryRequest(systemPrompt: "sys", userPrompt: "usr", maxOutputTokens: 120, jsonMode: true)

        let byokConfig = SummaryProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "sk-test-1234567890"
        )
        let byokResp = try await provider.generate(req, config: byokConfig)
        XCTAssertEqual(recorder.captured.last?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-1234567890")
        XCTAssertEqual(byokResp.inputTokens, 120)
        XCTAssertEqual(byokResp.outputTokens, 30)
        XCTAssertNotNil(byokResp.estimatedCostUSD)

        let localConfig = SummaryProviderConfiguration(
            kind: .localModel,
            baseURL: "http://127.0.0.1:11434/v1",
            model: "qwen2.5:7b",
            apiKey: "should-not-be-sent"
        )
        let localResp = try await provider.generate(req, config: localConfig)
        XCTAssertNil(recorder.captured.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(localResp.estimatedCostUSD, 0)

        let failingProvider = OpenAICompatibleSummaryProvider { request in
            let url = request.url ?? URL(string: "https://example.com")!
            let errBody = #"{"error":{"message":"invalid api key"}}"#
            return (Data(errBody.utf8), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await failingProvider.generate(req, config: byokConfig)
            XCTFail("Expected 401 error")
        } catch let error as SummaryProviderError {
            XCTAssertEqual(error, .httpStatus(401, "invalid api key"))
        }
    }

    func testPromptBuildersRedactSecretsAndEnforceLengthCap() {
        let longText = String(repeating: "功能实现细节 ", count: 900)
        let session = SessionRecord(
            tool: "claude",
            id: "s-1",
            cwd: "/tmp/app",
            startedAt: Date().addingTimeInterval(-600),
            modified: Date(),
            lastUser: "token sk-live-secret9876543210123456 " + longText,
            firstUser: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 " + longText,
            touchedFiles: ["/tmp/app/.env.secret", "/tmp/app/Sources/App.swift"],
            lastError: "ghp_1234567890abcdefghijklmnopqrstuvwxyz failed",
            endedWithError: true,
            turnCount: 4,
            durationMinutes: 10
        )

        let request = SummaryPromptBuilder.sessionPrompt(session: session, projectName: "demo")
        XCTAssertLessThanOrEqual(request.userPrompt.count, SummaryPromptBuilder.maxPromptCharacters)
        XCTAssertFalse(SecretRedactor.containsSecret(request.userPrompt))
        XCTAssertFalse(request.userPrompt.contains("sk-live-secret9876543210123456"))
        XCTAssertFalse(request.userPrompt.contains("ghp_1234567890abcdefghijklmnopqrstuvwxyz"))

        let preview = SummaryPromptBuilder.sampleRedactedPromptPreview()
        XCTAssertFalse(SecretRedactor.containsSecret(preview))
        XCTAssertLessThanOrEqual(preview.count, SummaryPromptBuilder.maxPromptCharacters)
    }

    func testSummaryLanguageSeparatesCachesWithoutChangingSessionIdentity() throws {
        let dir = try makeTempDirectory(name: "languages")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        SummaryPreferences.setEnabled(true, in: defaults)
        let engine = SummaryEngine(cacheDirectory: dir, usageFile: dir.appendingPathComponent("usage.json"), defaults: defaults)
        let session = SessionRecord(tool: "codex", id: "same-session", cwd: nil, startedAt: nil, modified: Date(),
                                    firstUser: "保留任务原文")
        for (language, headline) in [(FizzLanguage.chinese, "中文摘要"), (.english, "English summary")] {
            FizzL10n.$languageOverride.withValue(language) {
                let fallback = engine.cachedOrRuleBasedSessionSummary(for: session, projectName: "项目")
                XCTAssertEqual(fallback.headline, "保留任务原文")
                SummaryCacheStore.saveSession(.init(sessionStableID: session.stableID, headline: headline, blockerOrNext: nil,
                    isAIGenerated: true, generatedAt: Date(), fingerprint: fallback.fingerprint), directory: dir)
                XCTAssertEqual(engine.cachedOrRuleBasedSessionSummary(for: session, projectName: "项目").headline, headline)
            }
        }
        FizzL10n.$languageOverride.withValue(.chinese) {
            XCTAssertEqual(engine.cachedOrRuleBasedSessionSummary(for: session, projectName: "项目").headline, "中文摘要")
        }
    }

    func testExistingProviderErrorFollowsInterfaceLanguage() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        SummaryPreferences.setProviderKind(.localModel, in: defaults)
        defaults.set("invalid", forKey: SummaryPreferences.localBaseURLKey)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = SummaryEngine(cacheDirectory: dir, usageFile: dir.appendingPathComponent("usage.json"), defaults: defaults)
        _ = await FizzL10n.$languageOverride.withValue(.chinese) { await engine.testConnection() }
        FizzL10n.$languageOverride.withValue(.english) {
            XCTAssertEqual(engine.lastError, "Invalid endpoint. Check the base URL.")
        }
    }

    func testSummaryEngineCacheHitInvalidationAndSilentFallback() async throws {
        let dir = try makeTempDirectory(name: "engine")
        defer { try? FileManager.default.removeItem(at: dir) }

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        final class CounterProvider: SummaryProvider, @unchecked Sendable {
            var calls = 0
            var shouldFail = false
            func generate(_ request: SummaryRequest, config: SummaryProviderConfiguration) async throws -> SummaryResponse {
                calls += 1
                if shouldFail {
                    throw SummaryProviderError.timedOut
                }
                return SummaryResponse(
                    text: #"{"headline":"把首页卡片改成了单列清晰版","blockerOrNext":"点存个版本即可保存"}"#,
                    model: "gpt-4o-mini",
                    inputTokens: 100,
                    outputTokens: 25,
                    estimatedCostUSD: 0.001,
                    providerLabel: "Mock"
                )
            }
        }

        let provider = CounterProvider()
        let cacheDir = dir.appendingPathComponent("summaries", isDirectory: true)
        let usageFile = dir.appendingPathComponent("self_usage.json")
        let workdir = dir.appendingPathComponent("llm-workdir", isDirectory: true)

        let engine = SummaryEngine(
            cacheDirectory: cacheDir,
            usageFile: usageFile,
            defaults: defaults,
            workdir: workdir,
            cliProvider: provider,
            httpProvider: provider
        )

        var session = SessionRecord(
            tool: "claude",
            id: "sess-42",
            cwd: "/tmp/demo",
            startedAt: Date().addingTimeInterval(-300),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            firstUser: "优化设置页面间距",
            turnCount: 3,
            durationMinutes: 5
        )

        // Default OFF -> falls back to rule-based with zero provider calls.
        let offSummary = await engine.summarizeSessionIfNeeded(session, projectName: "demo")
        XCTAssertFalse(offSummary.isAIGenerated)
        XCTAssertEqual(provider.calls, 0)

        // Enable + accept consent -> triggers provider once, then hits cache.
        SummaryPreferences.setEnabled(true, in: defaults)
        SummaryPreferences.setConsentAccepted(true, in: defaults)
        let aiSummary = await engine.summarizeSessionIfNeeded(session, projectName: "demo")
        XCTAssertTrue(aiSummary.isAIGenerated)
        XCTAssertEqual(aiSummary.headline, "把首页卡片改成了单列清晰版")
        XCTAssertEqual(provider.calls, 1)

        // Second call with identical session + new engine instance reads disk cache.
        let engine2 = SummaryEngine(
            cacheDirectory: cacheDir,
            usageFile: usageFile,
            defaults: defaults,
            workdir: workdir,
            cliProvider: provider,
            httpProvider: provider
        )
        let cached = await engine2.summarizeSessionIfNeeded(session, projectName: "demo")
        XCTAssertEqual(cached.headline, aiSummary.headline)
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(engine2.monthlySelfUsage.callCount, 1)
        XCTAssertEqual(engine2.monthlySelfUsage.totalTokens, 125)

        // Modified mtime invalidates cache; provider failure falls back silently and stores error for diagnostics.
        session = SessionRecord(
            tool: "claude",
            id: "sess-42",
            cwd: "/tmp/demo",
            startedAt: Date().addingTimeInterval(-300),
            modified: Date(timeIntervalSince1970: 1_700_000_999),
            firstUser: "优化设置页面间距",
            turnCount: 4,
            durationMinutes: 7
        )
        provider.shouldFail = true
        let fallbackOnError = await engine2.summarizeSessionIfNeeded(session, projectName: "demo")
        XCTAssertFalse(fallbackOnError.isAIGenerated)
        XCTAssertEqual(provider.calls, 2)
        XCTAssertNotNil(engine2.lastError)
    }

    func testSelfUsageLedgerAndCostBreakdownSelfSlice() throws {
        let dir = try makeTempDirectory(name: "ledger")
        defer { try? FileManager.default.removeItem(at: dir) }
        let usageFile = dir.appendingPathComponent("self_usage.json")
        let now = Date()

        SelfUsageLedger.record(
            SelfUsageEntry(
                timestamp: now.addingTimeInterval(-3_600),
                providerKind: .openAICompatible,
                model: "gpt-4o-mini",
                inputTokens: 400,
                outputTokens: 100,
                estimatedCostUSD: 0.02
            ),
            to: usageFile,
            now: now
        )
        SelfUsageLedger.record(
            SelfUsageEntry(
                timestamp: now.addingTimeInterval(-40 * 86_400),
                providerKind: .agentCLI,
                model: nil,
                inputTokens: 900,
                outputTokens: 200,
                estimatedCostUSD: 0.05
            ),
            to: usageFile,
            now: now
        )

        let weekly = SelfUsageLedger.weeklyTotals(from: usageFile, now: now)
        XCTAssertEqual(weekly.callCount, 1)
        XCTAssertEqual(weekly.totalTokens, 500)
        XCTAssertEqual(weekly.estimatedCostUSD, 0.02, accuracy: 0.0001)

        let claudeSession = SessionRecord(
            tool: "claude",
            id: "c1",
            cwd: "/tmp/p1",
            startedAt: now.addingTimeInterval(-1_800),
            modified: now,
            usage: TokenUsage(inputTokens: 1_000, outputTokens: 200, totalTokens: 1_200),
            costUSD: 0.08
        )
        let project = RepoProject(
            path: "/tmp/p1",
            name: "p1",
            displayName: "p1",
            group: "dev",
            kind: .web,
            detectedTools: [],
            recent: now,
            branch: "main",
            lastCommit: nil,
            dirtyCount: 0,
            changes: .zero,
            ahead: 0,
            behind: 0,
            weekly: [:],
            stacks: [],
            size: .empty,
            cleanup: .empty,
            run: nil,
            sessions: SessionSummary(
                detected: ["claude"],
                lastSessionAt: now,
                lastUserMessage: "hi",
                lastSessionID: "c1",
                lastTool: "claude",
                sessionCount: 1,
                byTool: [],
                recentSessions: [claudeSession]
            ),
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: false,
            color: nil,
            note: "",
            port: .noPreview
        )

        let segments = DashboardMetrics.costBreakdown(
            sessions: WeeklyRecapService.build(projects: [project], now: now).analysis.sessions,
            mode: .byTool,
            selfUsage: weekly
        )
        let selfSegment = segments.first { $0.id == "fizzdeck-self" }
        XCTAssertNotNil(selfSegment)
        XCTAssertEqual(selfSegment?.label, "FizzDeck 自身")
        XCTAssertEqual(selfSegment?.tokens, 500)
        XCTAssertEqual(selfSegment?.costUSD ?? 0, 0.02, accuracy: 0.0001)
    }

    func testSessionIndexFiltersInternalLLMWorkdir() throws {
        let dir = try makeTempDirectory(name: "isolation")
        defer { try? FileManager.default.removeItem(at: dir) }

        let fakeHome = dir.appendingPathComponent("home", isDirectory: true)
        let llmWorkdir = dir.appendingPathComponent("llm-workdir", isDirectory: true)
        let normalProject = dir.appendingPathComponent("user-app", isDirectory: true)
        try FileManager.default.createDirectory(at: llmWorkdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: normalProject, withIntermediateDirectories: true)

        let claudeProjDir = fakeHome.appendingPathComponent(".claude/projects/test-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeProjDir, withIntermediateDirectories: true)

        let pollutedJSONL = """
        {"type":"user","cwd":"\(llmWorkdir.path)","sessionId":"internal-1","timestamp":"2026-11-27T01:00:00Z","message":{"role":"user","content":"总结一下"}}
        """
        let cleanJSONL = """
        {"type":"user","cwd":"\(normalProject.path)","sessionId":"user-1","timestamp":"2026-11-27T02:00:00Z","message":{"role":"user","content":"帮我修个按钮"}}
        """
        try pollutedJSONL.write(to: claudeProjDir.appendingPathComponent("internal.jsonl"), atomically: true, encoding: .utf8)
        try cleanJSONL.write(to: claudeProjDir.appendingPathComponent("clean.jsonl"), atomically: true, encoding: .utf8)

        let records = SessionIndex.build(
            homeDirectory: fakeHome,
            cacheFile: dir.appendingPathComponent("session_cache.json"),
            excludedCwd: llmWorkdir
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, "clean")

        let cwdMap = SessionIndex.buildLightweightCwdMap(
            homeDirectory: fakeHome,
            cacheFile: dir.appendingPathComponent("session_cache.json"),
            excludedCwd: llmWorkdir
        )
        let claudeCwds = cwdMap["claude"] ?? []
        XCTAssertTrue(claudeCwds.contains(PathTools.canonical(normalProject.path)))
        XCTAssertFalse(claudeCwds.contains(PathTools.canonical(llmWorkdir.path)))
    }
}
