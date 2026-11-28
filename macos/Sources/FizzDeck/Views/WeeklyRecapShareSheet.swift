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

    // Keep only aggregate facts in a prepared share. Resolve its labels when previewing or exporting.
    fileprivate enum Labels: Sendable {
        case report(WeeklyRecapRange, Date, Date, Calendar, WeeklyRecapTotals)
        case supplied(String, [Metric])
    }

    fileprivate let labels: Labels
    let trendMetric: WeeklyRecapMetric
    let projects: [Project]
    private(set) var isProjectReport = false

    init(period: String, metrics: [Metric], trendMetric: WeeklyRecapMetric, projects: [Project]) {
        labels = .supplied(period, metrics)
        self.trendMetric = trendMetric
        self.projects = projects
    }
}

extension WeeklyRecapShareData {
    init(recap: WeeklyRecap, calendar: Calendar? = nil) {
        self.init(range: recap.range, start: recap.windowStart, end: recap.generatedAt,
                  calendar: calendar ?? recap.calendar, analysis: recap.analysis)
    }

    init(project: RepoProject, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let candidates = project.sessions.recentSessions.filter {
            $0.kind == .conversation && (start...now).contains($0.modified) && $0.cwd?.hasPrefix("/") == true
        }
        // Use the index's exact directory identity (including symlink aliases), never a name or path prefix.
        let scoped = SessionIndex.summary(for: URL(fileURLWithPath: project.path), in: candidates)
        let rows = scoped.recentSessions.map {
            WeeklyRecapSession(projectPath: project.path, projectName: project.displayName, record: $0)
        }
        self.init(range: .week, start: start, end: now, calendar: calendar,
                  analysis: .build(sessions: rows, previous: nil, previousStart: nil, start: start, now: now, calendar: calendar))
        isProjectReport = true
    }

    init(range: WeeklyRecapRange, start: Date, end: Date, calendar: Calendar, analysis: WeeklyRecapAnalysis) {
        labels = .report(range, start, end, calendar, analysis.totals)
        let metric: WeeklyRecapMetric = analysis.totals.timedSessions > 0 ? .agentTime : .sessions
        trendMetric = metric
        projects = analysis.projects.map { project in
            .init(name: project.name, tint: ProjectAccentColor.color(for: project.id),
                  buckets: analysis.bucketStarts.indices.map { project.buckets[$0]?.value(metric) ?? 0 })
        }
    }

    var period: String {
        switch labels {
        case let .supplied(period, _): return period
        case let .report(range, start, end, calendar, _):
            let format = DateFormatter()
            format.locale = FizzL10n.locale
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)
            format.dateFormat = FizzL10n.text(sameYear ? "MM.dd" : "yyyy.MM.dd", sameYear ? "MMM d" : "MMM d, yyyy")
            return "\(range.periodTitle) · \(format.string(from: start)) – \(format.string(from: end))"
        }
    }

    var metrics: [Metric] {
        switch labels {
        case let .supplied(_, metrics): return metrics
        case let .report(_, _, _, _, totals):
            return WeeklyRecapMetric.allCases.map { metric in
                let value = totals.value(metric)
                let label = if metric == .agentTime, let value, value >= 3_600 {
                    Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes], width: .narrow,
                                                             maximumUnitCount: 2).locale(FizzL10n.locale))
                } else {
                    metric.label(value)
                }
                return .init(kind: metric, title: metric.title, value: label, detail: totals.detail(metric))
            }
        }
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
    let scopeTitle: String
    let series: [Series]

    init(data: WeeklyRecapShareData, hideProjectNames: Bool = true) {
        let hiddenNames: [String]
        if hideProjectNames, case .supplied = data.labels {
            hiddenNames = Set(data.projects.map { Self.safeText($0.name) }.filter { $0.count >= 4 && $0.contains(where: \.isLetter) })
                .sorted { $0.count > $1.count }
        } else {
            hiddenNames = []
        }
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
        trendTitle = data.trendMetric == .agentTime ? FizzL10n.text("已记录时长趋势", "Recorded time") : FizzL10n.text("对话趋势", "Sessions over time")
        projectCount = data.isProjectReport ? 1 : data.projects.count
        scopeTitle = data.isProjectReport ? FizzL10n.text("项目战报", "Project report")
            : FizzL10n.text("\(projectCount) 个项目", SessionSummaryText.englishCount(projectCount, "project"))
        let ranked = data.projects.map { (project: $0, total: $0.buckets.reduce(0, +)) }
            .filter { $0.total > 0 }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                // Break anonymous ties with public activity, never the private directory order.
                return hideProjectNames && lhs.project.buckets.lexicographicallyPrecedes(rhs.project.buckets, by: >)
            }
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
            bands.append(Series(name: FizzL10n.text("其他", "Other"), tint: .secondary, buckets: others))
        }
        series = bands
    }

    func legendName(at index: Int) -> String {
        series[index].name ?? FizzL10n.text("项目 \(index + 1)", "Project \(index + 1)")
    }

    private static func safeText(_ raw: String, isPeriod: Bool = false) -> String {
        var text = SecretRedactor.redact(raw).text
        if isPeriod {
            // Accept the old month/day range without converting numeric path components into safe-looking text.
            let date = #"(0?[1-9]|1[0-2])[/-](0?[1-9]|[12][0-9]|3[01])"#
            text = text.replacingOccurrences(of: #"(?<!\S)"# + date + #"(?:\s*[–—]\s*|\s+-\s+)"# + date + #"(?!\S)"#,
                                             with: "$1.$2 – $3.$4", options: .regularExpression)
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
        case .raster: FizzL10n.text("光栅", "Raster")
        case .ascii: "ASCII"
        }
    }
}

