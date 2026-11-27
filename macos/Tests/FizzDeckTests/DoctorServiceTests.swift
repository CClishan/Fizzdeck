import Foundation
import XCTest
@testable import FizzDeck

final class DoctorServiceTests: XCTestCase {
    private func makeTempDirectory(name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-doctor-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeProject(path: String, run: RunConfig? = nil) -> RepoProject {
        let now = Date()
        return RepoProject(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
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
            stacks: [StackGroup(key: "frontend", label: "前端", items: ["React", "Vite"])],
            size: .empty,
            cleanup: .empty,
            run: run,
            sessions: SessionSummary(
                detected: ["claude"],
                lastSessionAt: now,
                lastUserMessage: "修一下登录",
                lastSessionID: "s1",
                lastTool: "claude",
                sessionCount: 1,
                byTool: [],
                recentSessions: [
                    SessionRecord(
                        tool: "claude",
                        id: "s1",
                        cwd: path,
                        startedAt: now,
                        modified: now,
                        touchedFiles: ["\(path)/src/Login.tsx", "\(path)/package.json"]
                    ),
                ]
            ),
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: true,
            color: nil,
            note: "",
            port: .noPreview
        )
    }

    func testDetectInstallCommandInfersPackageManagerFromLockfile() throws {
        let root = try makeTempDirectory(name: "pm")
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(DoctorService.detectInstallCommand(in: root), "npm install")

        let pnpmDir = root.appendingPathComponent("pnpm", isDirectory: true)
        try FileManager.default.createDirectory(at: pnpmDir, withIntermediateDirectories: true)
        try "".write(to: pnpmDir.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)
        XCTAssertEqual(DoctorService.detectInstallCommand(in: pnpmDir), "pnpm install")

        let yarnDir = root.appendingPathComponent("yarn", isDirectory: true)
        try FileManager.default.createDirectory(at: yarnDir, withIntermediateDirectories: true)
        try "".write(to: yarnDir.appendingPathComponent("yarn.lock"), atomically: true, encoding: .utf8)
        XCTAssertEqual(DoctorService.detectInstallCommand(in: yarnDir), "yarn install")

        let bunDir = root.appendingPathComponent("bun", isDirectory: true)
        try FileManager.default.createDirectory(at: bunDir, withIntermediateDirectories: true)
        try "".write(to: bunDir.appendingPathComponent("bun.lockb"), atomically: true, encoding: .utf8)
        XCTAssertEqual(DoctorService.detectInstallCommand(in: bunDir), "bun install")
    }

    func testInspectProjectRespectsFocusedVsIdleScopes() async throws {
        let dir = try makeTempDirectory(name: "scopes")
        defer { try? FileManager.default.removeItem(at: dir) }

        try #"{"name":"demo"}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "API_KEY=".write(to: dir.appendingPathComponent(".env.example"), atomically: true, encoding: .utf8)

        let project = makeProject(path: dir.path)

        let focused = await DoctorService.inspectProject(project, scope: .focused, copyMode: .plain)
        let focusedKinds = Set(focused.issues.map(\.kind))
        XCTAssertTrue(focusedKinds.contains(.missingDependencies))
        XCTAssertTrue(focusedKinds.contains(.missingEnvFile))
        XCTAssertTrue(focusedKinds.contains(.notAGitRepo))
        XCTAssertEqual(focused.severity, .critical)

        let idle = await DoctorService.inspectProject(project, scope: .idle, copyMode: .plain)
        let idleKinds = Set(idle.issues.map(\.kind))
        XCTAssertFalse(idleKinds.contains(.missingDependencies))
        XCTAssertFalse(idleKinds.contains(.missingEnvFile))
        XCTAssertTrue(idleKinds.contains(.notAGitRepo))
    }

    func testInspectProjectDetectsTrackedSecretsOnlyInCommittedFiles() async throws {
        let dir = try makeTempDirectory(name: "secrets")
        defer { try? FileManager.default.removeItem(at: dir) }

        let initOut = await Shell.run("git", ["init"], cwd: dir, timeout: 10)
        XCTAssertEqual(initOut?.succeeded, true)

        try "const key = 'sk-live-secret1234567890abcd';\n".write(
            to: dir.appendingPathComponent("config.js"),
            atomically: true,
            encoding: .utf8
        )
        _ = await Shell.run("git", ["add", "config.js"], cwd: dir, timeout: 10)
        let commitOut = await Shell.run(
            "git",
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "init"],
            cwd: dir,
            timeout: 10
        )
        XCTAssertEqual(commitOut?.succeeded, true)

        try ".env\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "OPENAI_API_KEY=sk-live-ignored1234567890abcd\n".write(
            to: dir.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let project = makeProject(path: dir.path)
        let report = await DoctorService.inspectProject(project, scope: .idle, copyMode: .plain)
        let secretIssue = report.issues.first { $0.kind == .trackedSecrets }
        XCTAssertNotNil(secretIssue)
        XCTAssertEqual(secretIssue?.severity, .critical)
        if case .inspectTrackedSecrets(let files) = secretIssue?.fixAction {
            XCTAssertEqual(files, ["config.js"])
        } else {
            XCTFail("Expected inspectTrackedSecrets fix action")
        }
        XCTAssertFalse(report.issues.contains { $0.kind == .unignoredEnvFile })
    }

