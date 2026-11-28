import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import FizzDeck

final class WeeklyRecapShareTests: ChineseInterfaceTestCase {
    @MainActor
    func testPreparedChineseProjectCardExportsEnglishRasterAndASCIIWithoutLeakingProjectData() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 3)))
        func prepare(_ name: String, marker: String) -> WeeklyRecapShareData {
            let path = "/fixture/\(marker)"
            let row = SessionRecord(tool: "codex", id: marker, cwd: path, startedAt: nil, modified: now,
                lastUser: "TEST_API_KEY=\(marker)", model: marker, usage: TokenUsage(totalTokens: 20_000), costUSD: 1.25,
                firstUser: name, touchedFiles: [path + "/Private.swift"], lastError: marker, agentTimeSeconds: 5_400)
            return .init(project: fixtureProject(path: path, name: name, records: [row]), now: now, calendar: calendar)
        }

        let privateName = "客户原名"
        let prepared = FizzL10n.$languageOverride.withValue(.chinese) { prepare(privateName, marker: "private-marker-one") }
        try FizzL10n.$languageOverride.withValue(.english) {
            // A project named after a public label must not change even one anonymous pixel.
            let fresh = prepare("Sessions", marker: "private-marker-two")
            let card = WeeklyRecapShareContent(data: prepared)
            XCTAssertEqual(card.scopeTitle, "Project report")
            XCTAssertEqual(card.period, "Last 7 days · Dec 28, 2025 – Jan 3, 2026")
            XCTAssertEqual(card.metrics.map(\.title), ["Sessions", "Agent time", "Estimated cost", "Tokens"])
            XCTAssertEqual(card.metrics.first { $0.kind == .tokens }?.value, "20K")
            let time = try XCTUnwrap(card.metrics.first { $0.kind == .agentTime })
            XCTAssertTrue(time.value.contains("1h") && time.value.contains("30m"), time.value)
            XCTAssertEqual(time.detail, "Time recorded for 1 session")
            XCTAssertEqual(card.legendName(at: 0), "Project 1")
            XCTAssertEqual(WeeklyRecapShareContent(data: prepared, hideProjectNames: false).legendName(at: 0), privateName)

            var stylePixels: [Data] = []
            for style in WeeklyRecapShareVisualStyle.allCases {
                let english = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: prepared, visualStyle: style))
                let renamed = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: fresh, visualStyle: style))
                let source = try XCTUnwrap(CGImageSourceCreateWithData(english as CFData, nil))
                XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
                let bitmap = try image(in: english)
                XCTAssertEqual(bitmap.width, 1_280)
                XCTAssertEqual(bitmap.height, 800)
                let pixels = try pixels(in: english)
                XCTAssertTrue(pixels == (try self.pixels(in: renamed)))
                stylePixels.append(pixels)
                let metadata = String(describing: CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
                for text in [privateName, "private-marker", "/fixture/", "Private.swift", "TEST_API_KEY"] {
                    XCTAssertFalse(metadata.contains(text))
                }

                let chinese = try FizzL10n.$languageOverride.withValue(.chinese) {
                    try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: prepared, visualStyle: style))
                }
                let date = CGRect(x: 400, y: 38, width: 800, height: 85)
                let legend = CGRect(x: 66, y: 736, width: 900, height: 64)
                for region in [date, legend] {
                    XCTAssertTrue(try croppedPixels(in: english, rect: region) != croppedPixels(in: chinese, rect: region))
                }
            }
            XCTAssertNotEqual(stylePixels.first, stylePixels.last)
        }
    }

    @MainActor
    func testBothAppearancesExportFixedSizePNGWithDifferentBackgrounds() async throws {
        let data = sample(projectName: "Fixture Project")
        let lightPNG = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data))
        let darkPNG = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data, colorScheme: .dark))

        for png in [lightPNG, darkPNG] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let fileType = try XCTUnwrap(CGImageSourceGetType(source))
            XCTAssertEqual(fileType as String, UTType.png.identifier)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1_280)
            XCTAssertEqual(image.height, 800)
        }

        let light = try backgroundRedComponent(in: lightPNG)
        let dark = try backgroundRedComponent(in: darkPNG)
        XCTAssertGreaterThan(light, dark + 0.45)
    }

    func testAnonymousContentRemovesProjectNamesFromEveryDisplayFieldAndKeepsCounts() {
        let data = WeeklyRecapShareData(
            period: "11/22 – 11/28  Night Studio",
            metrics: [.init(kind: .sessions, title: "对话 night studio", value: "6 次", detail: "NightStudioLab Night Studio")],
            trendMetric: .sessions,
            projects: [.init(name: "Night Studio", tint: .purple, buckets: [0, 2, 0, 2]),
                       .init(name: "NightStudioLab", tint: .blue, buckets: [1, 0, 1, 0])]
        )

        let anonymous = WeeklyRecapShareContent(data: data)
        XCTAssertEqual(anonymous.period, "11.22 – 11.28")
        XCTAssertEqual(anonymous.metrics.first?.title, "对话")
        XCTAssertEqual(anonymous.metrics.first?.value, "6 次")
        XCTAssertEqual(anonymous.metrics.first?.detail, "")
        XCTAssertTrue(anonymous.series.allSatisfy { $0.name == nil })
        XCTAssertEqual(anonymous.projectCount, 2)
        XCTAssertEqual(anonymous.series.map(\.buckets), data.projects.map(\.buckets))

        let named = WeeklyRecapShareContent(data: data, hideProjectNames: false)
        XCTAssertEqual(named.series.compactMap(\.name), ["Night Studio", "NightStudioLab"])
    }

    func testShortNamesAndPartialMatchesDoNotRemoveMetricText() {
        let data = WeeklyRecapShareData(
            period: "近期 · 2026 年",
            metrics: [.init(kind: .sessions, title: "AI 对话", value: "42 次", detail: "Switchboard")],
            trendMetric: .sessions,
            projects: ["AI", "42", "2026", "Board"].map { .init(name: $0, tint: .blue, buckets: [1]) }
        )

        let content = WeeklyRecapShareContent(data: data)
        XCTAssertEqual(content.period, data.period)
        XCTAssertEqual(content.metrics.first?.title, "AI 对话")
        XCTAssertEqual(content.metrics.first?.value, "42 次")
        XCTAssertEqual(content.metrics.first?.detail, "Switchboard")
        XCTAssertTrue(content.series.allSatisfy { $0.name == nil })
    }

    func testShareStacksRecordedTimeAcrossTheFullRangeAndGroupsSmallerProjects() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        for days in [7, 30, 90, 365] {
            let end = calendar.date(byAdding: .day, value: days - 1, to: start)!
            let sessions = (1...6).flatMap { number in
                [session(number, at: start, seconds: number * 60), session(number, at: end, seconds: 120)]
            } + [session(7, at: end, seconds: nil)]
            let analysis = WeeklyRecapAnalysis.build(
                sessions: sessions, previous: nil, previousStart: nil, start: start, now: end, calendar: calendar
            )
            let data = WeeklyRecapShareData(range: .all, start: start, end: end, calendar: calendar, analysis: analysis)
            let content = WeeklyRecapShareContent(data: data, hideProjectNames: false)

            XCTAssertEqual(content.projectCount, 7)
            XCTAssertEqual(content.trendTitle, "已记录时长趋势")
            XCTAssertEqual(content.series.compactMap(\.name), ["Studio 6", "Studio 5", "Studio 4", "Studio 3", "其他"])
            XCTAssertEqual(content.series.last?.buckets.first, 180)
            XCTAssertEqual(content.series.last?.buckets.last, 240)
            FizzL10n.$languageOverride.withValue(.english) {
                let anonymous = WeeklyRecapShareContent(data: data)
                XCTAssertEqual(anonymous.series.indices.map { anonymous.legendName(at: $0) },
                               ["Project 1", "Project 2", "Project 3", "Project 4", "Other"])
            }
            let totals = analysis.bucketStarts.indices.map { index in content.series.reduce(0) { $0 + $1.buckets[index] } }
            XCTAssertEqual(totals, analysis.samples(.agentTime).map { $0 ?? 0 })
        }
    }

    func testMissingAgentTimeKeepsDashAndPlotsConversationCounts() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let analysis = WeeklyRecapAnalysis.build(
            sessions: [session(1, at: now, seconds: nil), session(2, at: now, seconds: nil)],
            previous: nil, previousStart: nil, start: calendar.startOfDay(for: now), now: now, calendar: calendar
        )
        let content = WeeklyRecapShareContent(data: .init(range: .all, start: now, end: now, calendar: calendar, analysis: analysis))
        XCTAssertEqual(content.metrics.first { $0.kind == .agentTime }?.value, "—")
        XCTAssertEqual(content.trendTitle, "对话趋势")
        XCTAssertEqual(content.series.map(\.buckets), [[1], [1]])
    }

    func testPathsAndSecretsDoNotReachTheCardWhenProjectNamesAreShown() {
        let fixtureValue = ["fizzdeck", "share", "fixture"].joined(separator: "-")
        let data = WeeklyRecapShareData(
            period: "文件 %2FUsers%2Ffixture%2Fwork",
            metrics: [.init(kind: .cost, title: "改动文件 Sources/Core.swift", value: "FIXTURE_API_KEY=\(fixtureValue)",
                            detail: "本地路径 /Users/fixture/Private Work")],
            trendMetric: .agentTime,
            projects: [.init(name: #"C:\Development\Private Work"#, tint: .purple, buckets: [2]),
                       .init(name: "FIXTURE_API_KEY=\(fixtureValue)", tint: .blue, buckets: [1])]
        )

        let content = WeeklyRecapShareContent(data: data, hideProjectNames: false)
        XCTAssertTrue(content.period.isEmpty)
        XCTAssertEqual(content.metrics.first?.title, "")
        XCTAssertEqual(content.metrics.first?.value, "FIXTURE_API_KEY=[已脱敏]")
        XCTAssertEqual(content.metrics.first?.detail, "")
        XCTAssertNil(content.series.first?.name)
        XCTAssertEqual(content.series.last?.name, "FIXTURE_API_KEY=[已脱敏]")
    }

    func testSharePeriodUsesDottedDatesInTheRecapTimeZoneAndKeepsBothYearsWhenNeeded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        for (month, day, expected) in [(11, 28, "11.22 – 11.28"), (1, 3, "2025.12.28 – 2026.01.03")] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
            let recap = WeeklyRecapService.build(projects: [], now: now, calendar: calendar)
            let content = WeeklyRecapShareContent(data: .init(recap: recap, calendar: calendar))
            XCTAssertEqual(content.period, "最近 7 天 · \(expected)")
        }

        let legacy = WeeklyRecapShareData(period: "11-22–11-28", metrics: [], trendMetric: .sessions, projects: [])
        XCTAssertEqual(WeeklyRecapShareContent(data: legacy).period, "11.22 – 11.28")
        for path in ["11/22/11/28", "11/22-11/28", "11/22–11/28/file", "/11/22 – 11/28", #"C:\11\22"#, "%2f11%2f22"] {
            let data = WeeklyRecapShareData(period: path, metrics: [], trendMetric: .sessions, projects: [])
            XCTAssertEqual(WeeklyRecapShareContent(data: data).period, "", path)
        }
    }

    func testProjectCardCountsOnlySelectedDirectoryConversationsInTheLastSevenCalendarDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)))
        let path = "/tmp/share-fixture/client"
        let name = "Private Studio"
        func record(_ cwd: String?, at date: Date, kind: SessionRecordKind = .conversation) -> SessionRecord {
            SessionRecord(tool: "codex", id: "\(date.timeIntervalSince1970)", cwd: cwd, startedAt: nil, modified: date,
                          kind: kind, usage: TokenUsage(totalTokens: 100), costUSD: 0.25, agentTimeSeconds: 60)
        }
        let unrelated = [record("/tmp/other/client", at: now), record(path + "-other", at: now),
                         record(path + "/child", at: now), record(nil, at: now), record("", at: now),
                         record(path, at: start.addingTimeInterval(-1)), record(path, at: now.addingTimeInterval(1)),
                         record(path, at: now, kind: .workspaceSummary)]
        let project = fixtureProject(path: path, name: name, records: unrelated + [record(path, at: start), record(path, at: now)])
        let data = WeeklyRecapShareData(project: project, now: now, calendar: calendar)
        let content = WeeklyRecapShareContent(data: data)
        XCTAssertEqual(content.projectCount, 1)
        XCTAssertEqual(content.series.map(\.buckets), [[60, 0, 0, 0, 0, 0, 60]])
        XCTAssertNil(content.series.first?.name)
        XCTAssertEqual(WeeklyRecapShareContent(data: data, hideProjectNames: false).series.first?.name, name)
        let expected: [(WeeklyRecapMetric, Double)] = [(.sessions, 2), (.agentTime, 120), (.tokens, 200), (.cost, 0.5)]
        for (metric, value) in expected {
            XCTAssertEqual(content.metrics.first { $0.kind == metric }?.value, metric.label(value))
        }

        let empty = fixtureProject(path: path, name: name, records: unrelated)
        let emptyCard = WeeklyRecapShareContent(data: .init(project: empty, now: now, calendar: calendar))
        XCTAssertTrue(emptyCard.series.isEmpty)
        XCTAssertEqual(emptyCard.projectCount, 1)
        XCTAssertEqual(emptyCard.scopeTitle, "项目战报")
        XCTAssertEqual(emptyCard.metrics.first { $0.kind == .sessions }?.value, WeeklyRecapMetric.sessions.label(0))
        XCTAssertEqual(emptyCard.metrics.first { $0.kind == .agentTime }?.value, "—")
    }

    @MainActor
    func testAnonymousPNGPixelsDoNotDependOnOriginalProjectNames() async throws {
        let first = sample(projectName: "Fixture Alpha")
        let second = sample(projectName: "Fixture Beta")
        for scheme in [ColorScheme.light, .dark] {
            let anonymousFirst = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: first, colorScheme: scheme))
            let anonymousSecond = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: second, colorScheme: scheme))
            let namedFirst = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: first, colorScheme: scheme, hideProjectNames: false))
            let firstPixels = try pixels(in: anonymousFirst)
            XCTAssertTrue(firstPixels == (try pixels(in: anonymousSecond)))
            XCTAssertTrue(firstPixels != (try pixels(in: namedFirst)))
        }
    }

    func testFiveAnonymousBandsStayDistinctWhenAllProjectsHaveTheSameColor() {
        let data = WeeklyRecapShareData(period: "全部", metrics: [], trendMetric: .sessions, projects:
            (1...5).map { .init(name: "Studio \($0)", tint: ProjectAccentColor.rose, buckets: [Double($0)]) })
        let anonymous = WeeklyRecapShareContent(data: data).series
        let named = WeeklyRecapShareContent(data: data, hideProjectNames: false).series
        XCTAssertEqual(Set(anonymous.map(\.tint)).count, 5)
        XCTAssertEqual(Set(named.map(\.tint)), [ProjectAccentColor.rose])
        XCTAssertEqual(anonymous.map(\.buckets), named.map(\.buckets))
    }

    func testTiedAnonymousBandsIgnorePrivateProjectOrder() {
        let left = WeeklyRecapShareData.Project(name: "Private A", tint: .blue, buckets: [2, 0])
        let right = WeeklyRecapShareData.Project(name: "Private B", tint: .red, buckets: [0, 2])
        func bands(_ projects: [WeeklyRecapShareData.Project]) -> [[Double]] {
            WeeklyRecapShareContent(data: .init(period: "", metrics: [], trendMetric: .sessions, projects: projects))
                .series.map(\.buckets)
        }
        XCTAssertEqual(bands([left, right]), bands([right, left]))
    }

    @MainActor
    func testNamedPNGDrawsBothProjectColorsOverTheSameTimeBucket() async throws {
        let data = WeeklyRecapShareData(period: "全部", metrics: [], trendMetric: .sessions, projects: [
            .init(name: "Studio One", tint: .red, buckets: [3]), .init(name: "Studio Two", tint: .blue, buckets: [2]),
        ])
        let png = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data, hideProjectNames: false))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let colors = (0..<bitmap.pixelsHigh).compactMap { y in
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.usingColorSpace(.sRGB)
        }
        let red = colors.indices.filter { colors[$0].redComponent - colors[$0].blueComponent > 0.35 }
        let blue = colors.indices.filter { colors[$0].blueComponent - colors[$0].redComponent > 0.35 }
        XCTAssertGreaterThan(red.count, 60)
        XCTAssertGreaterThan(blue.count, 60)
        XCTAssertLessThan(try XCTUnwrap(blue.last), try XCTUnwrap(red.first))
    }

    @MainActor
    func testRasterAndASCIIVisualStylesExportDistinctFixedSizePNGs() async throws {
        let first = sample(projectName: "Fixture Alpha")
        let second = sample(projectName: "Fixture Beta")

        for scheme in [ColorScheme.light, .dark] {
            let rasterPNG = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: first, colorScheme: scheme, visualStyle: .raster))
            let asciiPNG = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: first, colorScheme: scheme, visualStyle: .ascii))
            let asciiSecond = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: second, colorScheme: scheme, visualStyle: .ascii))

            for png in [rasterPNG, asciiPNG] {
                let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(image.width, 1_280)
                XCTAssertEqual(image.height, 800)
            }

            let rasterPixels = try pixels(in: rasterPNG)
            let asciiPixels = try pixels(in: asciiPNG)
            XCTAssertTrue(rasterPixels != asciiPixels)
            XCTAssertTrue(asciiPixels == (try pixels(in: asciiSecond)))
        }
    }

    @MainActor
    func testSingleProjectPNGsAreAnonymousFixedSizeAndMonoIsAchromaticInEveryStyleAndAppearance() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        func makeData(name: String, token: String) -> WeeklyRecapShareData {
            let path = "/tmp/\(name)"
            let record = SessionRecord(tool: "codex", id: token, cwd: path, startedAt: nil, modified: now,
                                       lastUser: "FIXTURE_API_KEY=\(token)", model: token, costUSD: 1.25,
                                       firstUser: name, touchedFiles: [path + "/\(token).swift"],
                                       lastError: token, agentTimeSeconds: 240)
            return .init(project: fixtureProject(path: path, name: name, records: [record]), now: now)
        }
        let first = makeData(name: "Fixture Alpha", token: "private-alpha-marker")
        let second = makeData(name: "Fixture Beta", token: "private-beta-marker")
        for scheme in [ColorScheme.light, .dark] {
            for style in WeeklyRecapShareVisualStyle.allCases {
                for palette in WeeklyRecapSharePalette.allCases {
                    let png = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: first, colorScheme: scheme,
                                                                             visualStyle: style, palette: palette))
                    let renamed = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: second, colorScheme: scheme,
                                                                                 visualStyle: style, palette: palette))
                    let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
                    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                    XCTAssertEqual(try XCTUnwrap(CGImageSourceGetType(source)) as String, UTType.png.identifier)
                    XCTAssertEqual(image.width, 1_280)
                    XCTAssertEqual(image.height, 800)
                    let metadata = String(describing: CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
                    XCTAssertFalse(metadata.contains("Fixture Alpha") || metadata.contains("private-alpha-marker"))
                    XCTAssertTrue(try pixels(in: png) == pixels(in: renamed), "\(scheme), \(style), \(palette)")
                    let rgba = try rgbaPixels(of: image)
                    if palette == .mono {
                        XCTAssertEqual(image.colorSpace?.model, .monochrome)
                        XCTAssertEqual(image.bitsPerPixel, 8)
                    } else {
                        XCTAssertTrue(hasChroma(rgba, above: 40), "\(scheme), \(style): expected project ink")
                    }
                }
            }
        }
    }

    @MainActor
    func testDefaultColorAndBrandAndTurningBrandOffChangesOnlyTheFooterCorner() async throws {
        XCTAssertEqual(WeeklyRecapShareAppearance().palette, .color)
        XCTAssertTrue(WeeklyRecapShareAppearance().showsBrand)
        let data = sample(projectName: "Fixture Project")
        let standard = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data))
        let branded = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data, palette: .color, showsBrand: true))
        let unbranded = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data, showsBrand: false))
        XCTAssertTrue(try pixels(in: standard) == pixels(in: branded))

        let aboveFooter = CGRect(x: 0, y: 0, width: 1_280, height: 736)
        let legend = CGRect(x: 0, y: 736, width: 1_040, height: 64)
        let brand = CGRect(x: 1_040, y: 736, width: 240, height: 64)
        for rect in [aboveFooter, legend] {
            XCTAssertTrue(try croppedPixels(in: branded, rect: rect) == croppedPixels(in: unbranded, rect: rect))
        }
        XCTAssertTrue(try croppedPixels(in: branded, rect: brand) != croppedPixels(in: unbranded, rect: brand))
    }

    @MainActor
    func testASCIIDrawsInkForASubCellTailAndLeavesTheZeroPlateauEmpty() async throws {
        let data = WeeklyRecapShareData(period: "", metrics: [], trendMetric: .agentTime,
                                        projects: [.init(name: "Tail", tint: .blue, buckets: [1_000, 0, 0, 1, 1])])
        for scheme in [ColorScheme.light, .dark] {
            let png = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data, colorScheme: scheme, visualStyle: .ascii))
            let tail = try croppedPixels(in: png, rect: CGRect(x: 1_100, y: 670, width: 100, height: 50))
            let zero = try croppedPixels(in: png, rect: CGRect(x: 440, y: 670, width: 100, height: 50))
            XCTAssertTrue(hasChroma(tail, above: 40), "\(scheme): actual low-amplitude glyphs")
            XCTAssertFalse(hasChroma(zero, above: 8), "\(scheme): no colored baseline at zero")
        }
    }

    @MainActor
    func testCostSublineKeepsTheThreeValueBaselinesEvenlySpaced() async throws {
        let kinds: [WeeklyRecapMetric] = [.cost, .tokens, .sessions]
        let width = 640, height = 350
        func values(_ digits: String) throws -> Data {
            let data = WeeklyRecapShareData(period: "", metrics: kinds.map {
                .init(kind: $0, title: $0.title, value: digits, detail: $0 == .cost ? "另有 3 次未计价" : "")
            }, trendMetric: .sessions, projects: [])
            let png = try XCTUnwrap(WeeklyRecapShareRenderer.pngData(for: data))
            return try croppedPixels(in: png, rect: CGRect(x: 640, y: 100, width: width, height: height))
        }
        // Only the three values change; their horizontal position and the note's width need not be assumed.
        let first = try values("888"), second = try values("111")
        var starts = [Int]()
        var lastInkRow: Int?
        for y in 0..<height {
            guard (0..<width).contains(where: { x in
                let i = 4 * (y * width + x)
                return abs(Int(first[i]) - Int(second[i])) > 32
            }) else { continue }
            if y - (lastInkRow ?? -10) > 8 { starts.append(y) }
            lastInkRow = y
        }
        XCTAssertEqual(starts.count, 3)
        if starts.count == 3 {
            XCTAssertLessThanOrEqual(abs((starts[1] - starts[0]) - (starts[2] - starts[1])), 2)
        }
    }

    private func fixtureProject(path: String, name: String, records: [SessionRecord]) -> RepoProject {
        var summary = SessionSummary.empty
        summary.recentSessions = records
        summary.sessionCount = records.count
        return RepoProject(path: path, name: name, displayName: name, group: "private", recent: nil, branch: nil,
                           lastCommit: nil, dirtyCount: 0, changes: .zero, ahead: 0, behind: 0, weekly: [:],
                           stacks: [], size: .empty, cleanup: .empty, run: nil, sessions: summary, intro: .empty,
                           artwork: nil, test: nil, starred: false, color: nil, note: "", port: .noPreview)
    }

    private func sample(projectName: String) -> WeeklyRecapShareData {
        WeeklyRecapShareData(
            period: "11 月 22 日 – 11 月 28 日",
            metrics: [.init(kind: .sessions, title: "AI 对话", value: "6 次", detail: "本周")],
            trendMetric: .sessions,
            projects: [.init(name: projectName, tint: .purple, buckets: [0, 1, 2, 0, 0, 2, 1])]
        )
    }

    private func session(_ number: Int, at date: Date, seconds: Int?) -> WeeklyRecapSession {
        let path = "/tmp/studio-\(number)"
        let record = SessionRecord(tool: seconds == nil ? "cursor" : "codex", id: "\(date.timeIntervalSince1970)",
                                   cwd: path, startedAt: nil, modified: date, agentTimeSeconds: seconds)
        return WeeklyRecapSession(projectPath: path, projectName: "Studio \(number)", record: record)
    }

    private func backgroundRedComponent(in png: Data) throws -> CGFloat {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let rgb = try XCTUnwrap(bitmap.colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB))
        return rgb.redComponent
    }

    private func image(in png: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(in png: Data) throws -> Data {
        try XCTUnwrap(image(in: png).dataProvider?.data) as Data
    }

    private func croppedPixels(in png: Data, rect: CGRect) throws -> Data {
        try rgbaPixels(of: XCTUnwrap(image(in: png).cropping(to: rect)))
    }

    private func rgbaPixels(of region: CGImage) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: region.width, height: region.height, bitsPerComponent: 8, bytesPerRow: region.width * 4,
            space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(region, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
        return Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * region.height)
    }

    private func hasChroma(_ rgba: Data, above threshold: UInt8) -> Bool {
        rgba.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return stride(from: 0, to: bytes.count, by: 4).contains { i in
                let r = bytes[i], g = bytes[i + 1], b = bytes[i + 2]
                return max(r, g, b) - min(r, g, b) > threshold
            }
        }
    }
}
