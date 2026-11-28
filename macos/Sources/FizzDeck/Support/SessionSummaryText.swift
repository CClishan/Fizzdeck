import Foundation

enum SessionSummaryText {
    static func englishCount(_ count: Int, _ noun: String) -> String {
        "\(count.formatted(.number.locale(FizzL10n.locale))) \(noun)\(count == 1 ? "" : "s")"
    }

    static func clean(_ value: String) -> String {
        var text = value

        text = removeBlock(named: "environment_context", from: text)
        text = removeBlock(named: "user_instructions", from: text)
        text = removeBlock(named: "ide_opened_file", from: text)
        text = removeBlock(named: "ide_selection", from: text)
        text = removeBlock(named: "system-reminder", from: text)

        text = stripIDEPreamble(from: text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let ignoredPrefixes = [
            "[Request interrupted",
            "[Tool use interrupted",
            "[Request cancelled",
        ]
        if ignoredPrefixes.contains(where: { text.hasPrefix($0) }) {
            return ""
        }
        return String(text.prefix(400))
    }

    static func stripIDEPreamble(from value: String) -> String {
        let lines = value.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ).map(String.init)

        let markers = [
            "## My request for Codex:",
            "## My request:",
        ]
        if let markerIndex = lines.firstIndex(where: { line in
            markers.contains(line.trimmingCharacters(in: .whitespaces))
        }) {
            return lines.dropFirst(markerIndex + 1).joined(separator: "\n")
        }

        guard let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("# Files mentioned by the user")
        else {
            return value
        }
        return ""
    }

    private static func removeBlock(named name: String, from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return value.replacingOccurrences(
            of: "(?s)<\(escaped)>.*?</\(escaped)>",
            with: "",
            options: .regularExpression
        )
    }
}
