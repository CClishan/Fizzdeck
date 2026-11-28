import CoreText
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
        XCTAssertEqual(FizzSpacing.card, 12)
        XCTAssertEqual(FizzSpacing.grid, 12)
        XCTAssertEqual(FizzSpacing.row, 8)
    }

    func testIconSizesMatchTheFourSemanticTiers() {
        XCTAssertEqual(FizzIconSize.allCases, [.xs, .sm, .md, .lg])
        XCTAssertEqual(FizzIconSize.allCases.map(\.rawValue), [10, 12, 14, 22])
    }

    @MainActor func testTypographyUsesTheStandardSizesAndWeights() {
        let tokens: [(Font, CGFloat, String)] = [
            (FizzTypography.pageTitle, 22, "SemiBold"), (FizzTypography.sectionTitle, 14, "SemiBold"),
            (FizzTypography.cardTitle, 13, "SemiBold"), (FizzTypography.body, 12.5, "Regular"),
            (FizzTypography.caption, 11, "Regular"), (FizzTypography.micro, 10, "Medium"),
            (FizzTypography.mono, 11.5, "Regular"), (FizzTypography.monoSmall, 10.5, "Regular"),
        ]
        for (token, size, weight) in tokens {
            let font = token.resolve(in: EnvironmentValues().fontResolutionContext).ctFont
            XCTAssertEqual(CTFontGetSize(font), size)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "ObelMono-\(weight)")
        }
    }

    @MainActor func testSwiftPMRegistersExactBundledFontsAndShipsTheirLicense() throws {
        let originals = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "Fonts", withExtension: nil))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("OFL.txt")),
                       try Data(contentsOf: originals.appendingPathComponent("OFL.txt")))
        for weight in FizzTypography.Weight.allCases {
            let font = FizzTypography.font(13, weight: weight).resolve(in: EnvironmentValues().fontResolutionContext).ctFont
            let url = try XCTUnwrap(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
            XCTAssertEqual(url.standardizedFileURL, directory.appendingPathComponent("ObelMono-\(weight.rawValue).otf").standardizedFileURL)
            XCTAssertEqual(CTFontManagerGetScopeForURL(url as CFURL), .process)
            XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: originals.appendingPathComponent(url.lastPathComponent)))
        }
    }

    @MainActor func testMixedRunsUseObelAndTheMatchingSystemChineseFace() throws {
        let weights: [(FizzTypography.Weight, NSFont.Weight)] = [
            (.regular, .regular), (.medium, .medium), (.semibold, .semibold), (.bold, .bold),
        ]
        for (weight, systemWeight) in weights {
            for size: CGFloat in [12.5, 58] {
                let font = FizzTypography.font(size, weight: weight).resolve(in: EnvironmentValues().fontResolutionContext).ctFont
                let source = try XCTUnwrap(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
                let system = NSFont.systemFont(ofSize: size, weight: systemWeight)
                let chinese = CTFontCreateForStringWithLanguage(system, "中" as CFString, CFRange(location: 0, length: 1), "zh-Hans" as CFString)
                let latinName = "ObelMono-\(weight.rawValue)", chineseName = CTFontCopyPostScriptName(chinese) as String
                XCTAssertTrue(chineseName.contains("PingFang"))
                let spans = [("FizzDeck 23:⌘K!é", latinName), ("，项目【周历】。１２（", chineseName), ("AI", latinName), ("）", chineseName)]
                let text = spans.map(\.0).joined()
                let expected = spans.flatMap { Array(repeating: $0.1, count: $0.0.utf16.count) }
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                var actual = Array(repeating: "", count: expected.count)
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    let name = CTFontCopyPostScriptName(runFont) as String
                    let range = CTRunGetStringRange(run)
                    for offset in range.location..<(range.location + range.length) { actual[offset] = name }
                    XCTAssertEqual(CTFontGetSize(runFont), size)
                    if name == latinName { XCTAssertEqual(CTFontCopyAttribute(runFont, kCTFontURLAttribute) as? URL, source) }
                }
                XCTAssertEqual(actual, expected, "Wrong character mapping at \(size)pt \(weight)")
            }
        }
    }

    @MainActor func testLettersDigitsAndASCIICardSymbolsHaveEqualAdvances() {
        let text = "ilWM0123456789^+*#%@=:"
        for weight in FizzTypography.Weight.allCases {
            let font = FizzTypography.font(11, weight: weight).resolve(in: EnvironmentValues().fontResolutionContext).ctFont
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            let cell = CTLineGetOffsetForStringIndex(line, 1, nil)
            XCTAssertGreaterThan(cell, 0)
            for index in 1...text.utf16.count {
                XCTAssertEqual(CTLineGetOffsetForStringIndex(line, index, nil), cell * CGFloat(index), accuracy: 0.001)
            }
        }
    }

    func testViewsDoNotReplaceBundledTextFaces() throws {
        let symbol = #"Image\(systemName: [^\n)]+\)\s*\.font\(\.system\(size:"#
        try assertNoSourceModifiers(#"\.font\(\.|\bFont\.system\(|\.monospacedDigit\(|\.fontWeight\(|\bFizzTypography\.\w+\.weight\("#,
                                   allowingIn: ["Support/FizzIcon.swift": symbol, "Views/ToastMicroViz.swift": symbol])
    }

    func testControlHeightsHaveOnlyTwoTiers() {
        XCTAssertEqual(FizzControlHeight.allCases, [.standard, .compact])
        XCTAssertEqual(FizzControlHeight.allCases.map(\.rawValue), [28, 24])
    }

    func testProjectAccentIsStableAndReadableInBothAppearances() {
        let colors = (0..<6).map { ProjectAccentColor.color(for: "/projects/fizz-\($0)") }
        XCTAssertEqual(ProjectAccentColor.color(for: "/projects/FizzDeck"), colors[4])
        XCTAssertEqual(ProjectAccentColor.color(for: "/projects/koroo"), colors[2])
        XCTAssertEqual(ProjectAccentColor.color(for: "/projects/放映室"), colors[1])

        for scheme: ColorScheme in [.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let resolved = colors.map { $0.resolve(in: environment) }
            XCTAssertEqual(Set(resolved).count, 6)
            for surface in [FizzTheme.page, FizzTheme.sidebar, FizzTheme.cardFill] {
                let background = luminance(surface.resolve(in: environment))
                for color in resolved {
                    let foreground = luminance(color)
                    let contrast = (max(background, foreground) + 0.05) / (min(background, foreground) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 3, "Project dot contrast in \(scheme)")
                }
            }
        }
    }

    @MainActor func testSparklineUsesTheAvailableRangeAndCentersConstantValues() {
        let rect = CGRect(x: 10, y: 20, width: 80, height: 20)
        XCTAssertEqual(FizzSparkline(samples: [4, 8, 6]).path(in: rect).boundingRect, rect)
        XCTAssertEqual(
            FizzSparkline(samples: [0, 0, 0]).path(in: rect).boundingRect,
            CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: 0)
        )
    }

    @MainActor func testSparklineLeavesMissingOrInvalidSeriesBlank() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 20)
        for samples: [Double] in [[], [3], [0, .nan], [0, .infinity]] {
            XCTAssertTrue(FizzSparkline(samples: samples).path(in: rect).isEmpty)
        }
    }

    func testViewsDoNotUseBorderedButtonStyles() throws {
        try assertNoSourceModifiers(#"\.\s*bordered(?:Prominent)?\b"#)
    }

    func testViewsDoNotUseBorderlessMenuStyle() throws {
        try assertNoSourceModifiers(#"\.\s*menuStyle\s*\(\s*\.\s*borderlessButton\s*\)"#)
    }

    func testMiniControlSizeIsOnlyAppliedDirectlyToProgressView() throws {
        let mini = #"\.\s*controlSize\s*\(\s*(?:ControlSize\s*)?\.\s*mini\s*\)"#
        let progress = #"\bProgressView\s*\([^(){}]*\)\s*"#
        try assertNoSourceModifiers(mini, allowing: progress + mini)
    }

    func testFizzIconCallsDoNotUseLegacyOrNumericSizes() throws {
        try assertNoSourceModifiers(#"\bFizzIcon\s*\(\s*(?:symbol\s*:|size\s*:|[+-]?\d|\.\d)"#)
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

    func testColorBudgetTokensResolveInBothAppearances() {
        let tokens: [(Color, UInt32, UInt32, Float, Float)] = [
            (FizzTheme.accent, 0x6941E8, 0x9F82FF, 1, 1),
            (FizzTheme.accentSoft, 0x6941E8, 0x9F82FF, 0.10, 0.16),
            (FizzTheme.statusDanger, 0xDC3848, 0xFF6B78, 1, 1),
            (FizzTheme.statusWarning, 0xCF6E0C, 0xFFA940, 1, 1),
            (FizzTheme.statusSuccess, 0x159662, 0x38D399, 1, 1),
        ]
        for scheme: ColorScheme in [.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            for (color, light, dark, lightAlpha, darkAlpha) in tokens {
                let hex = scheme == .dark ? dark : light
                func channel(_ shift: Int) -> Double { Double((hex >> shift) & 0xff) / 255 }
                let expected = Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0)).resolve(in: environment)
                let resolved = color.resolve(in: environment)
                XCTAssertEqual(resolved.linearRed, expected.linearRed, accuracy: 0.0001, "\(scheme) \(hex)")
                XCTAssertEqual(resolved.linearGreen, expected.linearGreen, accuracy: 0.0001, "\(scheme) \(hex)")
                XCTAssertEqual(resolved.linearBlue, expected.linearBlue, accuracy: 0.0001, "\(scheme) \(hex)")
                XCTAssertEqual(resolved.opacity, scheme == .dark ? darkAlpha : lightAlpha, accuracy: 0.0001)
            }
        }
    }

    func testLightPageBackgroundIsPureWhite() {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        let resolved = FizzTheme.page.resolve(in: environment)
        XCTAssertEqual(resolved.linearRed, 1, accuracy: 0.0001)
        XCTAssertEqual(resolved.linearGreen, 1, accuracy: 0.0001)
        XCTAssertEqual(resolved.linearBlue, 1, accuracy: 0.0001)
    }

    func testNativeSourceUsesNamedColorTokens() throws {
        let colorNames = "red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|magenta"
        try assertNoSourceModifiers(#"\.\s*(?i:(?:system)?(?:"# + colorNames + #")|accentColor)\b"#,
                                   allowingIn: [
            "Models/Models.swift": #"\bcase\s+\.(?:red|green|blue)\s*:"#,
            "Support/TagColor+UI.swift": #"\bcase\s+\.(?:red|green|blue)\s*:"#,
        ])
        let rawColor = #"(?i)\b0x[0-9a-f]{6,8}\b|#colorLiteral\b|\b(?:Color|NSColor)\s*\(\s*(?:(?:\.\w+\s*,\s*)?(?:red|srgbRed|deviceRed|calibratedRed|displayP3Red|hue|hex|white)\s*:|\")"#
        let surfaces = "statusDanger|statusWarning|statusSuccess|page|sidebar|cardFill|recessedFill|elevatedFill"
        let projects = "mauve|slate|sage|olive|ochre|rose"
        let pair = #"\b(?:"# + surfaces + "|" + projects + #")\s*=\s*fizzAdaptiveColor\(light: 0x[\dA-F]{6}, dark: 0x[\dA-F]{6}\)"#
        let accent = #"\baccent(?:Light|Dark)\s*=\s*fizzHexColor\(0x[\dA-F]{6}\)"#
        let converter = #"\bNSColor\(\s*srgbRed:\s*CGFloat\(\(hex >> 16\)"#
        try assertNoSourceModifiers(rawColor, allowingIn: ["Support/FizzTheme.swift": [pair, accent, converter].joined(separator: "|")])
        try assertNoSourceModifiers(#"\.\s*(?:foregroundStyle|background)\s*\(\s*FizzTheme\.status(?:Danger|Warning|Success)\b"#)
    }

    func testAccentIsLimitedToPrimaryButtonsFocusAndHeatmap() throws {
        let primaryButton = #"\.buttonStyle\(\.glassProminent\)\s*\.tint\(FizzTheme\.accent\)"#
        try assertNoSourceModifiers(#"\bFizzTheme\s*\.\s*accent(?:Soft)?\b"#, allowingIn: [
            "Views/Components.swift": primaryButton,
            "Views/ContentView.swift": primaryButton,
            "Views/FirstRunScanView.swift": primaryButton,
            "Views/ScanReportView.swift": primaryButton,
            "Views/ProjectFolderCard.swift": #"\bfocused\s*\?\s*FizzTheme\.accent\b"#,
            "Views/OverviewTabView.swift": #"\bisDropTargeted \? FizzTheme\.accent : FizzTheme\.stroke\b"#,
            "Views/CommitHeatmapCard.swift": #"\b(?:case [123]|default): FizzTheme\.accent(?:\.opacity\(0\.(?:30|50|73)\))?(?=\s|$)"#,
        ])
    }

    @MainActor func testBundledSidebarAssets() {
        for symbol in [
            "sidebar.left", "gearshape", "archivebox", "checkmark.circle",
            "house", "stethoscope", "bubble.left.and.bubble.right",
            "square.grid.2x2", "magnifyingglass", "calendar",
        ] {
            XCTAssertTrue(FizzIcon.hasBundledAsset(for: symbol), "Missing bundled SVG for \(symbol)")
        }
    }

    @MainActor func testPortStatusBadgeShowsPortWhenRunning() {
        XCTAssertEqual(PortStatusBadge.displayLabel(for: .running, port: 5173), ":5173")
        XCTAssertEqual(PortStatusBadge.displayLabel(for: .running, port: nil), "端口运行中")
        XCTAssertEqual(PortStatusBadge.displayLabel(for: .stopped, port: 5173), "端口未启动")
    }

    private func luminance(_ color: Color.Resolved) -> Float {
        0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
    }

    private func assertNoSourceModifiers(
        _ disallowed: String, allowing allowed: String? = nil, allowingIn: [String: String] = [:]
    ) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FizzDeck", isDirectory: true)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertTrue(files.contains("Views/Components.swift"))

        // Consume comments and string literals before looking for modifiers.
        let trivia = #"//[^\r\n]*|/\*[\s\S]*?\*/|"""[\s\S]*?"""|"(?:\\.|[^"\\])*""#
        for path in files {
            let pattern = [trivia, allowed, allowingIn[path], "(\(disallowed))"].compactMap { $0 }.joined(separator: "|")
            let regex = try NSRegularExpression(pattern: pattern)
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                let line = source[..<range.lowerBound].lazy.filter(\.isNewline).count + 1
                XCTFail("\(path):\(line) uses \(source[range])")
            }
        }
    }
}
