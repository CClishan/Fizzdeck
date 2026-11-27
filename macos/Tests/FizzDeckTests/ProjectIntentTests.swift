import AppIntents
import XCTest
@testable import FizzDeck

final class ProjectIntentTests: XCTestCase {
    @MainActor func testHealthShortcutRunsInlineAndUnknownProjectCannotCopyOrOpen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"name":"shortcut","dependencies":{"vite":"*"}}"#.utf8).write(to: dir.appendingPathComponent("package.json"))
        let scanned = await RepositoryScanner.scanFast(paths: [dir.path], meta: [:], evidenceIndex: .empty)
        var project = try XCTUnwrap(scanned.first)
        project.starred = true
        let store = RepositoryStore(), previous = ShortcutProjectData.liveStore
        store.projects = [project]
        ShortcutProjectData.liveStore = store
        defer { ShortcutProjectData.liveStore = previous }
        let health = try await FocusedFizzDoctorIntent().perform()
        let text = try XCTUnwrap(health.value)
        XCTAssertTrue(text.contains(project.displayName))
        XCTAssertFalse(text.contains("体检正常"))
        XCTAssertEqual(store.destination, .dashboard)
        XCTAssertFalse(FileTools.exists(dir.appendingPathComponent(".git")))

        let missing = ShortcutProject(id: dir.appendingPathComponent("removed").path, name: "Removed")
        let copy = CopyFizzHandoffIntent(), open = OpenFizzProjectIntent()
        copy.project = missing; open.project = missing
        do { _ = try await copy.perform(); XCTFail("An unmanaged path must not write the clipboard") } catch { }
        do { _ = try await open.perform(); XCTFail("An unmanaged path must not navigate") } catch { }
        XCTAssertEqual(store.destination, .dashboard)
    }
}