    func testSafeRepairHelpersCreateEnvInitGitAndTrashCleanupWithinRoot() async throws {
        let dir = try makeTempDirectory(name: "repairs")
        let outsideDir = try makeTempDirectory(name: "outside")
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        // createEnvFromExample
        try "PORT=3000\n".write(to: dir.appendingPathComponent(".env.example"), atomically: true, encoding: .utf8)
        let createdEnv = DoctorService.createEnvFromExample(in: dir)
        XCTAssertNotNil(createdEnv)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(".env"), encoding: .utf8), "PORT=3000\n")

        // Never overwrite existing .env
        try "PORT=4000\n".write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertNil(DoctorService.createEnvFromExample(in: dir))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(".env"), encoding: .utf8), "PORT=4000\n")

        // initGitRepository
        let gitInit = await DoctorService.initGitRepository(in: dir, marksFile: outsideDir.appendingPathComponent("marks.json"), tmpDir: outsideDir)
        XCTAssertTrue(gitInit.succeeded)
        XCTAssertTrue(GitService.hasGit(dir))
        let gitignoreContent = try String(contentsOf: dir.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignoreContent.contains(".env"))

        // trashCleanupItems refuses outside traversal, trashes inside directory
        let cacheDir = dir.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try "junk".write(to: cacheDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let outsideItem = CleanupItem(
            label: "outside",
            path: outsideDir.path,
            bytes: 10,
            reason: "test",
            regen: "",
            kind: "deps"
        )
        let blocked = DoctorService.trashCleanupItems([outsideItem], in: dir)
        XCTAssertNotNil(blocked.error)
        XCTAssertTrue(FileTools.exists(outsideDir))

        let insideItem = CleanupItem(
            label: "node_modules",
            path: cacheDir.path,
            bytes: 4_096,
            reason: "依赖目录",
            regen: "npm install",
            kind: "deps"
        )
        let trashed = DoctorService.trashCleanupItems([insideItem], in: dir) { url in
            try FileManager.default.removeItem(at: url)
        }
        XCTAssertNil(trashed.error)
        XCTAssertEqual(trashed.trashedCount, 1)
        XCTAssertEqual(trashed.freedBytes, 4_096)
        XCTAssertFalse(FileTools.exists(cacheDir))
    }

    func testLogErrorHelperExtractsExplainsAndRedactsPrompt() {
        let benignLog = "Build succeeded with 0 errors and 0 warnings."
        XCTAssertNil(LogErrorHelper.extractError(from: benignLog))

        let errorLog = """
        > vite build
        Loaded env sk-live-secret1234567890abcd
        Error: Cannot find module 'react-dnd'
            at Function.Module._resolveFilename (node:internal/modules/cjs/loader:1144:15)
        """
        let match = LogErrorHelper.extractError(from: errorLog)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.category, "missing_module")
        XCTAssertFalse(match?.contextBlock.contains("sk-live-secret1234567890abcd") ?? true)

        let project = makeProject(path: "/tmp/demo-app")
        let prompt = LogErrorHelper.buildHelpPrompt(project: project, match: match!)
        XCTAssertTrue(prompt.contains("demo-app"))
        XCTAssertTrue(prompt.contains("React / Vite"))
        XCTAssertTrue(prompt.contains("Login.tsx"))
        XCTAssertTrue(prompt.contains("Cannot find module"))
        XCTAssertFalse(prompt.contains("sk-live-secret1234567890abcd"))
    }

    func testRuntimeVersionMismatchIsFocusedOnlyAndCarriesCopyCommand() async throws {
        let dir = try makeTempDirectory(name: "runtime")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ">=999\n".write(
            to: dir.appendingPathComponent(".nvmrc"),
            atomically: true,
            encoding: .utf8
        )
        try "999\n".write(
            to: dir.appendingPathComponent(".python-version"),
            atomically: true,
            encoding: .utf8
        )
        let project = makeProject(path: dir.path)
        let runtimeEnvironment = RuntimeVersionEnvironment(node: "22.0.0", python: "3.12.0")

        let focused = await DoctorService.inspectProject(
            project,
            scope: .focused,
            copyMode: .plain,
            runtimeEnvironment: runtimeEnvironment
        )
        let issues = focused.issues.filter { $0.kind == .runtimeVersionMismatch }
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(Set(issues.map(\.id)).count, 2)
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning })
        XCTAssertTrue(issues.contains {
            $0.title.contains("Node")
                && $0.fixAction == .copyShellCommand(command: "nvm use")
        })
        XCTAssertTrue(issues.contains {
            $0.title.contains("Python")
                && $0.fixAction == .copyShellCommand(
                    command: "pyenv install 999 && pyenv local 999"
                )
        })

        let idle = await DoctorService.inspectProject(
            project,
            scope: .idle,
            copyMode: .plain,
            runtimeEnvironment: runtimeEnvironment
        )
        XCTAssertFalse(idle.issues.contains { $0.kind == .runtimeVersionMismatch })
    }

    func testL0ReadsOnlyStaticInputsAndCriticalIssuesCannotBeExempted() async throws {
        let root = try makeTempDirectory(name: "l0")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: false)
        for (name, text) in [("package.json", "{}"), (".env.example", ""), (".env.staging", ""),
                             (".gitignore", ".env.*\n!.env.staging\n"), (".nvmrc", ">=999")] {
            try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let project = makeProject(path: root.path)
        let raw = await DoctorService.inspectL0(project)
        XCTAssertEqual(Set(raw.issues.map(\.kind)), [.missingDependencies, .missingEnvFile, .unignoredEnvFile])
        let filtered = await DoctorService.inspectL0(project, exemptions: [.missingEnvFile, .missingDependencies, .unignoredEnvFile])
        XCTAssertEqual(Set(filtered.issues.map(\.kind)), [.missingDependencies, .unignoredEnvFile])
        XCTAssertEqual(filtered.severity, .critical)
        XCTAssertFalse(FileTools.exists(root.appendingPathComponent(".env")))
    }

    func testStateRoundTripKeepsExemptionsLocalAndPreservesUnrelatedMetadata() throws {
        let dir = try makeTempDirectory(name: "settings")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json"), a = dir.appendingPathComponent("a").path, b = dir.appendingPathComponent("b").path
        try FileTools.writeJSON([a: ["note": "keep", "futureField": 42, "doctorExemptions": ["trackedSecrets", "runtimeVersionMismatch"]],
                                 b: ["customArtwork": "art", "futureField": [1, 2]]], to: file)
        XCTAssertEqual(MetaStore.load(from: file)[a]?.doctorExemptions, [.runtimeVersionMismatch])
        try MetaStore.saveDoctorExemptions([.cloudBehind, .portConflict], for: b, to: file)
        var metadata = MetaStore.load(from: file)
        XCTAssertEqual(metadata[b]?.doctorExemptions, [.cloudBehind]); XCTAssertEqual(metadata[b]?.customArtwork, "art")
        metadata[a]?.starred = true
        try MetaStore.save(metadata, to: file)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: [String: Any]])
        XCTAssertEqual(json[a]?["futureField"] as? Int, 42); XCTAssertEqual(json[b]?["futureField"] as? [Int], [1, 2])
        XCTAssertEqual(json[a]?["doctorExemptions"] as? [String], ["runtimeVersionMismatch"])
        try MetaStore.saveDoctorExemptions([], for: a, to: file)
        XCTAssertEqual(MetaStore.load(from: file)[a]?.doctorExemptions, []); XCTAssertEqual(MetaStore.load(from: file)[b]?.doctorExemptions, [.cloudBehind])
        try Data("invalid".utf8).write(to: file)
        XCTAssertThrowsError(try MetaStore.saveDoctorExemptions([], for: b, to: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "invalid")
    }

    @MainActor func testFullDoctorPageRotatesFocusedProjectsWithinItsBudget() async throws {
        let root = try makeTempDirectory(name: "full-batches")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RepositoryStore()
        store.projects = try (0..<10).map { i in
            let dir = root.appendingPathComponent("project-\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            return makeProject(path: dir.path)
        }
        await store.refreshDoctorForFocused(force: false)
        XCTAssertEqual(store.doctorReports.count, 8)
        await store.refreshDoctorForFocused(force: false)
        XCTAssertEqual(store.doctorReports.count, 8, "Reopening the page within five minutes must remain cheap")
        await store.refreshDoctorForFocused(force: true)
        XCTAssertEqual(Set(store.doctorReports.keys), Set(store.projects.map(\.path)))
    }

    func testAttentionQueueSurfacesFocusedDoctorCriticalIssuesOnly() {
        let focusedProject = makeProject(path: "/tmp/focused-app")
        var idleProject = makeProject(path: "/tmp/idle-app")
        idleProject.starred = false

        let reports: [String: DoctorProjectReport] = [
            focusedProject.path: DoctorProjectReport(
                projectPath: focusedProject.path,
                checkedAt: Date(),
                issues: [
                    DoctorIssue(
                        projectPath: focusedProject.path,
                        kind: .missingDependencies,
                        severity: .critical,
                        title: "项目需要的零件还没装",
                        detail: "缺少 node_modules",
                        fixAction: .installDependencies(command: "npm install")
                    ),
                ]
            ),
            idleProject.path: DoctorProjectReport(
                projectPath: idleProject.path,
                checkedAt: Date(),
                issues: [
                    DoctorIssue(
                        projectPath: idleProject.path,
                        kind: .unignoredEnvFile,
                        severity: .critical,
                        title: ".env 可能泄露",
                        detail: "建议加入忽略",
                        fixAction: .addEnvToGitignore
                    ),
                ]
            ),
        ]

        let items = ProjectAttentionQueue.items(
            projects: [focusedProject, idleProject],
            testRuns: [:],
            focusedPaths: [focusedProject.path],
            copyMode: .plain,
            doctorReports: reports
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .doctorCritical)
        XCTAssertEqual(items.first?.project.path, focusedProject.path)
        XCTAssertEqual(items.first?.title, "项目需要的零件还没装")
    }
}
