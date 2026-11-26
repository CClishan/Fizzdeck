import Foundation

struct TestOutcomeSummary: Equatable, Sendable {
    let passed: Int
    let failed: Int

    static func parse(_ output: String, status: TestStatus) -> TestOutcomeSummary {
        let text = String(output.suffix(32_000))

        if let counts = captures(
            in: text,
            pattern: #"Tests run:\s*(\d+).*?Failures:\s*(\d+)"#
        ), counts.count == 2 {
            return summary(total: counts[0], failed: counts[1])
        }

        if let counts = captures(
            in: text,
            pattern: #"Executed\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failures?"#
        ), counts.count == 2 {
            return summary(total: counts[0], failed: counts[1])
        }

        if let counts = captures(
            in: text,
            pattern: #"(\d+)\s+passed(?:,|\s|$).*?(\d+)\s+failed"#
        ), counts.count == 2 {
            return TestOutcomeSummary(passed: counts[0], failed: counts[1])
        }

        if let counts = captures(
            in: text,
            pattern: #"(\d+)\s+passing(?:,|\s|$).*?(\d+)\s+failing"#
        ), counts.count == 2 {
            return TestOutcomeSummary(passed: counts[0], failed: counts[1])
        }

        let passed = firstCapture(
            in: text,
            pattern: #"Tests\s+(\d+)\s+passed"#
        ) ?? firstCapture(
            in: text,
            pattern: #"Test run with\s+(\d+)\s+tests?\s+passed"#
        ) ?? firstCapture(
            in: text,
            pattern: #"(\d+)\s+passed"#
        )

        let failed = firstCapture(
            in: text,
            pattern: #"Tests\s+(\d+)\s+failed"#
        ) ?? firstCapture(
            in: text,
            pattern: #"(\d+)\s+failed"#
        ) ?? firstCapture(
            in: text,
            pattern: #"(\d+)\s+failing"#
        )

        if passed != nil || failed != nil {
            return TestOutcomeSummary(
                passed: max(0, passed ?? 0),
                failed: max(0, failed ?? 0)
            )
        }

        return TestOutcomeSummary(
            passed: status == .passed ? 1 : 0,
            failed: status == .failed ? 1 : 0
        )
    }

    private static func summary(total: Int, failed: Int) -> TestOutcomeSummary {
        let total = max(0, total)
        let failed = min(total, max(0, failed))
        return TestOutcomeSummary(passed: total - failed, failed: failed)
    }

    private static func captures(in text: String, pattern: String) -> [Int]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
    }

    private static func firstCapture(in text: String, pattern: String) -> Int? {
        captures(in: text, pattern: pattern)?.first
    }
}