enum WeeklyRecapSharePalette: String, CaseIterable {
    case color = "彩色"
    case mono = "Mono"

    var title: String { self == .color ? FizzL10n.text("彩色", "Color") : rawValue }
}

struct WeeklyRecapShareAppearance {
    var colorScheme: ColorScheme = .light
    var visualStyle: WeeklyRecapShareVisualStyle = .raster
    var palette: WeeklyRecapSharePalette = .color
    var showsBrand = true
}

@MainActor
enum WeeklyRecapShareRenderer {
    static let pointSize = CGSize(width: 640, height: 400)
    static let scale: CGFloat = 2

    static func pngData(
        for data: WeeklyRecapShareData,
        colorScheme: ColorScheme = .light,
        hideProjectNames: Bool = true,
        visualStyle: WeeklyRecapShareVisualStyle = .raster,
        palette: WeeklyRecapSharePalette = .color,
        showsBrand: Bool = true
    ) -> Data? {
        let content = WeeklyRecapShareContent(data: data, hideProjectNames: hideProjectNames)
        let appearance = WeeklyRecapShareAppearance(colorScheme: colorScheme, visualStyle: visualStyle,
                                                   palette: palette, showsBrand: showsBrand)
        return pngData(of: card(for: content, appearance: appearance), palette: palette)
    }

