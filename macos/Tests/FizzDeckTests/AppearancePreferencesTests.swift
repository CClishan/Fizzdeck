import AppKit
import SwiftUI
import XCTest
@testable import FizzDeck

final class AppearancePreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "fizzdeck.tests.appearance.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testStorageKeyIsStable() {
        XCTAssertEqual(AppearancePreferences.key, "fizzdeck.appearance")
    }

    func testMissingValueDefaultsToSystem() {
        XCTAssertNil(defaults.object(forKey: AppearancePreferences.key))
        XCTAssertEqual(AppearancePreferences.appearance(in: defaults), .system)
    }

    func testRoundTripsEveryAppearance() {
        for appearance in AppAppearance.allCases {
            AppearancePreferences.set(appearance, in: defaults)

            XCTAssertEqual(defaults.string(forKey: AppearancePreferences.key), appearance.rawValue)
            XCTAssertEqual(AppearancePreferences.appearance(in: defaults), appearance)
        }
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("sepia", forKey: AppearancePreferences.key)

        XCTAssertEqual(AppearancePreferences.appearance(in: defaults), .system)
    }

    func testAppearanceMapsToColorScheme() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testAppearanceMapsToNSAppearance() {
        XCTAssertNil(AppAppearance.system.nsAppearance)
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }
}
