import Foundation
import XCTest
@testable import FizzDeck

final class MenuBarAttentionSummaryTests: XCTestCase {
    private func makeProject(path: String) -> RepoProject {
        RepoProject(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            group: "dev",
            kind: .web,
            recent: Date(),
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
            sessions: .empty,
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: true,
            color: nil,
            note: "",
            port: .noPreview
        )
    }

    func testDoctorCriticalCountsOncePerProjectAndDeduplicatesExistingTypes() {
        let project = makeProject(path: "/tmp/menubar-focused")
        let idle = makeProject(path: "/tmp/menubar-idle")
        let testFailed = ProjectAttentionItem(
            project: project,
            kind: .testFailed,
            title: "检查失败",
            detail: "npm test"
        )
        let existingDoctor = ProjectAttentionItem(
            project: project,
            kind: .doctorCritical,
            title: "缺依赖",
            detail: "node_modules"
        )
        let reports: [String: DoctorProjectReport] = [
            project.path: DoctorProjectReport(
                projectPath: project.path,
                checkedAt: Date(),
                issues: [
                    DoctorIssue(
                        projectPath: project.path,
                        kind: .missingDependencies,
                        severity: .critical,
                        title: "缺依赖",
                        detail: "node_modules",
                        fixAction: nil
                    ),
                    DoctorIssue(
                        projectPath: project.path,
                        kind: .unignoredEnvFile,
                        severity: .critical,
                        title: "环境文件没忽略",
                        detail: ".env",
                        fixAction: nil
                    ),
                ]
            ),
            idle.path: DoctorProjectReport(
                projectPath: idle.path,
                checkedAt: Date(),
                issues: [
                    DoctorIssue(
                        projectPath: idle.path,
                        kind: .trackedSecrets,
                        severity: .critical,
                        title: "疑似密钥",
                        detail: "config.js",
                        fixAction: nil
                    ),
                ]
            ),
        ]

        let count = MenuBarAttentionSummary.count(
            items: [testFailed, existingDoctor],
            doctorReports: reports,
            focusedPaths: [project.path]
        )
        XCTAssertEqual(count, 2)
    }

    func testLatestSnapshotCandidateSkipsExpiredNonSnapshotsAndMissingObjects() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let path = "/tmp/menubar-marks"
        let pureMark = SessionMark(
            projectPath: path,
            createdAt: now.addingTimeInterval(-60),
            kind: .pureMark
        )
        let missingSnapshot = SessionMark(
            projectPath: path,
            createdAt: now.addingTimeInterval(-120),
            kind: .gitSnapshot,
            snapshotSHA: ""
        )
        let expired = SessionMark(
            projectPath: path,
            createdAt: now.addingTimeInterval(-15 * 24 * 60 * 60),
            kind: .gitSnapshot,
            snapshotSHA: "expired"
        )
        let valid = SessionMark(
            projectPath: path,
            createdAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
            kind: .gitSnapshot,
            snapshotSHA: "valid"
        )

        XCTAssertEqual(
            MenuBarSnapshotMarkPolicy.latestCandidate(
                in: [pureMark, missingSnapshot, expired, valid],
                now: now
            )?.id,
            valid.id
        )

        let pinnedOld = SessionMark(
            projectPath: path,
            createdAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
            kind: .gitSnapshot,
            snapshotSHA: "pinned",
            pinned: true
        )
        XCTAssertEqual(
            MenuBarSnapshotMarkPolicy.latestCandidate(
                in: [expired, pinnedOld],
                now: now
            )?.id,
            pinnedOld.id
        )
    }
}
