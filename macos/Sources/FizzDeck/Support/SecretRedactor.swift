import Foundation

struct RedactionResult: Equatable, Sendable {
    let text: String
    let redactedCount: Int
}

enum SecretRedactor {
    private static let placeholder = "[已脱敏]"

    private static let bearerRegex = try? NSRegularExpression(
        pattern: #"(?i)\bBearer\s+[A-Za-z0-9._-]{20,}"#
    )

    private static let tokenRegex = try? NSRegularExpression(
        pattern: #"(?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,}|gh[pou]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,})"#
    )

    private static let envAssignmentRegex = try? NSRegularExpression(
        pattern: #"(?m)(\b[A-Z0-9_]*(?:API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY)[A-Z0-9_]*\s*=\s*)(['"]?)([^\s'"\n]{8,})\2"#
    )

    static func redact(_ input: String) -> RedactionResult {
        guard !input.isEmpty else {
            return RedactionResult(text: input, redactedCount: 0)
        }

        var current = input
        var totalCount = 0

        if let bearerRegex {
            let (updated, count) = replaceAll(
                regex: bearerRegex,
                in: current
            ) { _, _ in
                "Bearer \(placeholder)"
            }
            current = updated
            totalCount += count
        }

        if let tokenRegex {
            let (updated, count) = replaceAll(
                regex: tokenRegex,
                in: current
            ) { _, _ in
                placeholder
            }
            current = updated
            totalCount += count
        }

        if let envAssignmentRegex {
            let (updated, count) = replaceAll(
                regex: envAssignmentRegex,
                in: current
            ) { match, nsText in
                let prefix = nsText.substring(with: match.range(at: 1))
                let quoteRange = match.range(at: 2)
                let quote = quoteRange.location != NSNotFound ? nsText.substring(with: quoteRange) : ""
                let value = nsText.substring(with: match.range(at: 3))
                if value == placeholder || value.contains(placeholder) {
                    return nil
                }
                return "\(prefix)\(quote)\(placeholder)\(quote)"
            }
            current = updated
            totalCount += count
        }

        return RedactionResult(text: current, redactedCount: totalCount)
    }

    static func containsSecret(_ input: String) -> Bool {
        redact(input).redactedCount > 0
    }

    private static func replaceAll(
        regex: NSRegularExpression,
        in input: String,
        transform: (NSTextCheckingResult, NSString) -> String?
    ) -> (String, Int) {
        let nsText = input as NSString
        let matches = regex.matches(
            in: input,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return (input, 0) }

        let mutable = NSMutableString(string: input)
        var count = 0
        for match in matches.reversed() {
            guard let replacement = transform(match, nsText) else { continue }
            mutable.replaceCharacters(in: match.range, with: replacement)
            count += 1
        }
        return (mutable as String, count)
    }
}
