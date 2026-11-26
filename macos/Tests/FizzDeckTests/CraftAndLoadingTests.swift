import SwiftUI
import XCTest
@testable import FizzDeck

final class CraftAndLoadingTests: XCTestCase {
    func testHoverBubbleClampsInsideCardAtBothEdges() {
        let containerWidth: CGFloat = 320
        let bubbleWidth: CGFloat = 220
        let dotSize: CGFloat = 8.5
        let spacing: CGFloat = 4
        let columnCount = 26

        let first = CommitHeatmapLayout.hoverBubbleOriginX(
            column: 0,
            columnCount: columnCount,
            matrixWidth: 288,
            dotSize: dotSize,
            spacing: spacing,
            bubbleWidth: bubbleWidth,
            containerWidth: containerWidth
        )
        let last = CommitHeatmapLayout.hoverBubbleOriginX(
            column: columnCount - 1,
            columnCount: columnCount,
            matrixWidth: 288,
            dotSize: dotSize,
            spacing: spacing,
            bubbleWidth: bubbleWidth,
            containerWidth: containerWidth
        )

        XCTAssertEqual(first, 8, accuracy: 0.001)
        XCTAssertEqual(last, containerWidth - 8 - bubbleWidth, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(first, 8)
        XCTAssertLessThanOrEqual(last + bubbleWidth, containerWidth - 8)
    }

    func testHoverBubbleTracksColumnsMonotonically() {
        let origins = stride(from: 0, through: 25, by: 5).map { column in
            CommitHeatmapLayout.hoverBubbleOriginX(
                column: column,
                columnCount: 26,
                matrixWidth: 520,
                dotSize: 8.5,
                spacing: 4,
                bubbleWidth: 190,
                containerWidth: 552
            )
        }

        XCTAssertEqual(origins, origins.sorted())
        XCTAssertGreaterThan(origins.last ?? 0, origins.first ?? 0)
    }

    func testScrollHairlineThresholdAndShimmerMetrics() {
        XCTAssertFalse(FizzScrollMetrics.isPastTop(0))
        XCTAssertFalse(FizzScrollMetrics.isPastTop(8))
        XCTAssertTrue(FizzScrollMetrics.isPastTop(8.01))

        XCTAssertEqual(
            FizzShimmerMetrics.bandOffset(phase: 0, width: 100),
            -62,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FizzShimmerMetrics.bandOffset(phase: 1, width: 100),
            100,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            FizzShimmerMetrics.highlightOpacity(for: .light),
            FizzShimmerMetrics.highlightOpacity(for: .dark)
        )
    }

    func testLibraryCoverPreferenceDefaultsOnAndPersists() throws {
        XCTAssertTrue(LibraryCoverPreference.resolved(nil))
        XCTAssertFalse(LibraryCoverPreference.resolved(false))

        let suiteName = "FizzDeckTests.cover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: LibraryCoverPreference.key)
        let stored = defaults.object(forKey: LibraryCoverPreference.key) as? Bool

        XCTAssertFalse(LibraryCoverPreference.resolved(stored))
    }
}
