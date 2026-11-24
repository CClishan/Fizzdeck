import Foundation

struct SessionRecord: Sendable {
    let tool: String
    let id: String
    let cwd: String?
    let startedAt: Date?
    let modified: Date
    let lastUser: String?
}

enum SessionIndex {
    private static let tailBytes = 256 * 1024

    static func build() -> [SessionRecord] {
        var records: [SessionRecord] = []
        let codexRoot = AppPaths.home.appendingPathComponent(".codex/sessions")
        let claudeRoot = AppPaths.home.appendingPathComponent(".claude/projects")

        for file in walk(codexRoot, maxDepth: 6, filter: { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }) {
            if let record = parseCodex(file) { records.append(record) }
        }

        for directory in FileTools.childDirectories(of: claudeRoot) {
            for file in walk(directory, maxDepth: 6, filter: { $0.hasSuffix(".jsonl") }) {
                if let record = parseClaude(file, directoryName: directory.lastPathComponent) {
                    records.append(record)
                }
            }
        }

        return records.sorted { $0.modified > $1.modified }
    }

    static func summary(for directory: URL, in index: [SessionRecord]) -> SessionSummary {
        let target = PathTools.normalize(directory.path)
        let hits = index.filter { record in
            guard let cwd = record.cwd else { return false }
            return PathTools.normalize(cwd) == target
        }

        var byTool: [ToolSession] = []
        for hit in hits {
            if let existing = byTool.first(where: { $0.tool == hit.tool }) {
                if let index = byTool.firstIndex(where: { $0.tool == existing.tool }) {
                    byTool[index] = ToolSession(
                        tool: hit.tool,
                        sessionCount: byTool[index].sessionCount + 1,
                        lastSessionAt: byTool[index].lastSessionAt,
                        lastSessionID: byTool[index].lastSessionID,
                        lastUserMessage: byTool[index].lastUserMessage
                    )
                }
            } else {
                byTool.append(ToolSession(
                    tool: hit.tool,
                    sessionCount: 1,
                    lastSessionAt: hit.modified,
                    lastSessionID: hit.id,
                    lastUserMessage: hit.lastUser
                ))
            }
        }
        byTool.sort { ($0.lastSessionAt ?? .distantPast) > ($1.lastSessionAt ?? .distantPast) }
        let latest = byTool.first
        return SessionSummary(
            detected: byTool.map(\.tool),
            lastSessionAt: latest?.lastSessionAt,
            lastUserMessage: latest?.lastUserMessage,
            lastSessionID: latest?.lastSessionID,
            lastTool: latest?.tool,
            sessionCount: hits.count,
            byTool: byTool
        )
    }

    private static func walk(_ root: URL, maxDepth: Int, filter: (String) -> Bool) -> [URL] {
        var files: [URL] = []
        func visit(_ directory: URL, depth: Int) {
            guard depth <= maxDepth,
                  let contents = try? FileTools.manager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                  )
            else { return }
            for child in contents {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    visit(child, depth: depth + 1)
                } else if filter(child.lastPathComponent) {
                    files.append(child)
                }
            }
        }
        visit(root, depth: 0)
        return files
    }

    private static func parseCodex(_ file: URL) -> SessionRecord? {
        guard let modified = FileTools.modificationDate(file) else { return nil }
        let head = FileTools.head(file, bytes: 32 * 1024)
        guard let firstLine = head.split(separator: "\n").first,
              let data = String(firstLine).data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = meta["payload"] as? [String: Any],
              let cwd = payload["cwd"] as? String
        else { return nil }

        let id = (payload["session_id"] as? String)
            ?? (payload["id"] as? String)
            ?? file.deletingPathExtension().lastPathComponent
        let startedAt = (meta["timestamp"] as? String).flatMap(Format.isoDate)
        let lastUser = lastUserMessage(in: FileTools.tail(file, bytes: tailBytes)) { object in
            guard (object["type"] as? String) != "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["role"] as? String == "user"
            else { return nil }
            return payload["content"]
        }

        return SessionRecord(
            tool: "codex",
            id: id,
            cwd: cwd,
            startedAt: startedAt,
            modified: modified,
            lastUser: lastUser
        )
    }

    private static func parseClaude(_ file: URL, directoryName: String) -> SessionRecord? {
        guard let modified = FileTools.modificationDate(file) else { return nil }
        let tail = FileTools.tail(file, bytes: tailBytes)
        var cwd: String?
        var lastUser: String?

        for line in tail.split(separator: "\n").reversed() where !line.isEmpty {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if cwd == nil, let value = object["cwd"] as? String { cwd = value }
            if lastUser == nil,
               object["type"] as? String == "user",
               let message = object["message"] as? [String: Any],
               message["role"] as? String == "user" {
                let cleaned = cleanUserText(text(from: message["content"]))
                if !cleaned.isEmpty { lastUser = cleaned }
            }
            if cwd != nil && lastUser != nil { break }
        }

        let fallbackCwd = directoryName.hasPrefix("-")
            ? directoryName.replacingOccurrences(of: "-", with: "/")
            : nil
        return SessionRecord(
            tool: "claude",
            id: file.deletingPathExtension().lastPathComponent,
            cwd: cwd ?? fallbackCwd,
            startedAt: nil,
            modified: modified,
            lastUser: lastUser
        )
    }

    private static func lastUserMessage(
        in tail: String,
        extract: ([String: Any]) -> Any?
    ) -> String? {
        for line in tail.split(separator: "\n").reversed() where line.contains("\"user\"") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = extract(object)
            else { continue }
            let text = cleanUserText(text(from: content))
            if !text.isEmpty && !text.hasPrefix("<") { return text }
        }
        return nil
    }

    private static func text(from content: Any?) -> String {
        if let value = content as? String { return value }
        if let items = content as? [[String: Any]] {
            return items.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        if let item = content as? [String: Any], let value = item["text"] as? String {
            return value
        }
        return ""
    }

    private static func cleanUserText(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(
            of: #"(?s)<environment_context>.*?</environment_context>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?s)<user_instructions>.*?</user_instructions>"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ignoredPrefixes = [
            "[Request interrupted",
            "[Tool use interrupted",
            "[Request cancelled",
        ]
        if ignoredPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return ""
        }
        return String(trimmed.prefix(400))
    }
}
