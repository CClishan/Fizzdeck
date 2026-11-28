import Observation
import XCTest
@testable import FizzDeck

/// Legacy copy assertions describe the Chinese interface; the runner's own language is unrelated.
class ChineseInterfaceTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        FizzL10n.use(.chinese)
    }

    override class func tearDown() {
        FizzL10n.use(.stored())
        super.tearDown()
    }
}

final class FizzLanguageTests: XCTestCase {
    func testRecapTrendTickUsesTheSelectedInterfaceLanguage() throws {
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12)))
        FizzL10n.$languageOverride.withValue(.english) {
            XCTAssertEqual(Format.monthDay(date), "Nov 23")
        }
        FizzL10n.$languageOverride.withValue(.chinese) {
            XCTAssertEqual(Format.monthDay(date), "11月23日")
        }
    }

    func testPreferenceSurvivesReopeningDefaultsAndUnknownValueFollowsSystem() throws {
        let suite = "fizzdeck.tests.language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FizzLanguage.stored(in: defaults), .system)
        for choice in FizzLanguage.allCases {
            defaults.set(choice.rawValue, forKey: FizzLanguage.key)
            XCTAssertEqual(FizzLanguage.stored(in: try XCTUnwrap(UserDefaults(suiteName: suite))), choice)
        }
        defaults.set("unsupported", forKey: FizzLanguage.key)
        XCTAssertEqual(FizzLanguage.stored(in: defaults), .system)
        XCTAssertEqual(FizzLanguage.system.resolved(preferredLanguages: ["de-DE", "zh-Hans-CN", "en-US"]), .chinese)
        XCTAssertEqual(FizzLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-CN"]), .english)
        XCTAssertEqual(FizzLanguage.system.resolved(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(FizzLanguage.chinese.resolved(preferredLanguages: ["en-US"]), .chinese)
    }

    func testChangingLanguageInvalidatesDisplayedCopyWithoutChangingData() {
        let before = FizzL10n.language
        defer { FizzL10n.use(before) }
        FizzL10n.use(.chinese)
        let invalidation = expectation(description: "Observed label changes")
        withObservationTracking {
            XCTAssertEqual(FizzCopy.conversationsNavTitle, "对话")
        } onChange: { invalidation.fulfill() }
        FizzL10n.use(.english)
        wait(for: [invalidation], timeout: 1)
        XCTAssertEqual(FizzCopy.conversationsNavTitle, "Conversations")
        XCTAssertEqual(ProjectGrouping.detected(for: "/unused", kind: .web), "网页")
        XCTAssertEqual(ProjectGrouping.title(for: "网页"), "Web")
        XCTAssertEqual(ProjectGrouping.title(for: "工作室 Atlas"), "工作室 Atlas")
        XCTAssertEqual(Format.tokens(250_000), "250K")
        FizzL10n.use(.chinese)
        XCTAssertEqual(Format.tokens(250_000), "25 万")
    }

    @MainActor func testVisibleToastKeepsItsActionAndUserTextWhenSwitchingLanguage() throws {
        let center = ToastCenter()
        var presses = 0
        let userText = "我的 Atlas"
        FizzL10n.$languageOverride.withValue(.chinese) {
            center.show(FizzL10n.text("已复制", "Copied"), subtitle: userText,
                        action: ToastAction(title: FizzL10n.text("打开", "Open")) { presses += 1 })
        }
        let toast = try XCTUnwrap(center.current)
        FizzL10n.$languageOverride.withValue(.english) {
            XCTAssertEqual(toast.title, "Copied")
            XCTAssertEqual(toast.subtitle, userText)
            XCTAssertEqual(toast.action?.title, "Open")
            toast.action?.handler()
        }
        XCTAssertEqual(presses, 1)
    }

    func testEnglishPlainAndGitTermsWorkIndependentlyOfLanguagePreference() {
        FizzL10n.$languageOverride.withValue(.english) {
            XCTAssertEqual(CopyModePreferences.defaultValue, .plain)
            XCTAssertEqual(CopyMode.plain.title, "Plain English")
            XCTAssertEqual(CopyMode.pro.title, "Git Terms")
            XCTAssertEqual(FizzCopy.commitAction(.plain).text, "Save a version")
            XCTAssertEqual(FizzCopy.uncommittedChanges(mode: .plain).text, "Unsaved changes")
            XCTAssertEqual(FizzCopy.uncommittedChanges(mode: .pro).text, "Uncommitted")
            XCTAssertEqual(FizzCopy.commitAction(.pro).text, "Commit")
            XCTAssertEqual(FizzCopy.pullAction(.pro).text, "Pull")
            XCTAssertEqual(FizzCopy.stashAction(.pro).text, "Stash")
            XCTAssertNil(FizzCopy.commitAction(.pro).proHint)
            XCTAssertEqual(FizzCopy.tabTitle(.version, mode: .plain), "Version")
            XCTAssertEqual(FizzCopy.tabTitle(.version, mode: .pro), "Git")
        }
    }
}
