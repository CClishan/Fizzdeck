import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import FizzDeck

final class WeeklyRecapShareTests: XCTestCase {
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
        XCTAssertEqual(anonymous.period, "11-22 – 11-28")
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
            let data = WeeklyRecapShareData(period: "最近 \(days) 天", analysis: analysis)
            let content = WeeklyRecapShareContent(data: data, hideProjectNames: false)

            XCTAssertEqual(content.projectCount, 7)
            XCTAssertEqual(content.trendTitle, "已记录时长趋势")
            XCTAssertEqual(content.series.compactMap(\.name), ["Studio 6", "Studio 5", "Studio 4", "Studio 3", "其他"])
            XCTAssertEqual(content.series.last?.buckets.first, 180)
            XCTAssertEqual(content.series.last?.buckets.last, 240)
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
        let content = WeeklyRecapShareContent(data: .init(period: "全部", analysis: analysis))
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

    private func pixels(in png: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try XCTUnwrap(image.dataProvider?.data)
        return bytes as Data
    }
}
