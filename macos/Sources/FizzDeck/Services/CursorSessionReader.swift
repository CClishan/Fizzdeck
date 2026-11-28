import Foundation

enum CursorSessionReader {
    static let projectsPath = ".cursor/projects"
    static let workspacesPath = "Library/Application Support/Cursor/User/workspaceStorage"
    private static let maxScanBytes = 4 * 1024 * 1024
    private static let editTools: Set<String> = ["Write", "Edit", "StrReplace", "MultiEdit", "Delete"]

    struct Source {
        let url: URL
        let id: String
        let cwd: String
    }

    static func sources(in homeDirectory: URL) -> [Source] {
        transcriptDirectories(in: homeDirectory).flatMap { directory, cwd in
            entries(in: directory).compactMap { item in
                let id = item.pathExtension == "jsonl" ? item.deletingPathExtension().lastPathComponent : item.lastPathComponent
                guard let uuid = UUID(uuidString: id) else { return nil }
                let file = item.pathExtension == "jsonl" ? item : item.appendingPathComponent("\(id).jsonl")
                guard (file == item || kind(item, .isDirectoryKey)), kind(file, .isRegularFileKey) else { return nil }
                return Source(url: file, id: uuid.uuidString.lowercased(), cwd: cwd)
            }
        }
    }

    static func workspaceCwds(in homeDirectory: URL) -> Set<String> {
        Set(transcriptDirectories(in: homeDirectory).map(\.1))
    }

    static func parse(_ source: Source, modified: Date, fileSize: Int64) -> SessionRecord? {
        var firstUser: String?
        var lastUser: String?
        var touchedFiles: [String] = []
        var seenFiles = Set<String>()
        var lastError: String?
        var endedWithError = false
        var turns = 0

        FileTools.scanLines(in: source.url, maxBytes: maxScanBytes) { line in
            guard let row = json(line) else { return false }
            if row["type"] as? String == "turn_ended" {
                switch row["status"] as? String {
                case "success": endedWithError = false
                case "error", "failed":
                    endedWithError = true
                    let error = row["error"] as? String ?? (row["error"] as? [String: Any])?["message"] as? String
                    if let error, let cleanError = clean(error, limit: 240) { lastError = cleanError }
                default: break
                }
                return false
            }
            guard let role = row["role"] as? String,
                  let message = row["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return false }
            if role == "user" {
                guard let prompt = userPrompt(content) else { return false }
                if firstUser == nil { firstUser = prompt }
                lastUser = prompt
                turns += 1
                endedWithError = false
            } else if role == "assistant" {
                for block in content where touchedFiles.count < 40 && block["type"] as? String == "tool_use" {
                    guard let name = block["name"] as? String, editTools.contains(name),
                          let input = block["input"] as? [String: Any],
                          let raw = input["path"] as? String ?? input["file_path"] as? String,
                          let path = PathTools.projectRelativeFile(raw, in: source.cwd), seenFiles.insert(path).inserted else { continue }
                    touchedFiles.append(path)
                }
            }
            return false
        }
        guard let firstUser else { return nil }
        return SessionRecord(
            tool: "cursor", id: source.id, cwd: source.cwd, startedAt: nil, modified: modified,
            lastUser: lastUser, firstUser: firstUser, touchedFiles: touchedFiles, lastError: lastError,
            endedWithError: endedWithError, turnCount: fileSize <= maxScanBytes ? turns : nil
        )
    }

    private static func transcriptDirectories(in homeDirectory: URL) -> [(URL, String)] {
        let projectRoot = homeDirectory.appendingPathComponent(projectsPath, isDirectory: true)
        let projects = entries(in: projectRoot)
        guard !projects.isEmpty else { return [] }
        let storageRoot = homeDirectory.appendingPathComponent(workspacesPath, isDirectory: true)
        var slugPaths: [String: Set<String>] = [:]
        for workspace in entries(in: storageRoot) where kind(workspace, .isDirectoryKey) {
            guard let raw = metadata(workspace.appendingPathComponent("workspace.json"))?["folder"] as? String,
                  let path = PathTools.localFilePath(raw) else { continue }
            // Cursor's slug loses separators. Only use its own folder metadata when the match is unique.
            let canonical = PathTools.canonical(path)
            for spelling in Set([path, canonical]) {
                let separated = spelling.dropFirst().replacingOccurrences(of: "/", with: "-")
                let sanitized = spelling.split(whereSeparator: { !$0.isASCII || (!$0.isLetter && !$0.isNumber) }).joined(separator: "-")
                slugPaths[separated, default: []].insert(canonical)
                slugPaths[sanitized, default: []].insert(canonical)
            }
        }
        return projects.compactMap { project in
            guard kind(project, .isDirectoryKey) else { return nil }
            let transcripts = project.appendingPathComponent("agent-transcripts", isDirectory: true)
            guard kind(transcripts, .isDirectoryKey) else { return nil }
            let marker = project.appendingPathComponent(".workspace-trusted")
            if let raw = metadata(marker)?["workspacePath"] as? String, let path = PathTools.localFilePath(raw) {
                return (transcripts, PathTools.canonical(path))
            }
            guard let paths = slugPaths[project.lastPathComponent], paths.count == 1, let path = paths.first else { return nil }
            return (transcripts, path)
        }
    }

    private static func userPrompt(_ content: [[String: Any]]) -> String? {
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        // A tool result or harness notification is not a user turn.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if let start = trimmed.range(of: "<user_query>"), let end = trimmed.range(of: "</user_query>", range: start.upperBound..<trimmed.endIndex) {
            prompt = String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            prompt = trimmed
        }
        guard !["<system_reminder", "<system-reminder", "<subagent_notification", "<task-notification", "<usage>"].contains(where: { prompt.hasPrefix($0) }) else { return nil }
        return clean(prompt, limit: 400)
    }

    private static func clean(_ text: String, limit: Int) -> String? {
        let result = SessionSummaryText.clean(SecretRedactor.redact(text).text)
        return result.isEmpty ? nil : String(result.prefix(limit))
    }

    private static func metadata(_ file: URL) -> [String: Any]? {
        guard kind(file, .isRegularFileKey) else { return nil }
        return json(FileTools.readText(file, maxBytes: 64 * 1024))
    }

    private static func json(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func entries(in directory: URL) -> [URL] {
        guard kind(directory, .isDirectoryKey) else { return [] }
        return (try? FileTools.manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func kind(_ item: URL, _ key: URLResourceKey) -> Bool {
        guard let values = try? item.resourceValues(forKeys: [key, .isSymbolicLinkKey]), values.isSymbolicLink != true else { return false }
        return values.allValues[key] as? Bool == true
    }
}
