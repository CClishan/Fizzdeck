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

    func testRangesCompareDisjointNaturalDaysAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let today = calendar.startOfDay(for: now)
        let path = "/tmp/recap-ranges"
        func session(_ offset: Int, secondsAtStart: Double = 0, kind: SessionRecordKind = .conversation) -> SessionRecord {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!.addingTimeInterval(secondsAtStart)
            return SessionRecord(tool: "codex", id: "\(offset):\(secondsAtStart)", cwd: path, startedAt: nil, modified: date, kind: kind)
        }
        let project = makeProject(path: path, name: "Ranges", sessions: [
            session(0), session(-6), session(-6, secondsAtStart: -1), session(-13),
            session(-13, secondsAtStart: -1), session(-29), session(-89), session(-99),
            session(0, secondsAtStart: 80_000), session(-1, kind: .workspaceSummary),
        ])

        let seven = WeeklyRecapService.build(projects: [project], now: now, calendar: calendar)
        XCTAssertEqual(seven.sessionCount, 2)
        XCTAssertEqual(seven.analysis.previous?.sessions, 2)
        XCTAssertNil(seven.analysis.trend(.sessions).change)
        XCTAssertEqual(DashboardMetrics.weeklyConversationTotals(projects: [project], now: now, calendar: calendar), seven.analysis.totals)
        XCTAssertEqual(seven.analysis.bucketStarts.count, 7)
        XCTAssertTrue(seven.analysis.bucketStarts.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        XCTAssertEqual(WeeklyRecapService.build(projects: [project], range: .month, now: now, calendar: calendar).sessionCount, 6)
        XCTAssertEqual(WeeklyRecapService.build(projects: [project], range: .quarter, now: now, calendar: calendar).sessionCount, 7)
        let all = WeeklyRecapService.build(projects: [project], range: .all, now: now, calendar: calendar)
        XCTAssertEqual(all.sessionCount, 8)
        XCTAssertNil(all.analysis.previous)
        XCTAssertNil(all.analysis.trend(.sessions).change)
        XCTAssertLessThanOrEqual(all.analysis.bucketStarts.count, 45)
    }

    func testRecapKeepsMissingMeasurementsAndCountsOnlyEvidenceInAverages() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let alpha = "/tmp/recap-alpha"
        let beta = "/tmp/recap-beta"
        let logged = SessionRecord(tool: "codex", id: "a", cwd: alpha, startedAt: day(-4), modified: day(-1),
                                   usage: TokenUsage(inputTokens: 150, outputTokens: 50, totalTokens: 200), costUSD: 0.12,
                                   endedWithError: true, turnCount: 2, agentTimeSeconds: 80, testResult: .failed)
        let missing = SessionRecord(tool: "codex", id: "b", cwd: alpha, startedAt: day(-6), modified: today,
                                    costUSD: 0, durationMinutes: 1_000)
        let other = SessionRecord(tool: "opencode", id: "c", cwd: beta, startedAt: nil, modified: day(-1),
                                  agentTimeSeconds: 40, testResult: .notRun)
        let recap = WeeklyRecapService.build(projects: [
            makeProject(path: alpha, name: "Alpha", sessions: [logged, missing]),
            makeProject(path: beta, name: "Beta", sessions: [other]),
        ], now: now, calendar: calendar)
        let analysis = recap.analysis

        XCTAssertEqual(analysis.projects.map(\.id), [alpha, beta])
        XCTAssertEqual(analysis.projects[0].buckets[5]?.value(.agentTime), 80)
        XCTAssertNil(analysis.projects[0].buckets[6]?.value(.agentTime))
        XCTAssertEqual(analysis.samples(.agentTime), [nil, nil, nil, nil, nil, 120, nil])
        XCTAssertEqual(analysis.samples(.cost), [nil, nil, nil, nil, nil, 0.12, nil])
        XCTAssertEqual(analysis.totals.value(.tokens), 200)
        XCTAssertEqual(analysis.totals.cost.unpriced, 2)
        XCTAssertEqual(analysis.totals.averageSeconds, 60)
        XCTAssertEqual(analysis.totals.averageCost, 0.12)
        XCTAssertNil(analysis.trend(.cost).change)
        XCTAssertEqual(analysis.tools.map { $0.totals.errorRate }, [0.5, 0])
        XCTAssertEqual(analysis.activeDays, 2)
        XCTAssertEqual(analysis.streak, 2)
        XCTAssertEqual(analysis.busiestDay?.date, day(-1))
        XCTAssertEqual(analysis.longestSession?.record.id, "a")
        XCTAssertEqual(analysis.sessions.first?.record.id, "b")
    }

    func testCurrentStreakCanEndYesterdayButStopsAtAFullInactiveDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let path = "/tmp/recap-streak"
        let sessions = [-1, -2, -4].map { offset in
            SessionRecord(tool: "codex", id: "\(offset)", cwd: path, startedAt: nil,
                          modified: calendar.date(byAdding: .day, value: offset, to: today)!)
        }
        func build(_ offset: Int) -> WeeklyRecapAnalysis {
            WeeklyRecapService.build(projects: [makeProject(path: path, name: "Streak", sessions: sessions)],
                                     now: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar).analysis
        }
        XCTAssertEqual(build(0).activeDays, 3)
        XCTAssertEqual(build(0).streak, 2)
        XCTAssertEqual(build(1).streak, 0)
        XCTAssertEqual(build(1).heatmap.last?.sessions, 0)
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
