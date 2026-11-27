import XCTest
@testable import FizzDeck

final class AppDestinationTests: XCTestCase {
    func testDestinationHelpersReportActiveCase() {
        XCTAssertTrue(AppDestination.dashboard.isDashboard)
        XCTAssertFalse(AppDestination.dashboard.isLibrary)
        XCTAssertNil(AppDestination.dashboard.projectPath)

        let query = LibraryQuery(group: "网页", dirtyOnly: true)
        let library = AppDestination.library(query)
        XCTAssertTrue(library.isLibrary)
        XCTAssertEqual(library.libraryQuery, query)
        XCTAssertNil(library.projectPath)

        XCTAssertTrue(AppDestination.conversations.isConversations)
        XCTAssertFalse(AppDestination.conversations.isDashboard)
        XCTAssertTrue(AppDestination.cleanup.isCleanup)
        XCTAssertEqual(AppDestination.project("/tmp/app").projectPath, "/tmp/app")
    }

    func testLibraryQueryTracksAndClearsFilters() {
        var query = LibraryQuery()
        XCTAssertFalse(query.hasActiveFilters)

        query.searchText = "  "
        XCTAssertFalse(query.hasActiveFilters)

        query.commitDayKey = "2026-11-20"
        XCTAssertTrue(query.hasActiveFilters)

        query.starredOnly = true
        query.group = "网页"
        query.clearFilters()
        XCTAssertFalse(query.hasActiveFilters)
        XCTAssertEqual(query, LibraryQuery())
    }

    @MainActor
    func testRepositoryStoreNavigationAndSelectedPathBridge() {
        let store = RepositoryStore()
        XCTAssertEqual(store.destination, .dashboard)
        XCTAssertEqual(store.selectedPath, RepositoryStore.homeSelection)

        store.openLibrary(LibraryQuery(group: "工具"))
        XCTAssertEqual(store.destination, .library(LibraryQuery(group: "工具")))
        XCTAssertNil(store.selectedPath)

        store.openConversations()
        XCTAssertEqual(store.destination, .conversations)
        XCTAssertNil(store.selectedPath)

        store.openCleanup()
        XCTAssertEqual(store.destination, .cleanup)
        XCTAssertNil(store.selectedPath)

        store.selectedPath = "/tmp/demo"
        XCTAssertEqual(store.destination, .project("/tmp/demo"))
        XCTAssertEqual(store.selectedPath, "/tmp/demo")

        store.selectedPath = RepositoryStore.selection(for: .dirty)
        XCTAssertEqual(store.destination, .library(LibraryQuery(dirtyOnly: true)))

        store.openDashboard()
        XCTAssertEqual(store.destination, .dashboard)
    }
}
