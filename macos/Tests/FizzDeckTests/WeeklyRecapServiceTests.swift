import Foundation
import XCTest
@testable import FizzDeck

final class WeeklyRecapServiceTests: XCTestCase {
    private func makeProject(
        path: String,
        name: String,
        sessions: [SessionRecord],
        weekly: [String: Int] = [:]
    ) -> RepoProject {
        RepoProject(
            path: path,
            name: name,
            displayName: name,
            group: "dev",
            kind: .web,
            detectedTools: Array(Set(sessions.compactMap {
                DetectedTool(rawValue: $0.tool)
            })),
            recent: sessions.map(\.modified).max(),
            branch: "main",
            lastCommit: nil,
            dirtyCount: 0,
            changes: .zero,
            ahead: 0,
            behind: 0,
            weekly: weekly,
            stacks: [],
            size: .empty,
            cleanup: .empty,
            run: nil,
            sessions: SessionSummary(
                detected: Array(Set(sessions.map(\.tool))),
                lastSessionAt: sessions.map(\.modified).max(),
                lastUserMessage: sessions.first?.lastUser,
                lastSessionID: sessions.first?.id,
                lastTool: sessions.first?.tool,
                sessionCount: sessions.count,
                byTool: [],
                recentSessions: sessions
            ),
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: false,
            color: nil,
            note: "",
            port: .noPreview
        )
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testLastSevenDaysAggregationSortingAndTopFiles() {
        let now = Date()
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: now)
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay)!
        let todayKey = dayKey(now)
        let boundaryKey = dayKey(startDay)
        let oldKey = dayKey(calendar.date(byAdding: .day, value: -1, to: startDay)!)

        let projectA = makeProject(
            path: "/tmp/weekly-a",
            name: "Alpha",
            sessions: [
                SessionRecord(
                    tool: "codex",
                    id: "a1",
                    cwd: "/tmp/weekly-a",
                    startedAt: now.addingTimeInterval(-3_600),
                    modified: now.addingTimeInterval(-1_800),
                    costUSD: 0.10,
                    touchedFiles: ["src/App.swift"]
                ),
                SessionRecord(
                    tool: "claude",
                    id: "a2",
                    cwd: "/tmp/weekly-a",
                    startedAt: now.addingTimeInterval(-7_200),
                    modified: now.addingTimeInterval(-5_400),
                    costUSD: 0.20,
                    touchedFiles: [
                        "src/App.swift",
                        "/tmp/weekly-a/src/App.swift",
                        "./src/App.swift",
                        "SRC/APP.SWIFT",
                        "src/Model.swift",
                    ]
                ),
                SessionRecord(
                    tool: "codex",
                    id: "a-old",
                    cwd: "/tmp/weekly-a",
                    startedAt: now.addingTimeInterval(-9 * 24 * 60 * 60),
                    modified: now.addingTimeInterval(-8 * 24 * 60 * 60),
                    costUSD: 9,
                    touchedFiles: ["src/Old.swift"]
                ),
            ],
            weekly: [todayKey: 1, boundaryKey: 2, oldKey: 5]
        )
        let projectB = makeProject(
            path: "/tmp/weekly-b",
            name: "Beta",
            sessions: [
                SessionRecord(
                    tool: "codex",
                    id: "b1",
                    cwd: "/tmp/weekly-b",
                    startedAt: now.addingTimeInterval(-2_000),
                    modified: now.addingTimeInterval(-1_000),
                    costUSD: 0.05,
                    touchedFiles: ["lib/B.swift"]
                ),
            ],
            weekly: [todayKey: 2]
        )

        let recap = WeeklyRecapService.build(projects: [projectB, projectA], now: now)

        XCTAssertEqual(recap.activeProjects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(recap.sessionCount, 3)
        XCTAssertEqual(recap.changedFileCount, 3)
        XCTAssertEqual(recap.savedVersionCount, 5)
        XCTAssertEqual(recap.cost.amount ?? -1, 0.35, accuracy: 0.0001)
        XCTAssertEqual(recap.activeProjects.first?.sessionCount, 2)
        XCTAssertEqual(recap.activeProjects.first?.changedFileCount, 2)
        XCTAssertEqual(recap.topFiles.first?.path, "src/App.swift")
        XCTAssertEqual(recap.topFiles.first?.sessionCount, 2)
        XCTAssertTrue(recap.markdown.contains("Alpha"))
        XCTAssertTrue(recap.markdown.contains("存下 5 个版本"))
    }

