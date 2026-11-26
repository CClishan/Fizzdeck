import XCTest
@testable import FizzDeck

final class CommandPaletteLayoutTests: XCTestCase {
    func testAllGroupsFitAtNaturalHeight() {
        let sizes = [1, 2, 3]
        let expected = CommandPaletteLayout.contentPadding
            + CommandPaletteLayout.sectionHeight * 3
            + CommandPaletteLayout.rowHeight * 6

        XCTAssertEqual(CommandPaletteLayout.resultsHeight(groupSizes: sizes), expected)
    }

    func testPartialGroupEndsAfterVisibleRows() {
        let height = CommandPaletteLayout.resultsHeight(groupSizes: [2, 8, 10])
        let fixed = CommandPaletteLayout.contentPadding + CommandPaletteLayout.sectionHeight * 2

        XCTAssertLessThanOrEqual(height, CommandPaletteLayout.maxHeight)
        XCTAssertGreaterThanOrEqual((height - fixed) / CommandPaletteLayout.rowHeight, 2)
        XCTAssertEqual((height - fixed).truncatingRemainder(dividingBy: CommandPaletteLayout.rowHeight), 0)
    }

    func testOrphanHeaderIsDroppedWhenNoRowsFit() {
        let height = CommandPaletteLayout.resultsHeight(groupSizes: [9, 1])
        let fullFirstGroup = CommandPaletteLayout.contentPadding
            + CommandPaletteLayout.sectionHeight
            + CommandPaletteLayout.rowHeight * 9

        XCTAssertGreaterThan(fullFirstGroup, CommandPaletteLayout.maxHeight)
        XCTAssertEqual(height, CommandPaletteLayout.contentPadding + CommandPaletteLayout.sectionHeight + CommandPaletteLayout.rowHeight * 8)
    }
}
