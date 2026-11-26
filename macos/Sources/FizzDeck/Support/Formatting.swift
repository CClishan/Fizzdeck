import Foundation

enum Format {
    nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        let value = max(0, value)
        if value < 1_000 { return "\(value) B" }
        return byteFormatter.string(fromByteCount: value)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        if abs(date.timeIntervalSinceNow) < 10 { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func day(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    static func count(_ value: Int) -> String {
        value.formatted()
    }

    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    static func cost(_ value: Double?, estimated: Bool = false) -> String? {
        guard let value, value >= 0 else { return nil }
        let prefix = estimated ? "~" : ""
        if value < 0.01 {
            return value == 0 ? "\(prefix)$0" : "\(prefix)<$0.01"
        }
        if value < 10 {
            return String(format: "%@$%.2f", prefix, value)
        }
        return String(format: "%@$%.1f", prefix, value)
    }
}
