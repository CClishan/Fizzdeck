import SwiftUI
import XCTest
@testable import FizzDeck

final class FizzDesignSystemTests: XCTestCase {
    func testRadiusTokensMatchLayoutScale() {
        XCTAssertEqual(FizzRadius.frame, 16)
        XCTAssertEqual(FizzRadius.panel, 16)
        XCTAssertEqual(FizzRadius.card, 14)
        XCTAssertEqual(FizzRadius.inset, 10)
        XCTAssertEqual(FizzRadius.control, 8)
        XCTAssertEqual(FizzRadius.micro, 4)
    }

    func testSpacingTokensMatchLayoutScale() {
        XCTAssertEqual(FizzSpacing.page, 24)
        XCTAssertEqual(FizzSpacing.section, 20)
        XCTAssertEqual(FizzSpacing.panel, 16)
        XCTAssertEqual(FizzSpacing.grid, 12)
        XCTAssertEqual(FizzSpacing.row, 8)
    }

    func testElevationTightensInDarkMode() {
        let levels: [FizzElevation] = [.subtle, .raised, .floating]

        for level in levels {
            let light = level.metrics(for: .light)
            let dark = level.metrics(for: .dark)

            XCTAssertGreaterThan(light.radius, 0)
            XCTAssertGreaterThan(light.opacity, 0)
            XCTAssertLessThan(dark.radius, light.radius)
            XCTAssertLessThanOrEqual(dark.y, light.y)
        }

        XCTAssertEqual(
            FizzElevation.subtle.metrics(for: .light),
            FizzElevation.Metrics(opacity: 0.04, radius: 6, y: 2)
        )
        XCTAssertGreaterThan(
            FizzElevation.floating.metrics(for: .light).radius,
            FizzElevation.raised.metrics(for: .light).radius
        )
    }

    func testPortStatusBadgeReservesOrangeForAttention() {
        XCTAssertEqual(PortState.running.badgeTone, .running)
        XCTAssertEqual(PortState.stopped.badgeTone, .neutral)
        XCTAssertEqual(PortState.noPreview.badgeTone, .muted)

        XCTAssertEqual(PortState.running.badgeLabel, "端口运行中")
        XCTAssertEqual(PortState.stopped.badgeLabel, "端口未启动")
        XCTAssertEqual(PortState.noPreview.badgeLabel, "无预览端口")
    }

    func testLogoSVGLoadsForEachAppearance() {
        XCTAssertEqual(FizzAsset.logoResourceName(for: .light), "FizzDeck_logo_light")
        XCTAssertEqual(FizzAsset.logoResourceName(for: .dark), "FizzDeck_logo_dark")
        XCTAssertNotNil(FizzAsset.logo(for: .light))
        XCTAssertNotNil(FizzAsset.logo(for: .dark))
    }

    @MainActor func testLightBackgroundDisablesGlow() {
        XCTAssertNil(FizzBackground.glowOpacity(for: .light))
        XCTAssertEqual(FizzBackground.glowOpacity(for: .dark), 0.06)
    }

    @MainActor func testIconScaleAndBundledSidebarAssets() {
        XCTAssertEqual(FizzIconScale.toolbar, 13)
        XCTAssertEqual(FizzIconScale.nav, 12)
        XCTAssertEqual(FizzIconScale.micro, 8)
        XCTAssertTrue(FizzIcon.hasBundledAsset(for: "sidebar.left"))
        XCTAssertTrue(FizzIcon.hasBundledAsset(for: "gearshape"))
        XCTAssertTrue(FizzIcon.hasBundledAsset(for: "archivebox"))
        XCTAssertTrue(FizzIcon.hasBundledAsset(for: "checkmark.circle"))
    }

    @MainActor func testPortStatusBadgeShowsPortWhenRunning() {
        XCTAssertEqual(PortStatusBadge.displayLabel(for: .running, port: 5173), ":5173")
        XCTAssertEqual(PortStatusBadge.displayLabel(for: .running, port: nil), "端口运行中")
        XCTAssertEqual(PortStatusBadge.displayLabel(for: .stopped, port: 5173), "端口未启动")
    }
}
