import Foundation
import SQLite3

enum SessionRecordKind: String, Codable, Sendable, Hashable {
    case conversation
    case workspaceSummary
}

struct SessionRecord: Codable, Sendable, Hashable {
    let tool: String
    let id: String
    let cwd: String?
    let startedAt: Date?
    let modified: Date
    var lastUser: String?
    var kind: SessionRecordKind = .conversation
    var model: String? = nil
    var usage: TokenUsage? = nil
    var costUSD: Double? = nil
    var costIsEstimate: Bool? = nil

    var stableID: String { "\(tool):\(id)" }

    var isWorkspaceSummary: Bool { kind == .workspaceSummary }

    var resumeCommand: String? {
        guard kind == .conversation else { return nil }
        switch tool {
        case "codex": return "codex resume \(id)"
        case "claude": return "claude --resume \(id)"
        case "grok": return "grok -r \(id)"
        case "gemini": return "gemini --resume \(id)"
        default: return nil
        }
    }

    func withLastUserFallback(_ value: String?) -> SessionRecord {
        guard lastUser == nil, let value else { return self }
        var copy = self
        copy.lastUser = value
        return copy
    }
}

private struct SessionCacheEntry: Codable {
    let mtime: TimeInterval
    let fileSize: Int64
    let record: SessionRecord?
}

private struct SessionCachePayload: Codable {
    let version: Int
    let entries: [String: SessionCacheEntry]
}

enum SessionIndex {
    private static let scanBytes = 8 * 1024 * 1024
    private static let cacheVersion = 3
    private static let maxIDEWorkspaces = 300
    private static let ideCachePrefix = "ide:"

    static func build(
        homeDirectory: URL = AppPaths.home,
        cacheFile: URL? = AppPaths.sessionCacheFile
    ) -> [SessionRecord] {
        let cache = loadCache(from: cacheFile)
        var nextCache: [String: SessionCacheEntry] = [:]
        var records: [SessionRecord] = []
        var changed = false

        let codexRoot = homeDirectory.appendingPathComponent(".codex/sessions")
        let claudeRoot = homeDirectory.appendingPathComponent(".claude/projects")
        let grokRoot = homeDirectory.appendingPathComponent(".grok/sessions")

        for file in walk(codexRoot, maxDepth: 6, filter: { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }) {
            let key = PathTools.normalize(file.path)
            let stamp = fileStamp(file)
            if let stamp,
               let cached = cache[key],
               abs(cached.mtime - stamp.mtime) < 0.001,
               cached.fileSize == stamp.fileSize {
                nextCache[key] = cached
                if let record = cached.record { records.append(record) }
                continue
            }
            let record = parseCodex(file)
            if let record { records.append(record) }
            if let stamp {
                nextCache[key] = SessionCacheEntry(mtime: stamp.mtime, fileSize: stamp.fileSize, record: record)
                changed = true
            }
        }

        for directory in FileTools.childDirectories(of: claudeRoot) {
            for file in walk(directory, maxDepth: 6, filter: { $0.hasSuffix(".jsonl") }) {
                let key = PathTools.normalize(file.path)
                let stamp = fileStamp(file)
                if let stamp,
                   let cached = cache[key],
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    nextCache[key] = cached
                    if let record = cached.record { records.append(record) }
                    continue
                }
                let record = parseClaude(file, directoryName: directory.lastPathComponent)
                if let record { records.append(record) }
                if let stamp {
                    nextCache[key] = SessionCacheEntry(mtime: stamp.mtime, fileSize: stamp.fileSize, record: record)
                    changed = true
                }
            }
        }

