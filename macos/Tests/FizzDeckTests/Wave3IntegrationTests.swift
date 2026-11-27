import Foundation
import XCTest
@testable import FizzDeck

@MainActor
final class Wave3IntegrationTests: XCTestCase {
    private func makeTempDirectory(name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-w3-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeProject(path: String) -> RepoProject {
        let now = Date()
        return RepoProject(
            path: path,
            name: "demo",
            displayName: "demo",
            group: "dev",
            kind: .web,
            detectedTools: [.claude],
            recent: now,
            branch: "main",
            lastCommit: nil,
            dirtyCount: 2,
            changes: ChangeStats(tracked: 2, untracked: 0, total: 2),
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
                lastUserMessage: "完善登录按钮",
                lastSessionID: "s1",
                lastTool: "claude",
                sessionCount: 1,
                byTool: [],
                recentSessions: []
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

    func testSummaryEngineHandoffAndCommitMessageRespectOffSwitchAndSilentFallback() async throws {
        let dir = try makeTempDirectory(name: "handoff-commit")
        defer { try? FileManager.default.removeItem(at: dir) }

        let suite = "dev.fizzdeck.tests.w3.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        final class MockProvider: SummaryProvider, @unchecked Sendable {
            var calls = 0
            var shouldFail = false
            var replyText = "“把登录弹窗按钮圆角调大并补充提示”\nsk-live-secret1234567890abcd"

            func generate(_ request: SummaryRequest, config: SummaryProviderConfiguration) async throws -> SummaryResponse {
                calls += 1
                if shouldFail {
                    throw SummaryProviderError.timedOut
                }
                return SummaryResponse(
                    text: replyText,
                    model: "gpt-4o-mini",
                    inputTokens: 50,
                    outputTokens: 15,
                    estimatedCostUSD: 0.0005,
                    providerLabel: "Mock"
                )
            }
        }

        let provider = MockProvider()
        let engine = SummaryEngine(
            cacheDirectory: dir.appendingPathComponent("summaries", isDirectory: true),
            usageFile: dir.appendingPathComponent("usage.json"),
            defaults: defaults,
            workdir: dir.appendingPathComponent("workdir", isDirectory: true),
            cliProvider: provider,
            httpProvider: provider
        )
        let project = makeProject(path: dir.path)

        let offHandoff = await engine.generateHandoffMarkdown(for: project)
        let offCommit = await engine.generateCommitMessage(for: project, changedFiles: ["App.swift"])
        XCTAssertNil(offHandoff)
        XCTAssertNil(offCommit)
        XCTAssertEqual(provider.calls, 0)

        SummaryPreferences.setEnabled(true, in: defaults)
        SummaryPreferences.setConsentAccepted(true, in: defaults)

        let onHandoff = await engine.generateHandoffMarkdown(for: project)
        let onCommit = await engine.generateCommitMessage(for: project, changedFiles: ["App.swift"])
        XCTAssertNotNil(onHandoff)
        XCTAssertFalse(onHandoff?.contains("sk-live-secret1234567890abcd") ?? true)
        XCTAssertEqual(onCommit, "把登录弹窗按钮圆角调大并补充提示")
        XCTAssertEqual(provider.calls, 2)

        provider.shouldFail = true
        let failedHandoff = await engine.generateHandoffMarkdown(for: project)
        let failedCommit = await engine.generateCommitMessage(for: project, changedFiles: ["App.swift"])
        XCTAssertNil(failedHandoff)
        XCTAssertNil(failedCommit)
        XCTAssertNotNil(engine.lastError)
    }

    func testMarkDiffRestoreSelectionDefaultsExcludeCreatedFiles() {
        let mark = SessionMark(projectPath: "/tmp/demo", kind: .gitSnapshot)
        let summary = MarkDiffSummary(
            mark: mark,
            available: true,
            modifiedOrDeleted: [
                MarkFileChange(path: "Sources/App.swift", status: .modified),
                MarkFileChange(path: "Sources/Old.swift", status: .deleted),
            ],
            createdAfterMark: [
                MarkFileChange(path: "Sources/NewFeature.swift", status: .createdAfterMark),
            ]
        )

        XCTAssertEqual(
            MarkDiffRestoreSelection.defaultRestorePaths(for: summary),
            Set(["Sources/App.swift", "Sources/Old.swift"])
        )
        XCTAssertTrue(MarkDiffRestoreSelection.defaultTrashPaths(for: summary).isEmpty)
    }

    func testAddEnvFilesToGitignoreAppendsMissingEntriesIdempotently() throws {
        let dir = try makeTempDirectory(name: "gitignore")
        defer { try? FileManager.default.removeItem(at: dir) }

        let gitignore = dir.appendingPathComponent(".gitignore")
        try ".env\nnode_modules".write(to: gitignore, atomically: true, encoding: .utf8)

        XCTAssertTrue(LightweightProjectCheckService.addEnvFilesToGitignore(in: dir))
        let content = try String(contentsOf: gitignore, encoding: .utf8)
        XCTAssertEqual(
            content.split(whereSeparator: \.isNewline).map(String.init),
            [".env", "node_modules", ".env.local"]
        )

        XCTAssertTrue(LightweightProjectCheckService.addEnvFilesToGitignore(in: dir))
        let contentAfterSecondCall = try String(contentsOf: gitignore, encoding: .utf8)
        XCTAssertEqual(content, contentAfterSecondCall)
    }
}