    fileprivate static func pngData(of card: some View, palette: WeeklyRecapSharePalette) -> Data? {
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = scale
        renderer.isOpaque = true
        guard var image = renderer.cgImage else { return nil }
        if palette == .mono {
            // A desaturated SwiftUI layer can still have tinted RGB pixels after color conversion.
            guard let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: gray,
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let monochrome = context.makeImage() else { return nil }
            image = monochrome
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    fileprivate static func card(for content: WeeklyRecapShareContent, appearance: WeeklyRecapShareAppearance) -> some View {
        WeeklyRecapShareCard(content: content, appearance: appearance)
            .frame(width: pointSize.width, height: pointSize.height)
            .foregroundStyle(.primary)
            .grayscale(appearance.palette == .mono ? 1 : 0)
            .environment(\.locale, FizzL10n.locale)
            .environment(\.colorScheme, appearance.colorScheme)
            .environment(\.displayScale, scale)
    }
}

struct WeeklyRecapShareSheet: View {
    let data: WeeklyRecapShareData
    var title: String? = nil
    private var sheetTitle: String {
        data.isProjectReport ? FizzL10n.text("项目战报", "Project Report") : (title ?? FizzL10n.text("复盘分享卡", "Recap Card"))
    }

    @Environment(\.dismiss) private var dismiss
    @State private var appearance = WeeklyRecapShareAppearance()
    @State private var hideProjectNames = true

    var body: some View {
        let content = WeeklyRecapShareContent(data: data, hideProjectNames: hideProjectNames)
        let card = WeeklyRecapShareRenderer.card(for: content, appearance: appearance)

        VStack(spacing: 0) {
            FizzSheetHeader(title: sheetTitle) { dismiss() }
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)

            Divider()

            VStack(spacing: FizzSpacing.grid) {
                HStack(spacing: FizzSpacing.grid) {
                    FizzSegmentedCapsule(
                        items: [ColorScheme.light, .dark], selection: $appearance.colorScheme,
                        keyboardNavigation: true
                    ) { scheme, _ in
                        Text(scheme == .dark ? FizzL10n.text("暗色", "Dark") : FizzL10n.text("浅色", "Light"))
                            .font(FizzTypography.caption(.medium))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(FizzL10n.text("分享卡外观", "Card appearance"))

                    FizzSegmentedCapsule(
                        items: WeeklyRecapShareVisualStyle.allCases, selection: $appearance.visualStyle,
                        keyboardNavigation: true
                    ) { style, _ in
                        Text(style.title)
                            .font(FizzTypography.caption(.medium))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(FizzL10n.text("视觉样式", "Chart style"))

                    FizzSegmentedCapsule(
                        items: WeeklyRecapSharePalette.allCases, selection: $appearance.palette,
                        keyboardNavigation: true
                    ) { palette, _ in
                        Text(palette.title).font(FizzTypography.caption(.medium))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(FizzL10n.text("分享卡配色", "Card palette"))

                    Spacer()

                    shareSwitch(FizzL10n.text("隐藏项目名", "Hide names"), isOn: $hideProjectNames, help: FizzL10n.text("用项目编号代替真实名称", "Replace project names with numbered labels."))
                    shareSwitch(FizzL10n.text("显示底部品牌", "Show brand"), isOn: $appearance.showsBrand, help: FizzL10n.text("在分享卡右下角显示 fizzdeck 字标", "Show the fizzdeck wordmark in the lower-right corner."))
                }

                card
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)

            Divider()

            FizzSheetFooter {
                FizzActionButton(title: FizzL10n.text("复制 PNG", "Copy PNG"), symbol: "doc.on.clipboard", height: .standard, prominence: .primary) {
                    copyPNG(card)
                }
                .keyboardShortcut(.defaultAction)
                .fizzKeyboardAction { copyPNG(card) }
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: WeeklyRecapShareRenderer.pointSize.width + 2 * FizzSpacing.page)
        .background(FizzTheme.page)
        .onExitCommand { dismiss() }
    }

    private func shareSwitch(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
                .font(FizzTypography.body)
                .onTapGesture { isOn.wrappedValue.toggle() }
                .accessibilityHidden(true)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(.secondary)
                .accessibilityLabel(Text(verbatim: title))
                .help(help)
                .fizzKeyboardAction { isOn.wrappedValue.toggle() }
        }
        .fixedSize()
    }

    private func copyPNG(_ card: some View) {
        if let png = WeeklyRecapShareRenderer.pngData(of: card, palette: appearance.palette) {
            let pasteboard = NSPasteboard.general
            _ = pasteboard.prepareForNewContents(with: .currentHostOnly)
            if pasteboard.setData(png, forType: .png) {
                ToastCenter.shared.show(FizzL10n.text("\(sheetTitle)已复制", "\(sheetTitle) copied"), symbol: "photo", tint: FizzTheme.statusSuccess)
                return
            }
        }
        ToastCenter.shared.show(FizzL10n.text("无法复制 PNG", "Couldn’t copy the PNG"), symbol: "exclamationmark.triangle", tint: FizzTheme.statusWarning)
    }
}

private struct WeeklyRecapShareCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: WeeklyRecapShareContent
    let appearance: WeeklyRecapShareAppearance

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
                if appearance.palette == .mono {
                    colorScheme == .dark ? Color.black : Color.white
                } else if colorScheme == .dark {
                    FizzTheme.page
                    Color.black.opacity(0.42)
                } else {
                    FizzTheme.page
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

            Text(verbatim: [content.scopeTitle, content.period].filter { !$0.isEmpty }.joined(separator: " · "))
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
        let costNote = content.metrics.first { $0.kind == .cost }?.detail ?? ""
        return VStack(spacing: costNote.isEmpty ? 10 : 6) {
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
                    if kind != .sessions, !costNote.isEmpty {
                        // Reserve the same line between the three value baselines when cost has a note.
                        Text(verbatim: costNote)
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .opacity(kind == .cost ? 1 : 0)
                            .accessibilityHidden(kind != .cost)
                    }
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var trend: some View {
        if content.series.isEmpty {
            Text(FizzL10n.text("暂无对话", "No sessions"))
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
        } else {
            Canvas { context, size in
                let bucketCount = content.series[0].buckets.count
                let empty = Array(repeating: 0.0, count: bucketCount)
                let totals = content.series.reduce(empty) { zip($0, $1.buckets).map(+) }
                guard let peak = totals.max(), peak > 0 else { return }

                switch appearance.visualStyle {
                case .raster:
                    drawRasterTrend(in: &context, size: size, peak: peak)
                case .ascii:
                    drawASCIITrend(in: &context, size: size, peak: peak)
                }
            }
            .accessibilityLabel(FizzL10n.text("按项目堆叠的\(content.trendTitle)", "\(content.trendTitle), stacked by project"))
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
        for index in content.series.indices {
            let upper = zip(lower, content.series[index].buckets).map(+)
            let tint = ink(at: index)
            let path = area(lower: lower, upper: upper, peak: peak, size: size)
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(isDark ? 0.16 : 0.08), tint.opacity(isDark ? 0.06 : 0.03)]),
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
            guard topMost > 0 else { continue }
            let x = (CGFloat(col) + 0.5) * cellW

            for row in 0..<rows {
                let h = (Double(rows - 1 - row) + 0.5) / Double(rows)
                let scaledH = h / 0.90
                let y = (CGFloat(row) + 0.5) * cellH

                // Sample a real nonzero tail in the bottom cell even when it is below the cell's midpoint.
                let sampleH = row == rows - 1 ? min(scaledH, topMost) : scaledH
                if let band = bands.first(where: { $0.upper > $0.lower && sampleH >= $0.lower && sampleH <= $0.upper }) {
                    let depth = max(0, min(1, (topMost - scaledH) / max(topMost, 0.01)))
                    let baseIndex = Int(depth * Double(ramp.count - 1))
                    let index = min(ramp.count - 1, max(0, baseIndex + ((col * 5 + row * 3) % 2 == 0 ? 0 : 1)))
                    let glyph = ramp[index]
                    let alpha = 1.0 - 0.16 * depth
                    let text = Text(verbatim: glyph).font(font).foregroundStyle(band.tint.opacity(alpha))
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
                } else if scaledH > topMost && (scaledH - topMost) < 0.28 {
                    let fade = max(0, 1 - (scaledH - topMost) / 0.28)
                    let dotOpacity = (isDark ? 0.22 : 0.09) * fade
                    let text = Text(verbatim: "·").font(font).foregroundStyle(Color.primary.opacity(dotOpacity))
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
                }
            }
        }
    }

    private func stackedIntervals(at u: Double, peak: Double) -> [(tint: Color, lower: Double, upper: Double)] {
        var cumulativeLower = 0.0
        return content.series.indices.map { index in
            let sampled = sampleSeries(content.series[index].buckets, at: u)
            let lower = cumulativeLower / peak
            cumulativeLower += sampled
            let upper = cumulativeLower / peak
            return (tint: ink(at: index), lower: lower, upper: upper)
        }
    }

    private func ink(at index: Int) -> Color {
        if appearance.palette == .mono {
            return (colorScheme == .dark ? Color.white : .black).opacity(0.94 - 0.13 * Double(index))
        }
        return content.series[index].tint
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
            ForEach(content.series.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    Circle().fill(ink(at: index)).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(verbatim: content.legendName(at: index)).lineLimit(1)
                }
            }
            Spacer(minLength: FizzSpacing.grid)
            if appearance.showsBrand {
                Text(verbatim: "fizzdeck")
                    .font(FizzTypography.monoSmall(.medium))
                    .fixedSize()
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