        for cwdDirectory in FileTools.childDirectories(of: grokRoot) {
            for sessionDirectory in FileTools.childDirectories(of: cwdDirectory) {
                let chat = sessionDirectory.appendingPathComponent("chat_history.jsonl")
                guard FileTools.exists(chat) else { continue }
                let files = [
                    chat,
                    sessionDirectory.appendingPathComponent("updates.jsonl"),
                    sessionDirectory.appendingPathComponent("events.jsonl"),
                ]
                let key = PathTools.normalize(chat.path)
                let stamp = bundleStamp(files)
                if let stamp,
                   let cached = cache[key],
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    nextCache[key] = cached
                    if let record = cached.record { records.append(record) }
                    continue
                }
                let record = parseGrok(
                    sessionDirectory: sessionDirectory,
                    encodedCwd: cwdDirectory.lastPathComponent
                )
                if let record { records.append(record) }
                if let stamp {
                    nextCache[key] = SessionCacheEntry(mtime: stamp.mtime, fileSize: stamp.fileSize, record: record)
                    changed = true
                }
            }
        }

        let geminiProjects = geminiProjectsMap(homeDirectory: homeDirectory)
        let geminiRoots = geminiProjectRoots(homeDirectory: homeDirectory)
        for projectRoot in geminiRoots {
            let chats = projectRoot.appendingPathComponent("chats", isDirectory: true)
            for file in walk(chats, maxDepth: 2, filter: { URL(fileURLWithPath: $0).pathExtension == "jsonl" }) {
                let key = PathTools.normalize(file.path)
                let stamp = fileStamp(file)
                if let stamp,
                   let cached = cache[key],
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    nextCache[key] = cached
                    if let record = cached.record { records.append(record) }
                    continue
                }
                let record = parseGemini(
                    file,
                    projectRoot: projectRoot,
                    projects: geminiProjects
                )
                if let record { records.append(record) }
                if let stamp {
                    nextCache[key] = SessionCacheEntry(mtime: stamp.mtime, fileSize: stamp.fileSize, record: record)
                    changed = true
                }
            }
        }

        let ideResult = ideWorkspaceRecords(
            homeDirectory: homeDirectory,
            cache: cache,
            readDatabase: true
        )
        records.append(contentsOf: ideResult.records)
        changed = changed || ideResult.changed
        nextCache.merge(ideResult.cacheEntries) { _, new in new }

        if nextCache.count != cache.count {
            changed = true
        }
        if changed, let cacheFile {
            saveCache(nextCache, to: cacheFile)
        }

        return records.sorted { $0.modified > $1.modified }
    }

    static func buildLightweightCwdMap(
        homeDirectory: URL = AppPaths.home,
        cacheFile: URL? = AppPaths.sessionCacheFile
    ) -> [String: Set<String>] {
        let cache = loadCache(from: cacheFile)
        var map: [String: Set<String>] = [:]

        let codexRoot = homeDirectory.appendingPathComponent(".codex/sessions")
        for file in walk(codexRoot, maxDepth: 6, filter: { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }) {
            let key = PathTools.normalize(file.path)
            if let stamp = fileStamp(file),
               let cached = cache[key],
               abs(cached.mtime - stamp.mtime) < 0.001,
               cached.fileSize == stamp.fileSize {
                if let cwd = cached.record?.cwd {
                    map["codex", default: []].insert(PathTools.canonical(cwd))
                }
                continue
            }
            if let cwd = lightweightCodexCwd(in: file) {
                map["codex", default: []].insert(PathTools.canonical(cwd))
            }
        }

        let claudeRoot = homeDirectory.appendingPathComponent(".claude/projects")
        for directory in FileTools.childDirectories(of: claudeRoot) {
            for file in walk(directory, maxDepth: 6, filter: { $0.hasSuffix(".jsonl") }) {
                let key = PathTools.normalize(file.path)
                if let stamp = fileStamp(file),
                   let cached = cache[key],
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    if let cwd = cached.record?.cwd {
                        map["claude", default: []].insert(PathTools.canonical(cwd))
                    }
                    continue
                }
                if let cwd = lightweightClaudeCwd(in: file, directoryName: directory.lastPathComponent) {
                    map["claude", default: []].insert(PathTools.canonical(cwd))
                }
            }
        }

        let grokRoot = homeDirectory.appendingPathComponent(".grok/sessions")
        for cwdDirectory in FileTools.childDirectories(of: grokRoot) {
            guard let cwd = decodedGrokCwd(cwdDirectory.lastPathComponent) else { continue }
            map["grok", default: []].insert(PathTools.canonical(cwd))
        }

        let geminiProjects = geminiProjectsMap(homeDirectory: homeDirectory)
        var geminiCwds = Set<String>()
        for projectRoot in geminiProjectRoots(homeDirectory: homeDirectory) {
            let slug = projectRoot.lastPathComponent
            let chats = projectRoot.appendingPathComponent("chats", isDirectory: true)
            for file in walk(chats, maxDepth: 2, filter: { URL(fileURLWithPath: $0).pathExtension == "jsonl" }) {
                let key = PathTools.normalize(file.path)
                if let stamp = fileStamp(file),
                   let cached = cache[key],
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    if let cwd = cached.record?.cwd {
                        geminiCwds.insert(PathTools.canonical(cwd))
                    }
                    continue
                }
                if let cwd = lightweightGeminiCwd(
                    in: file,
                    slug: slug,
                    projectRoot: projectRoot,
                    projects: geminiProjects
                ) {
                    geminiCwds.insert(PathTools.canonical(cwd))
                }
            }
            let cwd = FileTools.readFileIfExists(
                projectRoot.appendingPathComponent(".project_root"),
                maxBytes: 4 * 1024
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cwd.isEmpty {
                geminiCwds.insert(PathTools.canonical(cwd))
            }
        }
        if !geminiCwds.isEmpty {
            map["gemini"] = geminiCwds
        }

        for record in ideWorkspaceRecords(
            homeDirectory: homeDirectory,
            cache: cache,
            readDatabase: false
        ).records {
            guard let cwd = record.cwd else { continue }
            map[record.tool, default: []].insert(PathTools.canonical(cwd))
        }

        return map
    }

    static func summary(for directory: URL, in index: [SessionRecord]) -> SessionSummary {
        let targetNormalized = PathTools.normalize(directory.path)
        let targetCanonical = PathTools.canonical(directory.path)
        let hits = index
            .filter { record in
                guard let cwd = record.cwd else { return false }
                return PathTools.normalize(cwd) == targetNormalized
                    || PathTools.canonical(cwd) == targetCanonical
            }
            .sorted {
                if $0.modified == $1.modified {
                    return $0.stableID < $1.stableID
                }
                return $0.modified > $1.modified
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
            byTool: byTool,
            recentSessions: hits
        )
    }

    private static func fileStamp(_ url: URL) -> (mtime: TimeInterval, fileSize: Int64)? {
        guard let attributes = try? FileTools.manager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return (modified.timeIntervalSince1970, size.int64Value)
    }

    private static func bundleStamp(_ urls: [URL]) -> (mtime: TimeInterval, fileSize: Int64)? {
        let stamps = urls.compactMap(fileStamp)
        guard !stamps.isEmpty else { return nil }
        return (
            stamps.map(\.mtime).max() ?? 0,
            stamps.map(\.fileSize).reduce(0, +)
        )
    }

    private static func loadCache(from url: URL?) -> [String: SessionCacheEntry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        guard let payload = try? JSONDecoder().decode(SessionCachePayload.self, from: data),
              payload.version == cacheVersion
        else { return [:] }
        return payload.entries
    }

    private static func saveCache(_ cache: [String: SessionCacheEntry], to url: URL) {
        try? FileTools.manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = SessionCachePayload(version: cacheVersion, entries: cache)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func lightweightCodexCwd(in file: URL) -> String? {
        let head = FileTools.head(file, bytes: 4 * 1024)
        guard let firstLine = head.split(separator: "\n").first,
              let data = String(firstLine).data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = meta["payload"] as? [String: Any]
        else { return nil }
        return payload["cwd"] as? String
    }

    private static func lightweightClaudeCwd(in file: URL, directoryName: String) -> String? {
        let head = FileTools.head(file, bytes: 16 * 1024)
        for line in head.split(separator: "\n").prefix(20) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cwd = object["cwd"] as? String
            else { continue }
            return cwd
        }
        return directoryName.hasPrefix("-")
            ? directoryName.replacingOccurrences(of: "-", with: "/")
            : nil
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
        let lastUser = codexLastUserMessage(in: file)
        let info = codexUsageInfo(in: file)
        let cost = PricingCatalog.estimate(model: info.model, usage: info.usage)

        return SessionRecord(
            tool: "codex",
            id: id,
            cwd: cwd,
            startedAt: startedAt,
            modified: modified,
            lastUser: lastUser,
            model: info.model,
            usage: info.usage,
            costUSD: cost,
            costIsEstimate: cost == nil ? nil : true
        )
    }

    private static func parseClaude(_ file: URL, directoryName: String) -> SessionRecord? {
        guard let modified = FileTools.modificationDate(file) else { return nil }
        var cwd: String?
        var lastUser: String?

        FileTools.scanLinesFromEnd(in: file, maxBytes: scanBytes) { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            if cwd == nil, let value = object["cwd"] as? String { cwd = value }
            if lastUser == nil,
               object["type"] as? String == "user",
               let message = object["message"] as? [String: Any],
               message["role"] as? String == "user" {
                let cleaned = cleanUserText(text(from: message["content"]))
                if !cleaned.isEmpty { lastUser = cleaned }
            }
            return cwd != nil && lastUser != nil
        }

        let fallbackCwd = directoryName.hasPrefix("-")
            ? directoryName.replacingOccurrences(of: "-", with: "/")
            : nil
        let info = claudeUsageInfo(in: file)
        let cost = info.cost ?? PricingCatalog.estimate(model: info.model, usage: info.usage)
        return SessionRecord(
            tool: "claude",
            id: file.deletingPathExtension().lastPathComponent,
            cwd: cwd ?? fallbackCwd,
            startedAt: nil,
            modified: modified,
            lastUser: lastUser,
            model: info.model,
            usage: info.usage,
            costUSD: cost,
            costIsEstimate: cost == nil ? nil : info.cost == nil
        )
    }

    private static func parseGrok(
        sessionDirectory: URL,
        encodedCwd: String
    ) -> SessionRecord? {
        let chat = sessionDirectory.appendingPathComponent("chat_history.jsonl")
        guard let cwd = decodedGrokCwd(encodedCwd),
              let modified = [chat,
                              sessionDirectory.appendingPathComponent("updates.jsonl"),
                              sessionDirectory.appendingPathComponent("events.jsonl")]
                .compactMap(FileTools.modificationDate)
                .max()
        else { return nil }

        let info = grokUsageInfo(
            updates: sessionDirectory.appendingPathComponent("updates.jsonl"),
            events: sessionDirectory.appendingPathComponent("events.jsonl")
        )
        let cost = PricingCatalog.estimate(model: info.model, usage: info.usage)
        return SessionRecord(
            tool: "grok",
            id: sessionDirectory.lastPathComponent,
            cwd: cwd,
            startedAt: nil,
            modified: modified,
            lastUser: grokLastUserMessage(in: chat),
            model: info.model,
            usage: info.usage,
            costUSD: cost,
            costIsEstimate: cost == nil ? nil : true
        )
    }

    private static func geminiProjectRoots(homeDirectory: URL) -> [URL] {
        FileTools.childDirectories(
            of: homeDirectory.appendingPathComponent(".gemini/tmp", isDirectory: true)
        )
    }

    private static func geminiProjectsMap(homeDirectory: URL) -> [String: String] {
        let projectsFile = homeDirectory.appendingPathComponent(".gemini/projects.json")
        guard let json = FileTools.json(projectsFile),
              let projects = json["projects"] as? [String: String]
        else { return [:] }
        return projects
    }

    private static func geminiProjectPath(
        slug: String,
        projectRoot: URL,
        projects: [String: String]
    ) -> String? {
        if let mount = projects.first(where: { $0.value == slug })?.key,
           mount.hasPrefix("/") {
            return mount
        }
        let rootFile = projectRoot.appendingPathComponent(".project_root")
        let root = FileTools.readFileIfExists(rootFile, maxBytes: 4 * 1024)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return root.hasPrefix("/") ? root : nil
    }

    private static func parseGemini(
        _ file: URL,
        projectRoot: URL,
        projects: [String: String]
    ) -> SessionRecord? {
        guard let modified = FileTools.modificationDate(file) else { return nil }
        let cwd = geminiProjectPath(
            slug: projectRoot.lastPathComponent,
            projectRoot: projectRoot,
            projects: projects
        )

        let head = FileTools.head(file, bytes: 32 * 1024)
        guard let firstLine = head.split(separator: "\n").first,
              let data = String(firstLine).data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let id = (meta["sessionId"] as? String)
            ?? file.deletingPathExtension().lastPathComponent
        let startedAt = ((meta["startTime"] as? String) ?? (meta["lastUpdated"] as? String))
            .flatMap(Format.isoDate)
        let info = geminiUsageInfo(in: file)

        return SessionRecord(
            tool: "gemini",
            id: id,
            cwd: cwd ?? (meta["directories"] as? [String])?.first,
            startedAt: startedAt,
            modified: modified,
            lastUser: geminiLastUserMessage(in: file)
                ?? (meta["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            model: info.model,
            usage: info.usage
        )
    }

    private static func lightweightGeminiCwd(
        in file: URL,
        slug: String,
        projectRoot: URL,
        projects: [String: String]
    ) -> String? {
        if let cwd = geminiProjectPath(
            slug: slug,
            projectRoot: projectRoot,
            projects: projects
        ) {
            return cwd
        }
        let head = FileTools.head(file, bytes: 16 * 1024)
        guard let firstLine = head.split(separator: "\n").first,
              let data = String(firstLine).data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (meta["directories"] as? [String])?.first
    }

    private static func geminiLastUserMessage(in file: URL) -> String? {
        var lastUser: String?
        FileTools.scanLinesFromEnd(in: file, maxBytes: scanBytes) { line in
            guard line.contains("\"user\""),
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "user"
            else { return false }
            let text = cleanUserText(text(from: object["content"]))
            guard !text.isEmpty,
                  !text.hasPrefix("<"),
                  !text.hasPrefix("/")
            else { return false }
            lastUser = text
            return true
        }
        return lastUser
    }

    private static func geminiUsageInfo(in file: URL) -> (model: String?, usage: TokenUsage?) {
        var model: String?
        var usage: TokenUsage?
        FileTools.scanLinesFromEnd(in: file, maxBytes: 2 * 1024 * 1024) { line in
            guard line.contains("\"tokens\""),
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = object["tokens"] as? [String: Any]
            else { return false }

            let input = int(tokens["input"])
            let output = int(tokens["output"])
            let total = int(tokens["total"])
            if total > 0 || input + output > 0 {
                usage = TokenUsage(
                    inputTokens: input,
                    cachedInputTokens: int(tokens["cached"]),
                    outputTokens: output,
                    reasoningOutputTokens: int(tokens["thoughts"]),
                    totalTokens: total > 0 ? total : input + output
                )
            }
            model = object["model"] as? String ?? model
            return usage != nil && model != nil
        }
        return (model, usage)
    }

    private struct IDEWorkspace {
        let tool: String
        let directory: URL
        let databaseName: String
    }

    private static func ideWorkspaceRecords(
        homeDirectory: URL,
        cache: [String: SessionCacheEntry],
        readDatabase: Bool
    ) -> (records: [SessionRecord], cacheEntries: [String: SessionCacheEntry], changed: Bool) {
        var records: [SessionRecord] = []
        var cacheEntries: [String: SessionCacheEntry] = [:]
        var changed = false
        let appSupport = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let applications = [
            ("cursor", "Cursor/User/workspaceStorage", "state.vscdb"),
            ("trae", "Trae/User/workspaceStorage", "state.vscdb"),
            ("windsurf", "Windsurf/User/workspaceStorage", "state.vscdb"),
        ]

        for (tool, relativePath, databaseName) in applications {
            let storageRoot = appSupport.appendingPathComponent(relativePath, isDirectory: true)
            for directory in FileTools.childDirectories(of: storageRoot).prefix(maxIDEWorkspaces) {
                let workspace = IDEWorkspace(
                    tool: tool,
                    directory: directory,
                    databaseName: databaseName
                )
                let files = [
                    directory.appendingPathComponent("workspace.json"),
                    directory.appendingPathComponent(databaseName),
                    directory.appendingPathComponent("\(databaseName)-wal"),
                ]
                guard let stamp = bundleStamp(files) else { continue }
                let key = "\(ideCachePrefix)\(tool):\(directory.lastPathComponent)"
                let entry: SessionCacheEntry
                if let cached = cache[key],
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    entry = cached
                } else {
                    entry = SessionCacheEntry(
                        mtime: stamp.mtime,
                        fileSize: stamp.fileSize,
                        record: parseIDEWorkspace(workspace, readDatabase: readDatabase)
                    )
                    changed = true
                }
                cacheEntries[key] = entry
                if let record = entry.record {
                    records.append(record)
                }
            }
        }
        return (records, cacheEntries, changed)
    }

    private static func parseIDEWorkspace(_ workspace: IDEWorkspace, readDatabase: Bool) -> SessionRecord? {
        let workspaceFile = workspace.directory.appendingPathComponent("workspace.json")
        guard let json = FileTools.json(workspaceFile),
              let folder = json["folder"] as? String,
              let url = URL(string: folder),
              url.isFileURL,
              !url.path.isEmpty
        else { return nil }

        let files = [
            workspaceFile,
            workspace.directory.appendingPathComponent(workspace.databaseName),
            workspace.directory.appendingPathComponent("\(workspace.databaseName)-wal"),
        ]
        guard let modified = files.compactMap(FileTools.modificationDate).max() else { return nil }
        let title = DetectedTool(rawValue: workspace.tool)?.title ?? workspace.tool.capitalized
        let lastUser = readDatabase
            ? lastUserMessage(inDatabase: workspace.directory.appendingPathComponent(workspace.databaseName))
            : nil

        return SessionRecord(
            tool: workspace.tool,
            id: workspace.directory.lastPathComponent,
            cwd: url.path,
            startedAt: nil,
            modified: modified,
            lastUser: lastUser,
            kind: .workspaceSummary
        ).withLastUserFallback("\(title) 工作区活动")
    }

    private static func lastUserMessage(inDatabase url: URL) -> String? {
        guard FileTools.exists(url) else { return nil }

        for key in ["workbench.panel.aichat.view.aichat.chatdata", "composer.composerData"] {
            if let value = readItemValue(inDatabase: url, key: key),
               let title = ideChatTitle(from: value) {
                return title
            }
        }
        return nil
    }

    private static func readItemValue(inDatabase url: URL, key: String) -> String? {
        var statement: OpaquePointer?
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK,
            let database
        else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 120)
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
            let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        key.withCString { pointer in
            _ = sqlite3_bind_text(statement, 1, pointer, -1, transient)
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: raw)
    }

    private static func ideChatTitle(from value: String) -> String? {
        if let title = composerTitle(from: value) {
            return title
        }
        guard value.count < 256 * 1024,
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabs = object["tabs"] as? [[String: Any]]
        else { return nil }
        if let message = tabs
            .flatMap({ ($0["bubbles"] as? [[String: Any]]) ?? [] })
            .filter({ ($0["type"] as? NSNumber)?.intValue == 1 })
            .compactMap({ $0["text"] as? String })
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .last {
            return String(message.prefix(400))
        }
        return tabs
            .compactMap { $0["chatTitle"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(400)) }
    }

    private static func composerTitle(from value: String) -> String? {
        guard value.contains("allComposers"),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let composers = object["allComposers"] as? [[String: Any]]
        else { return nil }
        return composers
            .compactMap { ($0["name"] as? String) ?? ($0["text"] as? String) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(400)) }
    }

    private static func codexUsageInfo(in file: URL) -> (model: String?, usage: TokenUsage?) {
        var model: String?
        var usage: TokenUsage?
        FileTools.scanLinesFromEnd(in: file, maxBytes: 2 * 1024 * 1024) { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            guard let payload = object["payload"] as? [String: Any] else { return false }

            if usage == nil,
               payload["type"] as? String == "token_count",
               let info = payload["info"] as? [String: Any],
               let total = info["total_token_usage"] as? [String: Any] {
                let input = int(total["input_tokens"])
                let output = int(total["output_tokens"])
                usage = TokenUsage(
                    inputTokens: input,
                    cachedInputTokens: int(total["cached_input_tokens"]),
                    cacheWriteInputTokens: int(total["cache_write_input_tokens"]),
                    outputTokens: output,
                    reasoningOutputTokens: int(total["reasoning_output_tokens"]),
                    totalTokens: int(total["total_tokens"]) == 0 ? input + output : int(total["total_tokens"])
                )
            }
            if model == nil,
               object["type"] as? String == "turn_context" {
                model = payload["model"] as? String
            }
            return usage != nil && model != nil
        }
        return (model, usage)
    }

    private static func claudeUsageInfo(
        in file: URL
    ) -> (model: String?, usage: TokenUsage?, cost: Double?) {
        var cost: Double?
        var model: String?
        var usage: TokenUsage?
        var messageUsage: TokenUsage?
        var messageModel: String?

        FileTools.scanLinesFromEnd(in: file, maxBytes: 2 * 1024 * 1024) { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }

            if cost == nil, object["type"] as? String == "cost-state" {
                if object["hasUnknownModelCost"] as? Bool != true,
                   let total = (object["totalCostUSD"] as? NSNumber)?.doubleValue,
                   total > 0 {
                    cost = total
                }
                if let models = object["modelUsage"] as? [String: Any] {
                    var aggregate = TokenUsage.zero
                    for (name, raw) in models {
                        guard let values = raw as? [String: Any] else { continue }
                        if model == nil { model = name }
                        aggregate.inputTokens += int(values["inputTokens"])
                        aggregate.outputTokens += int(values["outputTokens"])
                        aggregate.reasoningOutputTokens += int(values["thinkingTokens"])
                        aggregate.cachedInputTokens += int(values["cacheReadInputTokens"])
                        aggregate.cacheWriteInputTokens += int(values["cacheCreationInputTokens"])
                    }
                    aggregate.totalTokens = aggregate.inputTokens
                        + aggregate.outputTokens
                        + aggregate.cachedInputTokens
                        + aggregate.cacheWriteInputTokens
                    usage = aggregate
                }
            }

            if messageUsage == nil,
               let message = object["message"] as? [String: Any],
               let values = message["usage"] as? [String: Any] {
                let input = int(values["input_tokens"])
                let output = int(values["output_tokens"])
                let cacheRead = int(values["cache_read_input_tokens"])
                let cacheWrite = int(values["cache_creation_input_tokens"])
                messageUsage = TokenUsage(
                    inputTokens: input,
                    cachedInputTokens: cacheRead,
                    cacheWriteInputTokens: cacheWrite,
                    outputTokens: output,
                    reasoningOutputTokens: int((values["output_tokens_details"] as? [String: Any])?["thinking_tokens"]),
                    totalTokens: input + output + cacheRead + cacheWrite
                )
                messageModel = message["model"] as? String
            }

            return cost != nil && usage != nil
        }

        if cost != nil {
            return (model, usage, cost)
        }
        if let messageUsage {
            return (messageModel, messageUsage, nil)
        }
        return (nil, nil, nil)
    }

    private static func grokUsageInfo(
        updates: URL,
        events: URL
    ) -> (model: String?, usage: TokenUsage?) {
        var totalTokens = 0
        var model: String?

        if FileTools.exists(updates) {
            FileTools.scanLinesFromEnd(in: updates, maxBytes: 2 * 1024 * 1024) { line in
                guard line.contains("totalTokens"),
                      let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let params = object["params"] as? [String: Any],
                      let meta = params["_meta"] as? [String: Any]
                else { return false }
                totalTokens = int(meta["totalTokens"])
                return totalTokens > 0
            }
        }

        if FileTools.exists(events) {
            FileTools.scanLinesFromEnd(in: events, maxBytes: 512 * 1024) { line in
                guard line.contains("model_id"),
                      let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                model = object["model_id"] as? String
                return model != nil
            }
        }

        let usage = totalTokens > 0 ? TokenUsage(totalTokens: totalTokens) : nil
        return (model, usage)
    }

    private static func grokLastUserMessage(in file: URL) -> String? {
        var lastUser: String?
        FileTools.scanLinesFromEnd(in: file, maxBytes: scanBytes) { line in
            guard line.contains("\"user\""),
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "user"
            else { return false }
            let text = cleanUserText(text(from: object["content"]))
            guard !text.isEmpty, !text.hasPrefix("<") else { return false }
            lastUser = text
            return true
        }
        return lastUser
    }

    private static func decodedGrokCwd(_ encoded: String) -> String? {
        guard let decoded = encoded.removingPercentEncoding,
              decoded.hasPrefix("/")
        else { return nil }
        return decoded
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func codexLastUserMessage(in file: URL) -> String? {
        var lastUser: String?
        FileTools.scanLinesFromEnd(in: file, maxBytes: scanBytes) { line in
            guard let message = codexUserMessage(in: line) else { return false }
            lastUser = message
            return true
        }
        return lastUser
    }

    private static func codexUserMessage(in line: String) -> String? {
        guard line.contains("\"UserMessage\"") || line.contains("\"user\"") else {
            return nil
        }
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return nil }

        let content: Any?
        if object["type"] as? String == "event_msg",
           payload["type"] as? String == "item_completed",
           let item = payload["item"] as? [String: Any],
           item["type"] as? String == "UserMessage" {
            content = item["content"]
        } else if object["type"] as? String != "event_msg",
                  payload["role"] as? String == "user" {
            content = payload["content"]
        } else {
            return nil
        }

        let text = cleanUserText(text(from: content))
        guard !text.isEmpty, !text.hasPrefix("<") else { return nil }
        return text
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
