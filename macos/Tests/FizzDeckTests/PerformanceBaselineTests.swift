import AppKit
import QuartzCore
import ScreenCaptureKit
import SwiftUI
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

    func testDashboardAndLibraryPerformanceOnTwoHundredProjects() {
        let now = Date(timeIntervalSince1970: 1_795_680_000)
        var projects: [RepoProject] = []
        var commitMap: [String: RepoCommitActivity] = [:]

        for index in 0..<200 {
            let path = "/tmp/perf-200/project-\(index)"
            let recent = now.addingTimeInterval(-Double((index % 45) * 86_400))
            let sessions = (0..<3).map { sessionIdx in
                SessionRecord(
                    tool: sessionIdx == 0 ? "codex" : (sessionIdx == 1 ? "claude" : "grok"),
                    id: "s-\(index)-\(sessionIdx)",
                    cwd: path,
                    startedAt: recent.addingTimeInterval(-1_800),
                    modified: recent,
                    lastUser: "Task \(index)-\(sessionIdx)",
                    usage: TokenUsage(totalTokens: 2_500 + index * 10),
                    costUSD: 0.12 + Double(index % 5) * 0.05,
                    costIsEstimate: true
                )
            }

            var project = makeProject(
                path: path,
                name: "project-\(index)",
                recent: recent,
                size: Int64((index + 1) * 2_000_000),
                tool: "codex"
            )
            project.dirtyCount = index % 4
            project.ahead = index % 3
            project.starred = index % 10 == 0
            project.stacks = [StackGroup(key: "framework", label: "框架", items: [index % 2 == 0 ? "Next.js" : "SwiftUI"])]
            project.sessions = SessionSummary(
                detected: ["codex", "claude", "grok"],
                lastSessionAt: recent,
                lastUserMessage: "Task \(index)-0",
                lastSessionID: "s-\(index)-0",
                lastTool: "codex",
                sessionCount: 3,
                byTool: [
                    ToolSession(tool: "codex", sessionCount: 1, lastSessionAt: recent, lastSessionID: "s-\(index)-0", lastUserMessage: "Task \(index)-0"),
                ],
                recentSessions: sessions
            )
            projects.append(project)

            let baseTS = Int(now.timeIntervalSince1970)
            let timestamps = (0..<50).map { offset in
                baseTS - ((offset * 7 + index) % 360) * 86_400
            }
            commitMap[path] = RepoCommitActivity(
                path: path,
                head: "head-\(index)",
                authorEmails: ["dev@example.com"],
                windowDays: 371,
                timestamps: timestamps,
                updatedAt: now
            )
        }
        let snapshot = CommitActivitySnapshot(byProject: commitMap)

        let heatmapTime = elapsed {
            let summary = DashboardMetrics.buildHeatmap(snapshot: snapshot, projects: projects, range: .months12, now: now)
            XCTAssertEqual(summary.columns.count, 52)
        }

        let workbenchTime = elapsed {
            _ = DashboardMetrics.kpiSummary(projects: projects, commitActivity: snapshot, now: now)
            _ = DashboardMetrics.weeklyToolShares(projects: projects, now: now)
            _ = DashboardMetrics.costBreakdown(projects: projects, mode: .byTool, now: now)
            _ = DashboardMetrics.weeklyTimeline(projects: projects, commitActivity: snapshot, now: now)
            _ = DashboardMetrics.continueWorkItems(projects: projects, limit: 4)
            _ = DashboardMetrics.healthAlerts(projects: projects, freeDiskBytes: 15_000_000_000, now: now)
        }

        let libraryTime = elapsed {
            for _ in 0..<10 {
                let filtered = HomeDashboardModel.libraryProjects(
                    from: projects,
                    query: LibraryQuery(searchText: "project"),
                    sort: .recent,
                    commitActivity: snapshot
                )
                let split = DashboardMetrics.partitionByActivity(filtered, now: now)
                let rows = LibraryTableRow.makeRows(from: split.active)
                _ = rows.sorted(using: [LibraryRowComparator(column: .aiCost, order: .reverse)])
            }
        }

        XCTAssertLessThan(heatmapTime, 1.0)
        XCTAssertLessThan(workbenchTime, 1.0)
        XCTAssertLessThan(libraryTime, 1.0)
        print("[perf] heatmap 200 repos 10k commits (12m)=\(ms(heatmapTime))ms")
        print("[perf] workbench metrics 200 projects=\(ms(workbenchTime))ms")
        print("[perf] library 200 projects x 10 table+filter=\(ms(libraryTime))ms")
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

// Opt in with FIZZDECK_SCALE_TEST=1 on a Mac with an unlocked desktop. The
// search numbers and WindowServer frames refer to this temporary fixture only.
extension PerformanceBaselineTests {
    @MainActor func testThousandProjectWindowAndTenThousandConversations() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FIZZDECK_SCALE_TEST"] == "1", "interactive scale benchmark")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(), before = peakMemoryMiB()
        var projects: [RepoProject] = []
        for i in 0..<1_000 {
            var p = makeProject(path: dir.appendingPathComponent("project-\(i)").path, name: "Project \(i)", recent: now.addingTimeInterval(Double(-i)), size: Int64(i * 1_024), tool: "codex")
            p.sessions.recentSessions = (0..<10).map { j in
                SessionRecord(tool: "codex", id: "sample-\(i)-\(j)", cwd: p.path, startedAt: now, modified: now, lastUser: nil, firstUser: "更新颜色索引 samplecode\(i)entry\(j)end")
            }
            p.sessions.sessionCount = p.sessions.recentSessions.count
            projects.append(p)
        }
        let index = SessionSearchIndex(databaseURL: dir.appendingPathComponent("fts.sqlite"))
        let begin = CACurrentMediaTime()
        await index.rebuild(from: projects)
        let indexed = CACurrentMediaTime() - begin
        var times: [Double] = []
        for i in 0..<40 {
            let start = CACurrentMediaTime(), n = (i * 241) % 1000
            let hits = await index.search(query: "samplecode\(n)entry4end")
            times.append((CACurrentMediaTime() - start) * 1_000)
            XCTAssertEqual(hits.map(\.sessionID), ["sample-\(n)-4"])
        }
        times.sort()
        let shortStart = CACurrentMediaTime(), shortHits = await index.search(query: "颜色")
        XCTAssertEqual(shortHits.count, 40)
        print(String(format: "[scale] 1000 projects / 10000 sessions: index %.2fs, FTS query p50 %.2fms p95 %.2fms, short LIKE %.2fms, peak RSS %.1f MiB (baseline %.1f)", indexed, times[19], times[37], (CACurrentMediaTime() - shortStart) * 1000, peakMemoryMiB(), before))

        let host = NSHostingView(rootView: LibraryTableView(projects: projects, selectedPaths: .constant([])).environment(RepositoryStore()))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1100, height: 580), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "FizzDeck · scale fixture"
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        func table(in v: NSView) -> NSTableView? {
            if let v = v as? NSTableView { return v }
            return v.subviews.lazy.compactMap { table(in: $0) }.first
        }
        let table = try XCTUnwrap(table(in: host))
        XCTAssertEqual(table.numberOfRows, 1_000)
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        let driver = TableFrameDriver(scroll: scroll)
        let link = host.displayLink(target: driver, selector: #selector(TableFrameDriver.advance))
        link.add(to: .main, forMode: .common)
        defer { link.invalidate() }
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "WindowServer frame measurement needs screen recording permission")
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let target = try XCTUnwrap(content.windows.first { Int($0.windowID) == window.windowNumber })
        let config = SCStreamConfiguration()
        config.width = 550; config.height = 290; config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
        let frames = TablePresentedFrames(), queue = DispatchQueue(label: "FizzDeck.scale.frames")
        try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        try await Task.sleep(for: .milliseconds(400))
        let start = CACurrentMediaTime(), initial = queue.sync { frames.count }
        try await Task.sleep(for: .seconds(3))
        let seconds = CACurrentMediaTime() - start, drawn = queue.sync { frames.count } - initial
        try await stream.stopCapture()
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        XCTAssertGreaterThan(drawn, 0)
        print(String(format: "[scale] native table 1000 rows, WindowServer complete frames %d / %.2fs = %.1f FPS, display max %d Hz, process peak RSS %.1f MiB", drawn, seconds, Double(drawn) / seconds, window.screen?.maximumFramesPerSecond ?? 0, peakMemoryMiB()))
    }

    private func peakMemoryMiB() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
    }
}

@MainActor private final class TableFrameDriver: NSObject {
    let scroll: NSScrollView
    init(scroll: NSScrollView) { self.scroll = scroll }
    @objc func advance() {
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.minY + 12))
        scroll.reflectScrolledClipView(clip)
    }
}

private final class TablePresentedFrames: NSObject, SCStreamOutput {
    // Accessed only on the sample queue, including reads from the benchmark.
    var count = 0
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let entries = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = entries.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
        count += 1
    }
}
