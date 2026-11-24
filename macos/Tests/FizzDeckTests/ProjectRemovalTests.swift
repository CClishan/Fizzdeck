import XCTest
@testable import FizzDeck

final class ProjectRemovalTests: XCTestCase {
    private var root: URL!
    private var projectURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckRemoval-\(UUID().uuidString)", isDirectory: true)
        projectURL = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try "payload".write(
            to: projectURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRejectsUnmanagedProject() {
        let result = remove(managedRoots: [root.appendingPathComponent("other").path])

        XCTAssertFalse(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    func testRejectsWrongConfirmation() {
        let result = remove(confirmation: "wrong")

        XCTAssertFalse(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    func testRejectsRunningTest() {
        let result = remove(testRunning: true)

        XCTAssertFalse(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    func testRejectsRunningDevServer() {
        let result = remove(devServerRunning: true)

        XCTAssertFalse(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    func testRejectsShallowPath() {
        let result = ProjectRemovalService.remove(
            path: "/tmp",
            mode: .trash,
            confirmation: "tmp",
            managedRoots: ["/tmp"],
            testRunning: false,
            devServerRunning: false
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/tmp"))
    }

    func testPermanentDeletionCopiesBeforeRemoving() throws {
        let backupRoot = root.appendingPathComponent("backup", isDirectory: true)
        let result = remove(mode: .permanent, backupRoot: backupRoot)

        XCTAssertTrue(result.success, result.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.path))

        let backups = try FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: nil
        )
        let backup = try XCTUnwrap(backups.first)
        let payload = backup.appendingPathComponent("README.md")
        XCTAssertEqual(try String(contentsOf: payload, encoding: .utf8), "payload")
    }

    private func remove(
        mode: ProjectRemovalMode = .permanent,
        confirmation: String = "project",
        managedRoots: [String]? = nil,
        testRunning: Bool = false,
        devServerRunning: Bool = false,
        backupRoot: URL? = nil
    ) -> ProjectRemovalResult {
        ProjectRemovalService.remove(
            path: projectURL.path,
            mode: mode,
            confirmation: confirmation,
            managedRoots: managedRoots ?? [projectURL.path],
            testRunning: testRunning,
            devServerRunning: devServerRunning,
            backupRoot: backupRoot ?? root.appendingPathComponent("backup", isDirectory: true)
        )
    }
}
