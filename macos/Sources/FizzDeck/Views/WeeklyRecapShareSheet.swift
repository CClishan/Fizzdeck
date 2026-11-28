import AppKit
import SwiftUI

struct WeeklyRecapShareData: Sendable {
    struct Metric: Sendable {
        let kind: WeeklyRecapMetric
        let title: String
        let value: String
        let detail: String
    }

    struct Project: Sendable {
        let name: String
        let tint: Color
        let buckets: [Double]
    }

    let period: String
    let metrics: [Metric]
    let trendMetric: WeeklyRecapMetric
    let projects: [Project]
}

extension WeeklyRecapShareData {
    init(period: String, analysis: WeeklyRecapAnalysis) {
        let trendMetric: WeeklyRecapMetric = analysis.totals.timedSessions > 0 ? .agentTime : .sessions
        self.init(
            period: period,
            metrics: WeeklyRecapMetric.allCases.map { metric in
                let value = analysis.totals.value(metric)
                let label = if metric == .agentTime, let value, value >= 3_600 {
                    Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
                } else {
                    metric.label(value)
                }
                return .init(kind: metric, title: metric.title, value: label, detail: analysis.totals.detail(metric))
            },
            trendMetric: trendMetric,
            projects: analysis.projects.map { project in
                .init(name: project.name, tint: ProjectAccentColor.color(for: project.id),
                      buckets: analysis.bucketStarts.indices.map { project.buckets[$0]?.value(trendMetric) ?? 0 })
            }
        )
    }
}

struct WeeklyRecapShareContent: Sendable {
    struct Series: Sendable {
        let name: String?
        let tint: Color
        let buckets: [Double]
    }

    let period: String
    let metrics: [WeeklyRecapShareData.Metric]
    let trendTitle: String
    let projectCount: Int
    let series: [Series]