    func testEmptyRecapIsExplicitAndRedactsSecretsInMarkdown() {
        let empty = WeeklyRecapService.build(projects: [])
        XCTAssertFalse(empty.hasActivity)
        XCTAssertTrue(empty.markdown.contains("还没有新的 AI 对话"))

        let syntheticToken = "ghp_abcdefghijklmnopqrstuvwx"
        let caught = makeProject(
            path: "/tmp/weekly-secret",
            name: "Secret",
            sessions: [
                SessionRecord(
                    tool: "codex",
                    id: "secret-1",
                    cwd: "/tmp/weekly-secret",
                    startedAt: Date(),
                    modified: Date(),
                    touchedFiles: ["src/\(syntheticToken).swift"]
                ),
            ]
        )
        let recap = WeeklyRecapService.build(projects: [caught])
        XCTAssertFalse(recap.markdown.contains(syntheticToken))
        XCTAssertTrue(recap.markdown.contains("[已脱敏]"))
    }

    @MainActor
    func testPolishRequiresBothConsentsAndSendsOnlyTotalsToSelectedProvider() async throws {
        let suite = "fixture.recap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ledger = dir.appendingPathComponent("usage.json")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let path = "/fixture/private-folder"
        let token = "ghp_" + String(repeating: "a", count: 25)
        let session = SessionRecord(tool: "private-tool", id: "private-session", cwd: path, startedAt: nil, modified: Date(),
                                    lastUser: "private-chat", model: "private-model", touchedFiles: ["src/private-file"], lastError: token)
        let recap = WeeklyRecapService.build(projects: [makeProject(path: path, name: "private-name", sessions: [session])])
        let figures = WeeklyRecapFigures(recap)
        XCTAssertTrue(recap.markdown.contains("private-file"))
        let provider = RecapTestProvider(text: "workdir: /private/fixture\n{\"summary\":\"汇总 \(token)\"}")
        SummaryPreferences.setProviderKind(.localModel, in: defaults)
        func polish(_ consent: SummaryProviderKind?) async -> String? {
            await WeeklyRecapService.polish(figures, consentFor: consent, defaults: defaults, usageFile: ledger) { kind in
                XCTAssertEqual(kind, .localModel)
                return provider
            }
        }
        let disabled = await polish(.localModel)
        SummaryPreferences.setEnabled(true, in: defaults)
        let noGlobalConsent = await polish(.localModel)
        SummaryPreferences.setConsentAccepted(true, in: defaults)
        let noSheetConsent = await polish(nil)
        let changedProvider = await polish(.agentCLI)
        XCTAssertTrue([disabled, noGlobalConsent, noSheetConsent, changedProvider].allSatisfy { $0 == nil })
        let untouched = await provider.requests
        XCTAssertTrue(untouched.isEmpty)

        let text = await polish(.localModel)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.jsonMode)
        XCTAssertTrue(request.userPrompt.contains("未计价"))
        for forbidden in ["private-", "/fixture", "src/", token, "# FizzDeck"] {
            XCTAssertFalse((request.systemPrompt + request.userPrompt).contains(forbidden))
        }
        XCTAssertEqual(text, "汇总 [已脱敏]")
        XCTAssertTrue(recap.markdown(polishedSummary: text).contains("## AI 润色"))
        XCTAssertEqual(SelfUsageLedger.load(from: ledger).map(\.providerKind), [.localModel])

        await provider.fail()
        let fallback = await polish(.localModel)
        XCTAssertNil(fallback)
        XCTAssertEqual(recap.markdown(polishedSummary: fallback), recap.markdown)
        XCTAssertEqual(SelfUsageLedger.load(from: ledger).count, 1)
    }
}

private actor RecapTestProvider: SummaryProvider {
    var requests: [SummaryRequest] = []
    private var shouldFail = false
    let text: String
    init(text: String) { self.text = text }
    func fail() { shouldFail = true }
    func generate(_ request: SummaryRequest, config: SummaryProviderConfiguration) async throws -> SummaryResponse {
        requests.append(request)
        if shouldFail { throw SummaryProviderError.timedOut }
        return SummaryResponse(text: text, model: config.model, inputTokens: 10, outputTokens: 8, estimatedCostUSD: 0, providerLabel: "fixture")
    }
}
