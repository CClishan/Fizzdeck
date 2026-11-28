import Foundation
import XCTest
@testable import FizzDeck

final class SessionMarkExpiryPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func mark(
        _ id: String = "checkpoint",
        daysAgo: Int,
        pinned: Bool = false,
        kind: SessionMarkKind = .gitSnapshot,
        path: String = "/tmp/expiry",
        sha: String? = String(repeating: "a", count: 40),
        files: [String] = [],
        label: String? = "手动记录点"
    ) -> SessionMark {
        SessionMark(
            id: id, projectPath: path,
            createdAt: now.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60),
            kind: kind,
            snapshotSHA: kind == .gitSnapshot ? sha : nil,
            changedFilesAtMark: files, pinned: pinned, label: label
        )
    }

    func testWarnsOnlyDuringFinalFourDays() {
        let atFourDays = mark(daysAgo: 10)
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: atFourDays, now: now.addingTimeInterval(-1)), .stable)
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 9), now: now), .stable)
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(for: mark(daysAgo: 10), now: now),
            .expiring(daysRemaining: 4)
        )
        for days in 1...4 {
            XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 14 - days), now: now), .expiring(daysRemaining: days))
        }
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 14), now: now.addingTimeInterval(-1)), .expiring(daysRemaining: 1))
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(for: mark(daysAgo: 13), now: now),
            .expiring(daysRemaining: 1)
        )
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 14), now: now), .expired)
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 15), now: now), .expired)
    }

    func testPinnedPureAndUnavailableMarksNeverWarn() {
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 10, sha: nil), now: now), .unavailable)
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(for: mark(daysAgo: 10, pinned: true), now: now),
            .stable
        )
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(
                for: mark(daysAgo: 10, kind: .pureMark),
                now: now
            ),
            .stable
        )
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(
                for: mark(daysAgo: 10),
                now: now,
                available: false
            ),
            .unavailable
        )
    }

    func testWorkbenchCollectsNamedAndDirtySnapshotsOnlyInFocusedProjects() {
        let start = "对话开始前的样子"
        let candidates = SessionMarkExpiryPolicy.attentionCandidates(in: [
            mark("manual", daysAgo: 10),
            mark("backup", daysAgo: 12, label: "还原前自动备份"),
            mark("dirty-start", daysAgo: 13, files: ["draft.swift"], label: start),
            mark("clean-start", daysAgo: 12, label: start),
            mark("unnamed", daysAgo: 12, label: nil),
            mark("unfocused", daysAgo: 12, path: "/tmp/idle"),
            mark("pure", daysAgo: 12, kind: .pureMark),
            mark("no-sha", daysAgo: 12, sha: ""),
            mark("pinned", daysAgo: 12, pinned: true),
            mark("too-early", daysAgo: 9), mark("expired", daysAgo: 14),
        ], focusedPaths: ["/tmp/expiry"], now: now)

        XCTAssertEqual(candidates.map(\.mark.id), ["dirty-start", "backup", "manual"])
        XCTAssertEqual(candidates.map(\.daysRemaining), [1, 2, 4])
        XCTAssertTrue(SessionMarkAvailabilityCheck.Results().confirmed(candidates).isEmpty)
    }

    @MainActor
    func testDismissedBatchSurvivesReloadButNewAndNewlyExpiringMarksStillRemind() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("marks.json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        for (id, age) in [("a", 12), ("b", 11), ("later", 9)] {
            try MarkStore.upsertChecked(mark(id, daysAgo: age, path: root.path), in: file)
        }
        let store = RepositoryStore(preferences: defaults, marksFile: file)
        func reminders(_ marks: [SessionMark], at time: Date) -> [String] {
            SessionMarkExpiryPolicy.attentionCandidates(in: marks, focusedPaths: [root.path], now: time).map(\.mark.id)
        }
        XCTAssertEqual(reminders(store.marks, at: now), ["a", "b"])
        try store.dismissExpiryReminders(for: ["a", "b"])
        XCTAssertTrue(reminders(store.marks, at: now).isEmpty)
        store.reloadMarks()
        let dismissed = try XCTUnwrap(store.marks.first { $0.id == "a" })
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: dismissed, now: now), .expiring(daysRemaining: 2))
        try MarkStore.upsertChecked(mark("new", daysAgo: 11, path: root.path), in: file)
        store.reloadMarks()
        XCTAssertEqual(reminders(store.marks, at: now), ["new"])
        let reopened = RepositoryStore(preferences: defaults, marksFile: file)
        XCTAssertEqual(reminders(reopened.marks, at: now.addingTimeInterval(86_400)), ["new", "later"])
    }

    @MainActor
    func testRealSnapshotPinPersistsRefAndRemovesReminderImmediately() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let initialized = await Shell.run("git", ["init", "--template="], cwd: repo)
        XCTAssertEqual(initialized?.status, 0)
        try Data("unsaved work".utf8).write(to: repo.appendingPathComponent("draft.txt"))
        let snapshot = await SessionMarkService.createMark(for: repo, tmpDir: root.appendingPathComponent("index"))
        let sha = try XCTUnwrap(snapshot.snapshotSHA)
        let good = mark("good", daysAgo: 12, path: repo.path, sha: sha, files: snapshot.changedFilesAtMark, label: nil)
        let missing = mark("missing", daysAgo: 13, path: repo.path)
        let file = root.appendingPathComponent("marks.json")
        try MarkStore.upsertChecked(good, in: file)
        try MarkStore.upsertChecked(missing, in: file)
        let store = RepositoryStore(preferences: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), marksFile: file)
        func candidates() -> [ExpiringSessionMark] {
            SessionMarkExpiryPolicy.attentionCandidates(in: store.marks, focusedPaths: [repo.path], now: now)
        }
        let check = SessionMarkAvailabilityCheck(marks: candidates().map(\.mark), scannedAt: now)
        let verified = await check.run()
        XCTAssertEqual(verified.confirmed(candidates()).map(\.mark.id), [good.id])
        let failed = await store.setPinned(true, for: missing)
        XCTAssertFalse(failed)
        let saved = await store.setPinned(true, for: good)
        let repeated = await store.setPinned(true, for: good)
        XCTAssertTrue(saved)
        XCTAssertTrue(repeated)
        XCTAssertTrue(verified.confirmed(candidates()).isEmpty)
        let ref = await Shell.output("git", ["rev-parse", "--verify", "refs/fizzdeck/marks/\(good.id)"], cwd: repo)
        XCTAssertEqual(ref, sha)
        store.reloadMarks()
        let reloaded = try XCTUnwrap(store.marks.first { $0.id == good.id })
        XCTAssertTrue(reloaded.pinned)
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: reloaded, now: now), .stable)
        XCTAssertTrue(verified.confirmed(candidates()).isEmpty)

        // A metadata failure must not report success or leave a previously protected snapshot unpinned.
        let unreadable = Data("invalid JSON".utf8)
        try unreadable.write(to: file, options: .atomic)
        let unpinned = await store.setPinned(false, for: reloaded)
        XCTAssertFalse(unpinned)
        let protectedRef = await Shell.output("git", ["rev-parse", "--verify", "refs/fizzdeck/marks/\(good.id)"], cwd: repo)
        XCTAssertEqual(protectedRef, sha)
        XCTAssertEqual(try Data(contentsOf: file), unreadable)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FizzDeck-expiry-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
