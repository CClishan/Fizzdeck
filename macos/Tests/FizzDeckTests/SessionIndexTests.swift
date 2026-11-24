import XCTest
@testable import FizzDeck

final class SessionIndexTests: XCTestCase {
    func testSummarySortsAndGroupsSessions() {
        let target = URL(fileURLWithPath: "/tmp/fizzdeck-session")
        let start = Date(timeIntervalSince1970: 1_000)
        let index = [
            record(
                tool: "codex",
                id: "codex-old",
                cwd: target.path,
                modified: start,
                lastUser: "old request"
            ),
            record(
                tool: "claude",
                id: "claude-new",
                cwd: target.path,
                modified: start.addingTimeInterval(30),
                lastUser: "claude request"
            ),
            record(
                tool: "codex",
                id: "codex-new",
                cwd: target.path,
                modified: start.addingTimeInterval(20),
                lastUser: "new request"
            ),
            record(
                tool: "codex",
                id: "other-project",
                cwd: "/tmp/elsewhere",
                modified: start.addingTimeInterval(60),
                lastUser: "other request"
            ),
        ]

        let summary = SessionIndex.summary(for: target, in: index)

        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertEqual(
            summary.recentSessions.map(\.stableID),
            ["claude:claude-new", "codex:codex-new", "codex:codex-old"]
        )
        XCTAssertEqual(summary.detected, ["claude", "codex"])
        XCTAssertEqual(summary.byTool.map(\.tool), ["claude", "codex"])

        let codex = summary.byTool.first { $0.tool == "codex" }
        XCTAssertEqual(codex?.sessionCount, 2)
        XCTAssertEqual(codex?.lastSessionID, "codex-new")
        XCTAssertEqual(codex?.lastUserMessage, "new request")

        XCTAssertEqual(summary.lastTool, "claude")
        XCTAssertEqual(summary.lastSessionID, "claude-new")
        XCTAssertEqual(summary.lastUserMessage, "claude request")
    }

    func testSummaryNormalizesWorkingDirectory() {
        let target = URL(fileURLWithPath: "/tmp/fizzdeck-session")
        let index = [
            record(
                tool: "codex",
                id: "normalized",
                cwd: "/tmp/fizzdeck-session/./nested/..",
                modified: Date(timeIntervalSince1970: 1_000)
            ),
            record(
                tool: "claude",
                id: "missing-cwd",
                cwd: nil,
                modified: Date(timeIntervalSince1970: 1_100)
            ),
            record(
                tool: "claude",
                id: "different",
                cwd: "/tmp/fizzdeck-session-other",
                modified: Date(timeIntervalSince1970: 1_200)
            ),
        ]

        let summary = SessionIndex.summary(for: target, in: index)

        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.recentSessions.map(\.stableID), ["codex:normalized"])
    }

    func testResumeCommands() {
        let date = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            record(tool: "codex", id: "abc", cwd: nil, modified: date).resumeCommand,
            "codex resume abc"
        )
        XCTAssertEqual(
            record(tool: "claude", id: "def", cwd: nil, modified: date).resumeCommand,
            "claude --resume def"
        )
        XCTAssertNil(
            record(tool: "other", id: "ghi", cwd: nil, modified: date).resumeCommand
        )
    }

    func testScanLinesFromEndHandlesChunkBoundaries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "one\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var visited: [String] = []
        let found = FileTools.scanLinesFromEnd(in: url, chunkBytes: 5, maxBytes: 100) { line in
            visited.append(line)
            return line == "two"
        }

        XCTAssertTrue(found)
        XCTAssertEqual(visited, ["three", "two"])
    }

    private func record(
        tool: String,
        id: String,
        cwd: String?,
        modified: Date,
        lastUser: String? = nil
    ) -> SessionRecord {
        SessionRecord(
            tool: tool,
            id: id,
            cwd: cwd,
            startedAt: nil,
            modified: modified,
            lastUser: lastUser
        )
    }
}