    init(data: WeeklyRecapShareData, hideProjectNames: Bool = true) {
        let hiddenNames = hideProjectNames
            ? Set(data.projects.map { Self.safeText($0.name) }.filter { $0.count >= 4 && $0.contains(where: \.isLetter) })
                .sorted { $0.count > $1.count }
            : []
        // Short or numeric names can coincide with real metric labels or values.
        let alternatives = hiddenNames.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let namePattern = alternatives.isEmpty ? nil : try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_])(?:\#(alternatives))(?![\p{L}\p{N}_])"#, options: .caseInsensitive
        )

        func displayText(_ text: String, limit: Int, isPeriod: Bool = false) -> String {
            let cleaned = Self.safeText(text, isPeriod: isPeriod)
            let anonymous = namePattern?.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " "
            ) ?? cleaned
            return String(anonymous.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
        }

        period = displayText(data.period, limit: 80, isPeriod: true)
        metrics = data.metrics.prefix(4).map {
            .init(kind: $0.kind, title: displayText($0.title, limit: 32), value: displayText($0.value, limit: 24),
                  detail: displayText($0.detail, limit: 40))
        }
        trendTitle = data.trendMetric == .agentTime ? "已记录时长趋势" : "对话趋势"
        projectCount = data.projects.count
        let ranked = data.projects.map { (project: $0, total: $0.buckets.reduce(0, +)) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
        // Anonymous labels describe ranks, not project identities. Give each visible rank its own ink.
        let rankColors = [ProjectAccentColor.slate, ProjectAccentColor.sage, ProjectAccentColor.ochre,
                          ProjectAccentColor.mauve, ProjectAccentColor.rose]
        let limit = ranked.count <= rankColors.count ? rankColors.count : rankColors.count - 1
        var bands = ranked.prefix(limit).enumerated().map { index, entry in
            let project = entry.project
            let name = hideProjectNames ? "" : displayText(project.name, limit: 48)
            return Series(name: name.isEmpty ? nil : name, tint: hideProjectNames ? rankColors[index] : project.tint,
                          buckets: project.buckets)
        }
        if let first = ranked.dropFirst(limit).first {
            let others = ranked.dropFirst(limit + 1).reduce(first.project.buckets) {
                zip($0, $1.project.buckets).map(+)
            }
            bands.append(Series(name: "其他", tint: .secondary, buckets: others))
        }
        series = bands
    }

    private static func safeText(_ raw: String, isPeriod: Bool = false) -> String {
        var text = SecretRedactor.redact(raw).text
        if isPeriod {
            text = text.replacingOccurrences(of: #"(?<=[0-9])/(?=[0-9])"#, with: "-", options: .regularExpression)
        }
        // Drop the field so paths with spaces cannot leave a visible fragment.
        guard !text.contains("/"), !text.contains("\\"),
              !text.localizedCaseInsensitiveContains("%2f"),
              !text.localizedCaseInsensitiveContains("%5c") else { return "" }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum WeeklyRecapShareVisualStyle: String, CaseIterable, Hashable, Sendable {
    case raster
    case ascii

    var title: String {
        switch self {
        case .raster: "光栅"
        case .ascii: "ASCII"
        }
    }
}

@MainActor
enum WeeklyRecapShareRenderer {
    static let pointSize = CGSize(width: 640, height: 400)
    static let scale: CGFloat = 2

    static func pngData(
        for data: WeeklyRecapShareData,
        colorScheme: ColorScheme = .light,
        hideProjectNames: Bool = true,
        visualStyle: WeeklyRecapShareVisualStyle = .raster
    ) -> Data? {
        pngData(
            for: WeeklyRecapShareContent(data: data, hideProjectNames: hideProjectNames),
            colorScheme: colorScheme,
            visualStyle: visualStyle
        )
    }

    fileprivate static func pngData(
        for content: WeeklyRecapShareContent,
        colorScheme: ColorScheme,
        visualStyle: WeeklyRecapShareVisualStyle = .raster
    ) -> Data? {
        let renderer = ImageRenderer(content: card(for: content, colorScheme: colorScheme, visualStyle: visualStyle))
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    fileprivate static func card(
        for content: WeeklyRecapShareContent,
        colorScheme: ColorScheme,
        visualStyle: WeeklyRecapShareVisualStyle = .raster
    ) -> some View {
        WeeklyRecapShareCard(content: content, visualStyle: visualStyle)
            .frame(width: pointSize.width, height: pointSize.height)
            .environment(\.colorScheme, colorScheme)
    }
}

struct WeeklyRecapShareSheet: View {
    let data: WeeklyRecapShareData

    @Environment(\.dismiss) private var dismiss
    @State private var colorScheme: ColorScheme = .light
    @State private var visualStyle: WeeklyRecapShareVisualStyle = .raster
    @State private var hideProjectNames = true

    var body: some View {
        let content = WeeklyRecapShareContent(data: data, hideProjectNames: hideProjectNames)

        VStack(spacing: 0) {
            FizzSheetHeader(title: "复盘分享卡") { dismiss() }
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)

            Divider()

            VStack(spacing: FizzSpacing.grid) {
                HStack(spacing: FizzSpacing.grid) {
                    FizzSegmentedCapsule(
                        items: [ColorScheme.light, .dark], selection: $colorScheme,
                        keyboardNavigation: true
                    ) { scheme, _ in
                        Text(scheme == .dark ? "暗色" : "浅色")
                            .font(FizzTypography.caption(.medium))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("分享卡外观")

                    FizzSegmentedCapsule(
                        items: WeeklyRecapShareVisualStyle.allCases, selection: $visualStyle,
                        keyboardNavigation: true
                    ) { style, _ in
                        Text(style.title)
                            .font(FizzTypography.caption(.medium))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("视觉样式")

                    Spacer()

                    Toggle("隐藏项目名", isOn: $hideProjectNames)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.secondary)
                        .fizzKeyboardAction { hideProjectNames.toggle() }
                }

                WeeklyRecapShareRenderer.card(for: content, colorScheme: colorScheme, visualStyle: visualStyle)
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)

            Divider()

            FizzSheetFooter {
                FizzActionButton(title: "复制 PNG", symbol: "doc.on.clipboard", height: .standard, prominence: .primary) {
                    copyPNG(content)
                }
                .keyboardShortcut(.defaultAction)
                .fizzKeyboardAction { copyPNG(content) }
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: WeeklyRecapShareRenderer.pointSize.width + 2 * FizzSpacing.page)
        .background(FizzTheme.page)
        .onExitCommand { dismiss() }
    }

    private func copyPNG(_ content: WeeklyRecapShareContent) {
        if let png = WeeklyRecapShareRenderer.pngData(for: content, colorScheme: colorScheme, visualStyle: visualStyle) {
            let pasteboard = NSPasteboard.general
            _ = pasteboard.prepareForNewContents(with: .currentHostOnly)
            if pasteboard.setData(png, forType: .png) {
                ToastCenter.shared.show("复盘分享卡已复制", symbol: "photo", tint: FizzTheme.statusSuccess)
                return
            }
        }
        ToastCenter.shared.show("无法复制 PNG", symbol: "exclamationmark.triangle", tint: FizzTheme.statusWarning)
    }
}

private struct WeeklyRecapShareCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: WeeklyRecapShareContent
    let visualStyle: WeeklyRecapShareVisualStyle

    private let inset: CGFloat = 36
    private let rasterColumnCount = 79
    private let asciiRows = 17

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                header
                HStack(alignment: .top, spacing: FizzSpacing.page) {
                    agentTime
                        .frame(maxWidth: .infinity, alignment: .leading)
                    secondaryMetrics
                        .frame(width: 204)
                }
            }
            .padding(.horizontal, inset)
            .padding(.top, 26)
            .padding(.bottom, 12)

            trend
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, inset)
                .padding(.bottom, 8)
            legend
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                FizzTheme.page
                if colorScheme == .dark {
                    Color.black.opacity(0.42)
                }
            }
        }
        .overlay { Rectangle().strokeBorder(FizzTheme.stroke).allowsHitTesting(false) }
    }

    private var header: some View {
        HStack(spacing: FizzSpacing.grid) {
            HStack(spacing: FizzSpacing.row) {
                FizzLogo(size: 24).accessibilityHidden(true)
                Text("FizzDeck")
                    .font(FizzTypography.font(20, weight: .semibold))
                    .tracking(-0.3)
            }
            .fixedSize()
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Text(verbatim: ["\(content.projectCount) 个项目", content.period].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(FizzTypography.mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var agentTime: some View {
        let metric = content.metrics.first { $0.kind == .agentTime }
        return VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: metric?.title ?? WeeklyRecapMetric.agentTime.title)
                .font(FizzTypography.font(13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(verbatim: value(of: metric))
                .font(FizzTypography.font(58, weight: .semibold))
                .tracking(-2.0)
                .minimumScaleFactor(0.46)
            if let detail = metric?.detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var secondaryMetrics: some View {
        VStack(spacing: 10) {
            ForEach([WeeklyRecapMetric.cost, .tokens, .sessions], id: \.self) { kind in
                let metric = content.metrics.first { $0.kind == kind }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: metric?.title ?? kind.title)
                            .font(FizzTypography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer(minLength: FizzSpacing.row)
                        Text(verbatim: value(of: metric))
                            .font(FizzTypography.font(21, weight: .semibold))
                            .minimumScaleFactor(0.65)
                    }
                    if kind == .cost, let detail = metric?.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var trend: some View {
        if content.series.isEmpty {
            Text("暂无对话")
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
        } else {
            Canvas { context, size in
                let bucketCount = content.series[0].buckets.count
                let empty = Array(repeating: 0.0, count: bucketCount)
                let totals = content.series.reduce(empty) { zip($0, $1.buckets).map(+) }
                guard let peak = totals.max(), peak > 0 else { return }

                switch visualStyle {
                case .raster:
                    drawRasterTrend(in: &context, size: size, peak: peak)
                case .ascii:
                    drawASCIITrend(in: &context, size: size, peak: peak)
                }
            }
            .accessibilityLabel("按项目堆叠的\(content.trendTitle)")
        }
    }

    private func drawRasterTrend(in context: inout GraphicsContext, size: CGSize, peak: Double) {
        let isDark = colorScheme == .dark
        let step = size.width / CGFloat(rasterColumnCount)
        let barWidth = max(2, step * 0.66)
        let gridLineColor = Color.primary.opacity(isDark ? 0.045 : 0.035)
        let scanlineColor = (isDark ? Color.black : Color.white).opacity(isDark ? 0.22 : 0.16)
        let crestColor = Color.white.opacity(isDark ? 0.40 : 0.24)

        for col in 0..<rasterColumnCount {
            let centerX = (CGFloat(col) + 0.5) * step
            let u = Double(col) / Double(max(1, rasterColumnCount - 1))

            if col % 4 == 0 {
                let tick = CGRect(x: centerX - 0.25, y: 4, width: 0.5, height: size.height - 4)
                context.fill(Path(tick), with: .color(gridLineColor))
            }

            let bands = stackedIntervals(at: u, peak: peak)
            let visibleBands = bands.filter { $0.upper - $0.lower > 0.002 }
            for (index, band) in visibleBands.enumerated() {
                let rawTop = size.height * (1 - 0.90 * band.upper)
                let rawBottom = size.height * (1 - 0.90 * band.lower)
                let gap: CGFloat = (index > 0 && rawBottom - rawTop > 3) ? 1.0 : 0
                let yTop = rawTop
                let yBottom = max(yTop + 1.5, rawBottom - gap)
                let barRect = CGRect(x: centerX - barWidth / 2, y: yTop, width: barWidth, height: yBottom - yTop)
                let corner = min(1.6, barWidth * 0.28)
                let barPath = Path(roundedRect: barRect, cornerRadius: corner)

                context.fill(
                    barPath,
                    with: .linearGradient(
                        Gradient(colors: [band.tint, band.tint.opacity(isDark ? 0.80 : 0.86)]),
                        startPoint: CGPoint(x: 0, y: barRect.minY),
                        endPoint: CGPoint(x: 0, y: barRect.maxY)
                    )
                )

                // Optical lenticular scanlines for print-like raster rhythm.
                var scanY = ceil(barRect.minY / 4) * 4
                while scanY < barRect.maxY - 1 {
                    let slit = CGRect(x: barRect.minX, y: scanY, width: barRect.width, height: 0.65)
                    context.fill(Path(slit), with: .color(scanlineColor))
                    scanY += 4
                }

                if index == visibleBands.count - 1 && barRect.height >= 4 {
                    let capRect = CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: min(2.5, barRect.height * 0.28))
                    context.fill(Path(roundedRect: capRect, cornerRadius: corner), with: .color(crestColor))
                }
            }
        }
    }

    private func drawASCIITrend(in context: inout GraphicsContext, size: CGSize, peak: Double) {
        let isDark = colorScheme == .dark
        var lower = Array(repeating: 0.0, count: content.series[0].buckets.count)
        for series in content.series {
            let upper = zip(lower, series.buckets).map(+)
            let path = area(lower: lower, upper: upper, peak: peak, size: size)
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [series.tint.opacity(isDark ? 0.16 : 0.08), series.tint.opacity(isDark ? 0.06 : 0.03)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            lower = upper
        }

        let cols = rasterColumnCount
        let rows = asciiRows
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        let ramp = ["^", "+", "*", "#", "%", "@", "=", ":"]
        let font = FizzTypography.font(8.5, weight: .semibold)

        for col in 0..<cols {
            let u = Double(col) / Double(max(1, cols - 1))
            let bands = stackedIntervals(at: u, peak: peak)
            let topMost = bands.last?.upper ?? 0
            let x = (CGFloat(col) + 0.5) * cellW

            for row in 0..<rows {
                let h = (Double(rows - 1 - row) + 0.5) / Double(rows)
                let scaledH = h / 0.90
                let y = (CGFloat(row) + 0.5) * cellH

                if let band = bands.first(where: { scaledH >= $0.lower && scaledH <= $0.upper && ($0.upper - $0.lower) > 0.002 }) {
                    let depth = max(0, min(1, (topMost - scaledH) / max(topMost, 0.01)))
                    let baseIndex = Int(depth * Double(ramp.count - 1))
                    let index = min(ramp.count - 1, max(0, baseIndex + ((col * 5 + row * 3) % 2 == 0 ? 0 : 1)))
                    let glyph = ramp[index]
                    let alpha = 1.0 - 0.16 * depth
                    let text = Text(verbatim: glyph).font(font).foregroundStyle(band.tint.opacity(alpha))
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
                } else if topMost > 0 && scaledH > topMost && (scaledH - topMost) < 0.28 {
                    let fade = max(0, 1 - (scaledH - topMost) / 0.28)
                    let dotOpacity = (isDark ? 0.11 : 0.09) * fade
                    let text = Text(verbatim: "·").font(font).foregroundStyle(Color.primary.opacity(dotOpacity))
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
                }
            }
        }
    }

    private func stackedIntervals(at u: Double, peak: Double) -> [(tint: Color, lower: Double, upper: Double)] {
        var cumulativeLower = 0.0
        return content.series.map { series in
            let sampled = sampleSeries(series.buckets, at: u)
            let lower = cumulativeLower / peak
            cumulativeLower += sampled
            let upper = cumulativeLower / peak
            return (tint: series.tint, lower: lower, upper: upper)
        }
    }

    private func sampleSeries(_ buckets: [Double], at u: Double) -> Double {
        let values = buckets.count == 1 ? buckets + buckets : buckets
        guard values.count > 1 else { return values.first ?? 0 }
        let scaled = max(0, min(1, u)) * Double(values.count - 1)
        let i0 = Int(floor(scaled))
        let i1 = min(values.count - 1, i0 + 1)
        let t = scaled - Double(i0)
        // Smoothstep matches monotonic cubic band curves with zero layer crossing.
        let smooth = t * t * (3 - 2 * t)
        return values[i0] + (values[i1] - values[i0]) * smooth
    }

    private func area(lower: [Double], upper: [Double], peak: Double, size: CGSize) -> Path {
        func points(_ buckets: [Double]) -> [CGPoint] {
            let values = buckets.count == 1 ? buckets + buckets : buckets
            return values.enumerated().map { index, value in
                CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: size.height * (1 - 0.90 * value / peak))
            }
        }

        return Path { path in
            func trace(_ edge: [CGPoint]) {
                for (start, end) in zip(edge, edge.dropFirst()) {
                    // Both edges use the same curve weights, so stacked bands cannot cross.
                    let mid = (start.x + end.x) / 2
                    path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y),
                                  control2: CGPoint(x: mid, y: end.y))
                }
            }

            let top = points(upper)
            let bottom = Array(points(lower).reversed())
            guard let start = top.first, let end = bottom.first else { return }
            path.move(to: start)
            trace(top)
            path.addLine(to: end)
            trace(bottom)
            path.closeSubpath()
        }
    }

    private var legend: some View {
        HStack(spacing: FizzSpacing.row) {
            Text(verbatim: content.trendTitle).fixedSize()
            Spacer(minLength: FizzSpacing.grid)
            ForEach(content.series.indices, id: \.self) { index in
                let series = content.series[index]
                HStack(spacing: 4) {
                    Circle().fill(series.tint).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(verbatim: series.name ?? "项目 \(index + 1)").lineLimit(1)
                }
            }
        }
        .font(FizzTypography.monoSmall)
        .foregroundStyle(.secondary)
        .padding(.horizontal, inset)
        .frame(height: 32)
        .overlay(alignment: .top) { Rectangle().fill(FizzTheme.hairline).frame(height: 1) }
    }

    private func value(of metric: WeeklyRecapShareData.Metric?) -> String {
        guard let value = metric?.value, !value.isEmpty else { return "—" }
        return value
    }
}
