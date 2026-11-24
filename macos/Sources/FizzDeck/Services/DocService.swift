import Foundation

enum DocService {
    static func list(_ directory: URL) -> [DocFile] {
        AppPaths.docCandidates.compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard FileTools.exists(url),
                  let attributes = try? FileTools.manager.attributesOfItem(atPath: url.path)
            else { return nil }
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = attributes[.modificationDate] as? Date
            let text = FileTools.readText(url, maxBytes: 200_000)
            let title = firstTitle(in: text) ?? name
            return DocFile(
                file: name,
                title: String(title.prefix(80)),
                bytes: bytes,
                modified: modified,
                lines: text.split(separator: "\n", omittingEmptySubsequences: false).count
            )
        }
    }

    static func read(_ directory: URL, file: String) -> String? {
        guard AppPaths.docCandidates.contains(file) else { return nil }
        let url = directory.appendingPathComponent(file)
        guard FileTools.exists(url) else { return nil }
        return String(FileTools.readText(url, maxBytes: 200_000).prefix(200_000))
    }

    private static func firstTitle(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^#\s+(.+)$"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let titleRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[titleRange]).trimmingCharacters(in: .whitespaces)
    }
}
