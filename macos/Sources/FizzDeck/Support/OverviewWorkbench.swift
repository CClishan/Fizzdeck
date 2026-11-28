import CoreGraphics
import Foundation

extension SessionMark {
    static let manualCheckpointLabel = "手动记录点"

    var projectCheckpointTitle: String {
        label == Self.manualCheckpointLabel ? FizzL10n.text(Self.manualCheckpointLabel, "Manual checkpoint") : displayLabel
    }
}

struct WorkbenchDay: Equatable, Sendable {
    let key: String
    let count: Int
}

struct ByteParts: Equatable, Sendable {
    let value: String
    let unit: String
}

enum WorkbenchMetrics {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    static func lastSevenDays(
        counts: [String: Int],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkbenchDay] {
        let today = calendar.startOfDay(for: now)
        return stride(from: 6, through: 0, by: -1).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = dayKey(date, calendar: calendar)
            return WorkbenchDay(key: key, count: max(0, counts[key] ?? 0))
        }
    }

    static func sessionDayCounts(
        _ sessions: [SessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -6, to: today) else {
            return Array(repeating: 0, count: 7)
        }

        var counts = Array(repeating: 0, count: 7)
        for session in sessions {
            let day = calendar.startOfDay(for: session.modified)
            guard day >= oldest, day <= today else { continue }
            let offset = calendar.dateComponents([.day], from: oldest, to: day).day ?? -1
            if counts.indices.contains(offset) {
                counts[offset] += 1
            }
        }
        return counts
    }

    static func normalized(_ values: [Int]) -> [Double] {
        guard let peak = values.max(), peak > 0 else {
            return values.map { _ in 0 }
        }
        return values.map { Double(max(0, $0)) / Double(peak) }
    }

    static func emphasisIndex(_ values: [Int]) -> Int? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return values.lastIndex(of: peak)
    }

    static func cleanupBars(_ items: [CleanupItem], limit: Int = 7) -> [Int] {
        guard limit > 0 else { return [] }
        var values = items.prefix(limit).map { max(0, Int(clamping: $0.bytes)) }
        while values.count < limit {
            values.append(0)
        }
        return values
    }

    static func splitBytes(_ bytes: Int64) -> ByteParts {
        let value = max(0, bytes)
        if value < 1_000 {
            return ByteParts(value: "\(value)", unit: "B")
        }

        let units = ["KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var index = -1
        while amount >= 1_000, index < units.count - 1 {
            amount /= 1_000
            index += 1
        }

        var rounded = (amount * 10).rounded() / 10
        while rounded >= 1_000, index < units.count - 1 {
            rounded = (rounded / 1_000 * 10).rounded() / 10
            index += 1
        }
        let text = rounded.formatted(.number.grouping(.never).precision(.fractionLength(0...1)).locale(FizzL10n.locale))
        return ByteParts(value: text, unit: units[max(0, index)])
    }
}

enum LogTailReader {
    static let defaultMaxBytes = 16_384
    static let defaultMaxLines = 40

    static func read(
        path: String,
        maxBytes: Int = defaultMaxBytes,
        maxLines: Int = defaultMaxLines
    ) -> String {
        guard maxBytes > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        else { return "" }
        defer { try? handle.close() }

        let total = size.int64Value
        guard total > 0 else { return "" }
        let start = max(0, total - Int64(maxBytes))
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return "" }
        return tail(decodeTail(data), maxLines: maxLines)
    }

    static func tail(_ text: String, maxLines: Int = defaultMaxLines) -> String {
        guard maxLines > 0, !text.isEmpty else { return "" }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard lines.count > maxLines else { return text }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    static func decodeTail(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var dropped = 0
        while dropped < min(3, bytes.count),
              bytes[dropped] & 0b1100_0000 == 0b1000_0000 {
            dropped += 1
        }
        if dropped > 0 {
            bytes.removeFirst(dropped)
        }
        if let text = String(bytes: bytes, encoding: .utf8) {
            return text
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum OverviewSummaryLayout: Equatable, Sendable {
    case threeColumns
    case twoPlusBottom
    case twoColumns
    case stacked
}

enum OverviewLayoutPolicy {
    static let threeColumnMinWidth: CGFloat = 760
    static let twoColumnMinWidth: CGFloat = 520
    static let sideBySideMinWidth: CGFloat = 780

    static func summaryLayout(width: CGFloat, hasArtwork: Bool) -> OverviewSummaryLayout {
        if hasArtwork {
            if width >= threeColumnMinWidth { return .threeColumns }
            if width >= twoColumnMinWidth { return .twoPlusBottom }
            return .stacked
        }
        return width >= twoColumnMinWidth ? .twoColumns : .stacked
    }

    static func showsLogsAndActivitySideBySide(
        width: CGFloat,
        hasLogs: Bool,
        hasActivity: Bool
    ) -> Bool {
        hasLogs && hasActivity && width >= sideBySideMinWidth
    }

    static func splitWidths(
        totalWidth: CGFloat,
        spacing: CGFloat,
        leadingRatio: CGFloat = 0.58
    ) -> (leading: CGFloat, trailing: CGFloat) {
        let available = max(0, totalWidth - spacing)
        let leading = (available * leadingRatio).rounded(.down)
        return (leading, max(0, available - leading))
    }
}
