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

    static func relative(_ date: Date?, now: Date = Date(), locale: Locale = FizzL10n.locale) -> String {
        guard let date else { return "—" }
        if abs(date.timeIntervalSince(now)) < 10 { return locale.language.languageCode == .chinese ? "刚刚" : "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = locale
        return spaceChineseUnits(formatter.localizedString(for: date, relativeTo: now), locale: locale)
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: FizzL10n.locale))
    }

    static func monthDay(_ date: Date, locale: Locale = FizzL10n.locale) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
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
        value.formatted(.number.locale(FizzL10n.locale))
    }

    static func tokens(_ value: Int, locale: Locale = FizzL10n.locale) -> String {
        compactCount(Double(value), locale: locale)
    }

    static func compactCount(_ value: Double, locale: Locale = FizzL10n.locale) -> String {
        let text = value.formatted(.number.notation(.compactName).locale(locale))
        return spaceChineseUnits(text, locale: locale)
    }

    private static func spaceChineseUnits(_ text: String, locale: Locale) -> String {
        guard locale.language.languageCode == .chinese else { return text }
        return text.replacingOccurrences(of: #"(?<=\d)(?=\p{Han})"#, with: " ", options: .regularExpression)
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
