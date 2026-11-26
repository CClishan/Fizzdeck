import XCTest
@testable import FizzDeck

final class PerformanceBaselineTests: XCTestCase {
    func testSessionIndexColdWarmAndInvalidationOnFiftyProjects() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckPerf-\(UUID().uuidString)")
        let sessionsRoot = home.appendingPathComponent(".codex/sessions/2026/11/26", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        for index in 0..<50 {
            let path = sessionsRoot.appendingPathComponent("rollout-perf-\(index).jsonl")
            let content = """
            {"timestamp":"2026-11-26T10:00:00Z","type":"session_meta","payload":{"id":"perf-\(index)","cwd":"/tmp/perf-\(index)"}}
            {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"text":"项目 \(index) 的请求"}]}}}
            """
            try content.write(to: path, atomically: true, encoding: .utf8)
        }
        let cacheFile = home.appendingPathComponent("session-cache.json")

        let cold = elapsed {
            let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
            XCTAssertEqual(records.count, 50)
        }
        let warm = elapsed {
            let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
            XCTAssertEqual(records.count, 50)
        }

        let edited = sessionsRoot.appendingPathComponent("rollout-perf-0.jsonl")
        let existing = try String(contentsOf: edited, encoding: .utf8)
        try (existing + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"item\":{\"type\":\"UserMessage\",\"content\":[{\"text\":\"更新后的请求\"}]}}}\n")
            .write(to: edited, atomically: true, encoding: .utf8)
        let invalidated = elapsed {
            let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
            XCTAssertEqual(
                records.first(where: { $0.id == "perf-0" })?.lastUser,
                "更新后的请求"
            )
        }

        let summary = SessionIndex.summary(
            for: URL(fileURLWithPath: "/tmp/perf-0"),
            in: SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        )
        XCTAssertEqual(summary.sessionCount, 1)

        print("[perf] session-index 50 projects cold=\(ms(cold))ms warm=\(ms(warm))ms invalidated=\(ms(invalidated))ms")
    }

    func testVisibleProjectSortingForHundredPlusItems() {
        var projects: [RepoProject] = []
        for index in 0..<150 {
            projects.append(makeProject(
                path: "/tmp/perf-project-\(index)",
                name: "perf-\(index)",
                recent: Date(timeIntervalSince1970: TimeInterval(1_000 + index % 30)),
                size: Int64(index * 1024 * 1024),
                tool: index % 3 == 0 ? "codex" : "claude"
            ))
        }

        let start = Date()
        for _ in 0..<20 {
            _ = projects.sorted { ($0.recent ?? .distantPast) > ($1.recent ?? .distantPast) }
            _ = projects.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            _ = projects.sorted { $0.size.totalBytes > $1.size.totalBytes }
        }
        let elapsed = Date().timeIntervalSince(start) * 1_000
        print("[perf] 150 projects x 20 sorts = \(String(format: "%.1f", elapsed))ms")
    }

    func testFiftyProjectScanColdWarmCacheBaseline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckScanPerf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var paths: [String] = []
        for index in 0..<50 {
            let project = root.appendingPathComponent("project-\(index)", isDirectory: true)
            let source = project.appendingPathComponent("src", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try #"{"name":"perf-\#(index)","version":"1.0.0"}"#
                .write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
            try "export const value = \(index);\n"
                .write(to: source.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
            paths.append(project.path)
        }

        let coldStart = Date()
        let projects = await RepositoryScanner.scanFast(
            paths: paths,
            meta: [:],
            evidenceIndex: .empty
        )
        let cold = Date().timeIntervalSince(coldStart)
        XCTAssertEqual(projects.count, 50)

        let cacheFile = root.appendingPathComponent("scan-cache.json")
        ScanCacheStore.save(projects, cacheFile: cacheFile)
        let warmStart = Date()
        let cached = ScanCacheStore.load(for: paths, meta: [:], cacheFile: cacheFile)
        let warm = Date().timeIntervalSince(warmStart)
        XCTAssertEqual(cached.count, 50)

        print(
            "[perf] scan 50 projects cold=\(ms(cold))ms warmCache=\(ms(warm))ms"
        )
    }

    func testDiscoveryCancellationResponseBaseline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckCancelPerf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<2_000 {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("folder-\(index)/nested", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let scope = DiscoveryScope(
            id: "perf",
            title: "perf",
            path: root.path,
            maxDepth: 8,
            category: .custom,
            selectedByDefault: false,
            detail: nil
        )
        let task = Task {
            await ProjectDiscovery.discoverStreaming(
                scopes: [scope],
                limit: 300,
                evidenceIndex: .empty,
                onProgress: { _ in }
            )
        }
        try? await Task.sleep(for: .milliseconds(10))
        let cancelledAt = Date()
        task.cancel()
        let report = await task.value
        let response = Date().timeIntervalSince(cancelledAt)

        XCTAssertTrue(report.cancelled)
        XCTAssertLessThan(response, 2)
        print("[perf] discovery cancellation response=\(ms(response))ms")
    }

    private func elapsed(_ block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }

    private func ms(_ interval: TimeInterval) -> String {
        String(format: "%.1f", interval * 1_000)
    }

    private func makeProject(
        path: String,
        name: String,
        recent: Date,
        size: Int64,
        tool: String
    ) -> RepoProject {
        RepoProject(
            path: path,
            name: name,
            displayName: name,
            group: "测试",
            kind: .web,
            detectedTools: [DetectedTool(rawValue: tool) ?? .codex],
            recent: recent,
            branch: "main",
            lastCommit: nil,
            dirtyCount: 0,
            changes: .zero,
            ahead: 0,
            behind: 0,
            weekly: [:],
            stacks: [],
            size: SizeInfo(totalBytes: size, breakdown: [SizeRow]()),
            cleanup: .empty,
            run: nil,
            sessions: .empty,
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: false,
            color: nil,
            note: "",
            port: .stopped
        )
    }
}
