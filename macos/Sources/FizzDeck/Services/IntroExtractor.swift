import Foundation

enum IntroExtractor {
    private static let introDocs = [
        "PRODUCT.md", "README.md", "README.zh-CN.md", "HANDOFF.MD", "CLAUDE.md", "AGENTS.md",
    ]

    static func extract(_ directory: URL) -> ProjectIntro {
        let product = FileTools.readFileIfExists(directory.appendingPathComponent("PRODUCT.md"))
        for heading in ["Product Purpose", "Purpose", "Overview", "Summary", "Users"] {
            if let section = section(named: heading, in: product) {
                let body = stripMarkdown(section)
                if body.count > 30 {
                    return ProjectIntro(text: String(body.prefix(320)), source: "PRODUCT.md")
                }
            }
        }

        for name in introDocs {
            let raw = FileTools.readFileIfExists(directory.appendingPathComponent(name))
            guard !raw.isEmpty else { continue }
            let lines = raw.split(separator: "\n").map(String.init).filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty
                    && !trimmed.hasPrefix("<")
                    && !trimmed.hasPrefix("!")
                    && !trimmed.hasPrefix("[")
                    && !trimmed.hasPrefix("|")
            }
            var paragraph: [String] = []
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    if !paragraph.isEmpty { break }
                    continue
                }
                paragraph.append(line)
                if paragraph.joined(separator: " ").count > 220 { break }
            }
            let text = stripMarkdown(paragraph.joined(separator: " "))
            if text.count > 24 {
                return ProjectIntro(text: String(text.prefix(320)), source: name)
            }
        }

        if let package = FileTools.json(directory.appendingPathComponent("package.json")),
           let description = package["description"] as? String,
           !description.isEmpty {
            return ProjectIntro(text: String(description.prefix(320)), source: "package.json")
        }
        return .empty
    }

    private static func section(named name: String, in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let pattern = "(?is)##\\s*\(name)\\s*\\n(.*?)(?=\\n##\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let bodyRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[bodyRange])
    }

    static func stripMarkdown(_ text: String) -> String {
        var value = text
        value = replace(#"(?s)<!--.*?-->"#, in: value, with: "")
        value = replace(#"(?s)```.*?```"#, in: value, with: "")
        value = replace(#"(?m)^#{1,6}\s*"#, in: value, with: "")
        value = replace(#"\[([^\]]+)\]\([^)]+\)"#, in: value, with: "$1")
        value = replace(#"[*_`>]"#, in: value, with: "")
        value = value.replacingOccurrences(of: "|", with: " ")
        value = replace(#"\s+"#, in: value, with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
