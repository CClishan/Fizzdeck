import Foundation
import SQLite3

enum SessionRecordKind: String, Codable, Sendable, Hashable {
    case conversation
    case workspaceSummary
}

enum SessionTestResult: String, Codable, Sendable, Hashable {
    case passed, failed, notRun
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
    var firstUser: String? = nil
    var touchedFiles: [String] = []
    var lastError: String? = nil
    var endedWithError: Bool = false
    var turnCount: Int? = nil
    var durationMinutes: Int? = nil
    var agentTimeSeconds: Int? = nil
    var testResult: SessionTestResult? = nil

    init(
        tool: String,
        id: String,
        cwd: String?,
        startedAt: Date?,
        modified: Date,
        lastUser: String? = nil,
        kind: SessionRecordKind = .conversation,
        model: String? = nil,
        usage: TokenUsage? = nil,
        costUSD: Double? = nil,
        costIsEstimate: Bool? = nil,
        firstUser: String? = nil,
        touchedFiles: [String] = [],
        lastError: String? = nil,
        endedWithError: Bool = false,
        turnCount: Int? = nil,
        durationMinutes: Int? = nil,
        agentTimeSeconds: Int? = nil,
        testResult: SessionTestResult? = nil
    ) {
        self.tool = tool
        self.id = id
        self.cwd = cwd
        self.startedAt = startedAt
        self.modified = modified
        self.lastUser = lastUser
        self.kind = kind
        self.model = model
        self.usage = usage
        self.costUSD = costUSD
        self.costIsEstimate = costIsEstimate
        self.firstUser = firstUser
        self.touchedFiles = touchedFiles
        self.lastError = lastError
        self.endedWithError = endedWithError
        self.turnCount = turnCount
        self.durationMinutes = durationMinutes
        self.agentTimeSeconds = agentTimeSeconds.flatMap { $0 > 0 ? $0 : nil }
        self.testResult = testResult
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)
        id = try container.decode(String.self, forKey: .id)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        modified = try container.decode(Date.self, forKey: .modified)
        lastUser = try container.decodeIfPresent(String.self, forKey: .lastUser)
        kind = try container.decodeIfPresent(SessionRecordKind.self, forKey: .kind) ?? .conversation
        model = try container.decodeIfPresent(String.self, forKey: .model)
        usage = try container.decodeIfPresent(TokenUsage.self, forKey: .usage)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        costIsEstimate = try container.decodeIfPresent(Bool.self, forKey: .costIsEstimate)
        firstUser = try container.decodeIfPresent(String.self, forKey: .firstUser)
        touchedFiles = try container.decodeIfPresent([String].self, forKey: .touchedFiles) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        endedWithError = try container.decodeIfPresent(Bool.self, forKey: .endedWithError) ?? false
        turnCount = try container.decodeIfPresent(Int.self, forKey: .turnCount)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        agentTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .agentTimeSeconds).flatMap { $0 > 0 ? $0 : nil }
        testResult = try container.decodeIfPresent(SessionTestResult.self, forKey: .testResult)
    }

    var stableID: String { "\(tool):\(id)" }

    var isWorkspaceSummary: Bool { kind == .workspaceSummary }

    var primaryIntent: String? {
        if let first = firstUser?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        if let last = lastUser?.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
            return last
        }
        return nil
    }

    var resumeCommand: String? {
        // The ID is a single CLI argument and, for Codex Desktop, a URL path component.
        guard kind == .conversation, id.wholeMatch(of: #/[A-Za-z0-9_][A-Za-z0-9_.:-]*/#) != nil else { return nil }
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
    var databaseRevision: Int64? = nil
    var metricsVersion: Int? = nil
}

private struct SessionCachePayload: Codable {
    let version: Int
    let entries: [String: SessionCacheEntry]
}

enum SessionIndex {
    private static let scanBytes = 8 * 1024 * 1024
    private static let cacheVersion = 5
    private static let transcriptMetricsVersion = 1
    private static let maxTouchedFiles = 40
    private static let maxErrorCharacters = 240
    private static let maxIDEWorkspaces = 300
    private static let ideCachePrefix = "ide:"
    private static let agyCachePrefix = "agy:"

    static func isInternalLLMWorkdir(
        _ cwd: String?,
        excludedCwd: URL? = AppPaths.llmWorkdir
    ) -> Bool {
        guard let cwd, let excludedCwd else { return false }
        let candidate = PathTools.canonical(cwd)
        let excluded = PathTools.canonical(excludedCwd.path)
        return candidate == excluded || candidate.hasPrefix(excluded + "/")
    }

    static func build(
        homeDirectory: URL = AppPaths.home,
        cacheFile: URL? = AppPaths.sessionCacheFile,
        excludedCwd: URL? = AppPaths.llmWorkdir
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
               cached.metricsVersion == transcriptMetricsVersion,
               abs(cached.mtime - stamp.mtime) < 0.001,
               cached.fileSize == stamp.fileSize {
                nextCache[key] = cached
                if let record = cached.record { records.append(record) }
                continue
            }
            let record = parseCodex(file)
            if let record { records.append(record) }
            if let stamp {
                nextCache[key] = SessionCacheEntry(
                    mtime: stamp.mtime, fileSize: stamp.fileSize, record: record, metricsVersion: transcriptMetricsVersion
                )
                changed = true
            }
        }

        for directory in FileTools.childDirectories(of: claudeRoot) {
            for file in walk(directory, maxDepth: 6, filter: { $0.hasSuffix(".jsonl") }) {
                let key = PathTools.normalize(file.path)
                let stamp = fileStamp(file)
                if let stamp,
                   let cached = cache[key],
                   cached.metricsVersion == transcriptMetricsVersion,
                   abs(cached.mtime - stamp.mtime) < 0.001,
                   cached.fileSize == stamp.fileSize {
                    nextCache[key] = cached
                    if let record = cached.record { records.append(record) }
                    continue
                }
                let record = parseClaude(file, directoryName: directory.lastPathComponent)
                if let record { records.append(record) }
                if let stamp {
                    nextCache[key] = SessionCacheEntry(
                        mtime: stamp.mtime, fileSize: stamp.fileSize, record: record, metricsVersion: transcriptMetricsVersion
                    )
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

        let deepseekRoot = homeDirectory.appendingPathComponent(".dsh/storages/session_projcache/sessions")
        for file in walk(deepseekRoot, maxDepth: 2, filter: { $0.hasSuffix(".json") }) {
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
            let record = parseDeepSeek(file)
            if let record { records.append(record) }
            if let stamp {
                nextCache[key] = SessionCacheEntry(mtime: stamp.mtime, fileSize: stamp.fileSize, record: record)
                changed = true
            }
        }

        let agyResult = agyRecords(homeDirectory: homeDirectory, cache: cache)
        records.append(contentsOf: agyResult.records)
        changed = changed || agyResult.changed
        nextCache.merge(agyResult.cacheEntries) { _, new in new }

        var cursorConversations: [String: SessionRecord] = [:]
        for source in CursorSessionReader.sources(in: homeDirectory).sorted(by: { $0.url.path < $1.url.path }) {
            guard let stamp = fileStamp(source.url) else { continue }
            let key = "cursor:\(source.cwd)\0\(PathTools.normalize(source.url.path))"
            let entry: SessionCacheEntry
            if let existing = cache[key], existing.mtime == stamp.mtime, existing.fileSize == stamp.fileSize {
                entry = existing
            } else {
                let record = CursorSessionReader.parse(
                    source, modified: Date(timeIntervalSince1970: stamp.mtime), fileSize: stamp.fileSize
                )
                entry = SessionCacheEntry(mtime: stamp.mtime, fileSize: stamp.fileSize, record: record)
                changed = true
            }
            nextCache[key] = entry
            if let record = entry.record,
               cursorConversations[record.id].map({ $0.modified < record.modified }) ?? true {
                cursorConversations[record.id] = record
            }
        }
        records.append(contentsOf: cursorConversations.values)

        let database = OpenCodeSessionReader.database(in: homeDirectory)
        let openCodePrefix = openCodeCachePrefix(for: database)
        let previous = cache.reduce(into: [String: OpenCodeSessionReader.Snapshot]()) { result, pair in
            guard pair.key.hasPrefix(openCodePrefix), let revision = pair.value.databaseRevision else { return }
            result[String(pair.key.dropFirst(openCodePrefix.count))] = .init(revision: revision, record: pair.value.record)
        }
        if let snapshots = OpenCodeSessionReader.read(database: database, cached: previous) {
            for (id, snapshot) in snapshots {
                nextCache[openCodePrefix + id] = SessionCacheEntry(
                    mtime: 0, fileSize: 0, record: snapshot.record, databaseRevision: snapshot.revision
                )
                if previous[id]?.revision != snapshot.revision { changed = true }
                if let record = snapshot.record { records.append(record) }
            }
        } else if OpenCodeSessionReader.sourceExists(at: database) {
            // A busy or temporarily unreadable database must not evict last known records or revisions.
            for (id, snapshot) in previous {
                let key = openCodePrefix + id
                nextCache[key] = cache[key]
                if let record = snapshot.record { records.append(record) }
            }
        }

        let cursorCwds = Set(cursorConversations.values.compactMap(\.cwd))
        let ideResult = ideWorkspaceRecords(
            homeDirectory: homeDirectory,
            cache: cache,
            readDatabase: true,
            skipCursorCwds: cursorCwds
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

        return records
            .filter { !isInternalLLMWorkdir($0.cwd, excludedCwd: excludedCwd) }
            .sorted { $0.modified > $1.modified }
    }

    static func buildLightweightCwdMap(
        homeDirectory: URL = AppPaths.home,
        cacheFile: URL? = AppPaths.sessionCacheFile,
        excludedCwd: URL? = AppPaths.llmWorkdir
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

        let deepseekRoot = homeDirectory.appendingPathComponent(".dsh/storages/session_projcache/sessions")
        for file in walk(deepseekRoot, maxDepth: 2, filter: { $0.hasSuffix(".json") }) {
            let key = PathTools.normalize(file.path)
            if let stamp = fileStamp(file),
               let cached = cache[key],
               abs(cached.mtime - stamp.mtime) < 0.001,
               cached.fileSize == stamp.fileSize {
                if let cwd = cached.record?.cwd {
                    map["deepseek", default: []].insert(PathTools.canonical(cwd))
                }
                continue
            }
            if let cwd = lightweightDeepSeekCwd(in: file) {
                map["deepseek", default: []].insert(PathTools.canonical(cwd))
            }
        }

        let agyCwds = lightweightAgyCwds(homeDirectory: homeDirectory)
        if !agyCwds.isEmpty {
            map["agy"] = agyCwds
        }

        let cursorCwds = CursorSessionReader.workspaceCwds(in: homeDirectory)
        if !cursorCwds.isEmpty { map["cursor", default: []].formUnion(cursorCwds) }

        let database = OpenCodeSessionReader.database(in: homeDirectory)
        if OpenCodeSessionReader.sourceExists(at: database) {
            let prefix = openCodeCachePrefix(for: database)
            for (key, entry) in cache where key.hasPrefix(prefix) {
                if let cwd = entry.record?.cwd { map["opencode", default: []].insert(cwd) }
            }
        }

        for record in ideWorkspaceRecords(
            homeDirectory: homeDirectory,
            cache: cache,
            readDatabase: false
        ).records {
            guard let cwd = record.cwd else { continue }
            map[record.tool, default: []].insert(PathTools.canonical(cwd))
        }

        return map.reduce(into: [String: Set<String>]()) { filtered, entry in
            let kept = entry.value.filter { !isInternalLLMWorkdir($0, excludedCwd: excludedCwd) }
            if !kept.isEmpty {
                filtered[entry.key] = kept
            }
        }
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

    private static func openCodeCachePrefix(for sqlite: URL) -> String {
        "opencode:\(PathTools.normalize(sqlite.path))\0"
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
        guard let stamp = fileStamp(file) else { return nil }
        let modified = Date(timeIntervalSince1970: stamp.mtime)
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

        var firstUser: String?
        var lastUser: String?
        var userTurnCount = 0
        var lastTimestamp = startedAt
        var rawTouchedFiles: [String] = []
        var lastError: String?
        var endedWithError = false
        var model: String?
        var usage: TokenUsage?
        var coverage = SessionLogMetrics.Coverage()
        var metrics = CodexLogMetrics()
        var promptSource: String?

        FileTools.scanLines(in: file, maxBytes: scanBytes) { line in
            guard let object = coverage.consume(line) else { return false }
            let timestamp = (object["timestamp"] as? String).flatMap(Format.isoDate)
            if let ts = timestamp {
                if lastTimestamp == nil || ts > lastTimestamp! {
                    lastTimestamp = ts
                }
            }

            let topType = object["type"] as? String
            if let linePayload = object["payload"] as? [String: Any] {
                let payloadType = linePayload["type"] as? String
                if topType == "event_msg", ["task_started", "turn_started"].contains(payloadType ?? "") {
                    promptSource = nil
                }
                if let prompt = codexUserMessage(type: topType, payload: linePayload) {
                    // Some rollout versions write both the response item and the user event.
                    if promptSource == nil || promptSource == prompt.source || lastUser != prompt.text {
                        if firstUser == nil { firstUser = prompt.text }
                        lastUser = prompt.text
                        userTurnCount += 1
                        endedWithError = false
                        metrics.hasCleanEnd = false
                    }
                    promptSource = prompt.source
                }
                metrics.consume(type: topType, payload: linePayload, timestamp: timestamp)

                if topType == "turn_context", let lineModel = linePayload["model"] as? String {
                    model = lineModel
                } else if payloadType == "token_count",
                          let info = linePayload["info"] as? [String: Any],
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

                if topType == "response_item" {
                    if payloadType == "custom_tool_call",
                       linePayload["name"] as? String == "apply_patch",
                       let patchInput = linePayload["input"] as? String {
                        rawTouchedFiles.append(contentsOf: extractApplyPatchPaths(from: patchInput))
                    } else if payloadType == "function_call",
                              let callName = linePayload["name"] as? String,
                              ["apply_patch", "write_file", "edit_file", "create_file"].contains(callName),
                              let argsString = linePayload["arguments"] as? String {
                        rawTouchedFiles.append(contentsOf: extractCodexFunctionCallPaths(from: argsString))
                    } else if payloadType == "custom_tool_call_output" || payloadType == "function_call_output" {
                        let parsed = extractCodexToolOutput(linePayload["output"])
                        let isError = (parsed.exitCode != nil && parsed.exitCode != 0)
                            || containsErrorMarker(parsed.text)
                        if isError {
                            lastError = meaningfulErrorSnippet(from: parsed.text) ?? FizzL10n.text("命令执行失败", "Command failed")
                            endedWithError = true
                        } else {
                            endedWithError = false
                        }
                    } else if linePayload["role"] as? String == "assistant" {
                        endedWithError = false
                    }
                }
            }

            return false
        }

        let touchedFiles = normalizeTouchedFiles(rawTouchedFiles, cwd: cwd)
        let durationMinutes = computeDurationMinutes(
            startedAt: startedAt,
            endedAt: lastTimestamp ?? modified
        )
        let cost = PricingCatalog.estimate(model: model, usage: usage)
        let current = fileStamp(file)
        let complete = coverage.covers(fileSize: stamp.fileSize) && current?.mtime == stamp.mtime
            && current?.fileSize == stamp.fileSize

        return SessionRecord(
            tool: "codex",
            id: id,
            cwd: cwd,
            startedAt: startedAt,
            modified: modified,
            lastUser: lastUser,
            model: model,
            usage: usage,
            costUSD: cost,
            costIsEstimate: cost == nil ? nil : true,
            firstUser: firstUser,
            touchedFiles: touchedFiles,
            lastError: lastError,
            endedWithError: endedWithError,
            turnCount: complete && userTurnCount > 0 ? userTurnCount : nil,
            durationMinutes: durationMinutes,
            agentTimeSeconds: metrics.time.seconds,
            testResult: metrics.tests.result(complete: complete && metrics.isComplete && userTurnCount > 0)
        )
    }

    private struct CodexLogMetrics {
        var time = SessionLogMetrics.AgentTime()
        var tests = SessionLogMetrics.Tests()
        var hasCleanEnd = false
        private var openTurns: [String: Int] = [:]
        private var endedTurns = Set<String>()
        private var execCalls = Set<String>()
        private var pollCalls: [String: Int] = [:]
        private var shellCalls: [String: SessionLogMetrics.Tests.Attempt] = [:]
        private var shellSessions: [Int: SessionLogMetrics.Tests.Attempt] = [:]

        var isComplete: Bool { hasCleanEnd && openTurns.isEmpty }

        mutating func consume(type: String?, payload: [String: Any], timestamp: Date?) {
            switch (type, payload["type"] as? String) {
            case ("event_msg", "task_started"), ("event_msg", "turn_started"):
                hasCleanEnd = false
                if let id = payload["turn_id"] as? String, openTurns[id] == nil {
                    openTurns[id] = Self.epochMilliseconds(payload["started_at"]) ?? Self.milliseconds(timestamp) ?? 0
                }
            case ("event_msg", "task_complete"), ("event_msg", "turn_complete"), ("event_msg", "turn_aborted"):
                guard let id = payload["turn_id"] as? String, endedTurns.insert(id).inserted else { return }
                let started = openTurns.removeValue(forKey: id)
                let start = Self.epochMilliseconds(payload["started_at"]) ?? started
                let end = Self.epochMilliseconds(payload["completed_at"]) ?? Self.milliseconds(timestamp)
                if let duration = SessionLogMetrics.integer(payload["duration_ms"]), duration >= 0 {
                    if let end, end > duration { time.add(start: end - duration, end: end) }
                    else { time.add(milliseconds: duration) }
                } else if let start, let end { time.add(start: start, end: end) }
                hasCleanEnd = payload["type"] as? String != "turn_aborted" && (payload["error"] == nil || payload["error"] is NSNull)
            case ("response_item", "function_call"):
                guard let id = payload["call_id"] as? String, let name = payload["name"] as? String else { return }
                let args = Self.object(payload["arguments"])
                if ["exec_command", "shell_command", "shell"].contains(name) {
                    guard execCalls.insert(id).inserted else { return }
                    hasCleanEnd = false
                    shellCalls[id] = tests.start(args?["cmd"] ?? args?["command"])
                } else if name == "write_stdin", let session = SessionLogMetrics.integer(args?["session_id"]) {
                    pollCalls[id] = session
                    shellCalls[id] = shellSessions[session]
                }
            case ("response_item", "function_call_output"):
                guard let id = payload["call_id"] as? String, execCalls.contains(id) || pollCalls[id] != nil else { return }
                let status = Self.shellStatus(payload["output"])
                let attempt = shellCalls[id]
                if let session = status.session { shellSessions[session] = attempt }
                if let session = pollCalls.removeValue(forKey: id), status.exit != nil { shellSessions[session] = nil }
                if let attempt { tests.finish(attempt, exitCode: status.exit) }
            case ("event_msg", "exec_command_end"):
                guard payload["source"] as? String != "user_shell", payload["status"] as? String != "declined",
                      let id = payload["call_id"] as? String else { return }
                let attempt = shellCalls[id] ?? tests.start(payload["command"])
                if let attempt { tests.finish(attempt, exitCode: SessionLogMetrics.integer(payload["exit_code"])) }
            default: break
            }
        }

        private static func epochMilliseconds(_ value: Any?) -> Int? {
            guard let seconds = SessionLogMetrics.integer(value), seconds > 0, seconds <= Int.max / 1_000 else { return nil }
            return seconds * 1_000
        }

        private static func milliseconds(_ date: Date?) -> Int? {
            date.flatMap { Int(exactly: ($0.timeIntervalSince1970 * 1_000).rounded()) }
        }

        private static func object(_ value: Any?) -> [String: Any]? {
            if let object = value as? [String: Any] { return object }
            guard let text = value as? String, text.first == "{" else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        }

        private static func shellStatus(_ value: Any?) -> (exit: Int?, session: Int?) {
            if let result = object(value) {
                let metadata = result["metadata"] as? [String: Any]
                return (SessionLogMetrics.integer(metadata?["exit_code"] ?? result["exit_code"]),
                        SessionLogMetrics.integer(metadata?["session_id"] ?? result["session_id"]))
            }
            guard let text = value as? String else { return (nil, nil) }
            // Only the executor's header can provide status; subsequent command output is untrusted.
            let lines = text.prefix(512).split(separator: "\n", maxSplits: 3)
            guard lines.count >= 3, lines[0].hasPrefix("Chunk ID: "), lines[1].hasPrefix("Wall time: ") else { return (nil, nil) }
            for (prefix, isSession) in [("Process exited with code ", false), ("Exit code: ", false),
                                        ("Process running with session ID ", true), ("Session ID: ", true)] {
                if lines[2].hasPrefix(prefix) {
                    let number = Int(lines[2].dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines))
                    return isSession ? (nil, number) : (number, nil)
                }
            }
            return (nil, nil)
        }
    }

    private static func parseClaude(_ file: URL, directoryName: String) -> SessionRecord? {
        guard let stamp = fileStamp(file) else { return nil }
        let modified = Date(timeIntervalSince1970: stamp.mtime)
        var cwd: String?
        var startedAt: Date?
        var lastTimestamp: Date?
        var firstUser: String?
        var lastUser: String?
        var userTurnCount = 0
        var rawTouchedFiles: [String] = []
        var lastError: String?
        var endedWithError = false

        var cost: Double?
        var costModel: String?
        var costUsage: TokenUsage?
        var messageUsage: TokenUsage?
        var messageModel: String?
        var coverage = SessionLogMetrics.Coverage()
        var agentTime = SessionLogMetrics.AgentTime()
        var tests = SessionLogMetrics.Tests()
        var shellCalls: [String: SessionLogMetrics.Tests.Attempt] = [:]
        var seenShellCalls = Set<String>()
        var timedTurns = Set<String>()
        var hasCleanEnd = false

        FileTools.scanLines(in: file, maxBytes: scanBytes) { line in
            guard let object = coverage.consume(line) else { return false }

            if cwd == nil, let value = object["cwd"] as? String, !value.isEmpty {
                cwd = value
            }

            if let ts = (object["timestamp"] as? String).flatMap(Format.isoDate) {
                if startedAt == nil || ts < startedAt! { startedAt = ts }
                if lastTimestamp == nil || ts > lastTimestamp! { lastTimestamp = ts }
            }

            let topType = object["type"] as? String
            let mainThread = object["isSidechain"] as? Bool != true
            if mainThread, topType == "system", object["subtype"] as? String == "turn_duration",
               let duration = SessionLogMetrics.integer(object["durationMs"]), duration >= 0 {
                let id = object["uuid"] as? String ?? object["timestamp"] as? String
                if id.map({ timedTurns.insert($0).inserted }) ?? true {
                    agentTime.add(milliseconds: duration)
                    hasCleanEnd = true
                }
            }
            if topType == "user", let message = object["message"] as? [String: Any] {
                if let items = message["content"] as? [[String: Any]] {
                    let results = items.filter { $0["type"] as? String == "tool_result" }
                    for item in results {
                        if mainThread, let id = item["tool_use_id"] as? String, let attempt = shellCalls[id] {
                            let metadata = results.count == 1 ? object["toolUseResult"] : nil
                            tests.finish(attempt, exitCode: claudeBashExit(result: item, metadata: metadata))
                        }
                        if item["is_error"] as? Bool == true {
                            let errText = text(from: item["content"])
                            lastError = meaningfulErrorSnippet(from: errText) ?? FizzL10n.text("工具调用失败", "Tool call failed")
                            endedWithError = true
                        } else {
                            endedWithError = false
                        }
                    }
                }
                if message["role"] as? String == "user" {
                    let cleaned = cleanUserText(text(from: message["content"]))
                    if !cleaned.isEmpty, object["isMeta"] as? Bool != true {
                        if firstUser == nil { firstUser = cleaned }
                        lastUser = cleaned
                        userTurnCount += 1
                        endedWithError = false
                        if mainThread { hasCleanEnd = false }
                    }
                }
            } else if topType == "assistant", let message = object["message"] as? [String: Any] {
                if mainThread, let reason = message["stop_reason"] as? String { hasCleanEnd = reason == "end_turn" }
                if let items = message["content"] as? [[String: Any]] {
                    for item in items where item["type"] as? String == "tool_use" {
                        let id = item["id"] as? String
                        if mainThread, item["name"] as? String == "Bash", id.map({ seenShellCalls.insert($0).inserted }) ?? true {
                            hasCleanEnd = false
                            let attempt = tests.start((item["input"] as? [String: Any])?["command"])
                            if let id { shellCalls[id] = attempt }
                        }
                        if let name = item["name"] as? String,
                           ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(name),
                           let input = item["input"] as? [String: Any] {
                            let candidate = (input["file_path"] as? String)
                                ?? (input["path"] as? String)
                                ?? (input["notebook_path"] as? String)
                            if let candidate, !candidate.isEmpty {
                                rawTouchedFiles.append(candidate)
                            }
                        }
                    }
                }
                if let values = message["usage"] as? [String: Any] {
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
            } else if topType == "cost-state" {
                if object["hasUnknownModelCost"] as? Bool != true,
                   let total = (object["totalCostUSD"] as? NSNumber)?.doubleValue,
                   total > 0 {
                    cost = total
                }
                if let models = object["modelUsage"] as? [String: Any] {
                    var aggregate = TokenUsage.zero
                    var parsedModel: String?
                    for (name, raw) in models {
                        guard let values = raw as? [String: Any] else { continue }
                        if parsedModel == nil { parsedModel = name }
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
                    costModel = parsedModel
                    costUsage = aggregate
                }
            }

            return false
        }

        let fallbackCwd = directoryName.hasPrefix("-")
            ? directoryName.replacingOccurrences(of: "-", with: "/")
            : nil
        let resolvedCwd = cwd ?? fallbackCwd
        let touchedFiles = normalizeTouchedFiles(rawTouchedFiles, cwd: resolvedCwd)
        let durationMinutes = computeDurationMinutes(
            startedAt: startedAt,
            endedAt: lastTimestamp ?? modified
        )

        let finalModel = cost != nil ? costModel : messageModel
        let finalUsage = cost != nil ? costUsage : messageUsage
        let finalCost = cost ?? PricingCatalog.estimate(model: finalModel, usage: finalUsage)
        let current = fileStamp(file)
        let complete = coverage.covers(fileSize: stamp.fileSize) && current?.mtime == stamp.mtime
            && current?.fileSize == stamp.fileSize

        return SessionRecord(
            tool: "claude",
            id: file.deletingPathExtension().lastPathComponent,
            cwd: resolvedCwd,
            startedAt: startedAt,
            modified: modified,
            lastUser: lastUser,
            model: finalModel,
            usage: finalUsage,
            costUSD: finalCost,
            costIsEstimate: finalCost == nil ? nil : cost == nil,
            firstUser: firstUser,
            touchedFiles: touchedFiles,
            lastError: lastError,
            endedWithError: endedWithError,
            turnCount: complete && userTurnCount > 0 ? userTurnCount : nil,
            durationMinutes: durationMinutes,
            agentTimeSeconds: agentTime.seconds,
            testResult: tests.result(complete: complete && hasCleanEnd && userTurnCount > 0)
        )
    }

    private static func claudeBashExit(result: [String: Any], metadata: Any?) -> Int? {
        if let shell = metadata as? [String: Any] {
            guard shell["interrupted"] as? Bool == false, shell["backgroundTaskId"] == nil,
                  shell["timedOutAfterMs"] == nil else { return nil }
            if let code = SessionLogMetrics.integer(shell["exitCode"]) { return code }
            if result["is_error"] as? Bool != true, shell["stdout"] is String, shell["stderr"] is String { return 0 }
        }
        guard result["is_error"] as? Bool == true else { return nil }
        // is_error also covers rejected approvals and interruption; require the Bash exit header.
        for value in [metadata as? String, result["content"] as? String].compactMap({ $0 }) {
            let line = value.prefix(160).split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces) ?? ""
            for prefix in ["Error: Exit code ", "Exit code "] where line.hasPrefix(prefix) {
                if let code = Int(line.dropFirst(prefix.count)), code != 0 { return code }
            }
        }
        return nil
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
        readDatabase: Bool,
        skipCursorCwds: Set<String> = []
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
                let workspaceFile = directory.appendingPathComponent("workspace.json")
                if tool == "cursor", !skipCursorCwds.isEmpty,
                   let cwd = ideWorkspaceDirectory(workspaceFile), skipCursorCwds.contains(PathTools.canonical(cwd)) { continue }
                let workspace = IDEWorkspace(
                    tool: tool,
                    directory: directory,
                    databaseName: databaseName
                )
                let files = [
                    workspaceFile,
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
        guard let cwd = ideWorkspaceDirectory(workspaceFile) else { return nil }

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
            cwd: cwd,
            startedAt: nil,
            modified: modified,
            lastUser: lastUser,
            kind: .workspaceSummary
        ).withLastUserFallback(FizzL10n.text("\(title) 工作区活动", "\(title) workspace activity"))
    }

    private static func ideWorkspaceDirectory(_ workspaceFile: URL) -> String? {
        guard let json = FileTools.json(workspaceFile),
              let folder = json["folder"] as? String else { return nil }
        return PathTools.localFilePath(folder)
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

    private static func codexUserMessage(type: String?, payload: [String: Any]) -> (text: String, source: String)? {
        let content: Any?
        let source: String
        if type == "event_msg" {
            switch payload["type"] as? String {
            case "user_message":
                content = payload["message"]
                source = "user_message"
            case "item_completed":
                guard let item = payload["item"] as? [String: Any], item["type"] as? String == "UserMessage" else { return nil }
                content = item["content"]
                source = "item_completed"
            default: return nil
            }
        } else if payload["role"] as? String == "user" {
            content = payload["content"]
            source = "response_item"
        } else {
            return nil
        }

        let text = cleanUserText(text(from: content))
        guard !text.isEmpty, !text.hasPrefix("<") else { return nil }
        return (text, source)
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
        SessionSummaryText.clean(value)
    }

    private static func computeDurationMinutes(startedAt: Date?, endedAt: Date?) -> Int? {
        guard let startedAt, let endedAt else { return nil }
        let span = max(0, endedAt.timeIntervalSince(startedAt))
        return span >= 10 ? max(1, Int((span / 60.0).rounded())) : 0
    }

    private static func normalizeTouchedFiles(_ rawPaths: [String], cwd: String?) -> [String] {
        let normalizedCwd = cwd.map(PathTools.normalize)
        var seen = Set<String>()
        var result: [String] = []

        for raw in rawPaths {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("./") {
                trimmed = String(trimmed.dropFirst(2))
            }
            if let normalizedCwd, !normalizedCwd.isEmpty {
                let normalizedFile = trimmed.hasPrefix("/") ? PathTools.normalize(trimmed) : trimmed
                let prefix = normalizedCwd.hasSuffix("/") ? normalizedCwd : normalizedCwd + "/"
                if normalizedFile.hasPrefix(prefix) {
                    trimmed = String(normalizedFile.dropFirst(prefix.count))
                }
            }
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
            if result.count >= maxTouchedFiles { break }
        }
        return result
    }

    private static func extractApplyPatchPaths(from patch: String) -> [String] {
        let markers = [
            "*** Update File: ",
            "*** Add File: ",
            "*** Delete File: ",
            "*** Move to: ",
        ]
        var paths: [String] = []
        for rawLine in patch.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            for marker in markers where line.hasPrefix(marker) {
                let path = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { paths.append(path) }
                break
            }
        }
        return paths
    }

    private static func extractCodexFunctionCallPaths(from argumentsJSON: String) -> [String] {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var paths: [String] = []
        for key in ["path", "file_path", "target_file"] {
            if let value = args[key] as? String, !value.isEmpty {
                paths.append(value)
            }
        }
        for key in ["input", "patch"] {
            if let patch = args[key] as? String {
                paths.append(contentsOf: extractApplyPatchPaths(from: patch))
            }
        }
        return paths
    }

    private static func extractCodexToolOutput(_ raw: Any?) -> (text: String, exitCode: Int?) {
        if let dict = raw as? [String: Any] {
            let outputText = dict["output"] as? String ?? ""
            let meta = dict["metadata"] as? [String: Any]
            let exitCode = (meta?["exit_code"] as? NSNumber)?.intValue
            return (outputText, exitCode)
        }
        guard let str = raw as? String else { return ("", nil) }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let outputText = dict["output"] as? String ?? str
            let meta = dict["metadata"] as? [String: Any]
            let exitCode = (meta?["exit_code"] as? NSNumber)?.intValue
            return (outputText, exitCode)
        }
        return (str, parseExitCode(in: str))
    }

    private static func parseExitCode(in text: String) -> Int? {
        let patterns = [
            #"(?i)Exit code:\s*(-?\d+)"#,
            #"(?i)Process exited with code\s+(-?\d+)"#,
        ]
        let nsText = text as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
                  match.numberOfRanges > 1
            else { continue }
            let numStr = nsText.substring(with: match.range(at: 1))
            if let code = Int(numStr) {
                return code
            }
        }
        return nil
    }

    private static func containsErrorMarker(_ text: String) -> Bool {
        let prefixes = ["Error:", "error:", "Exception:", "FAILED", "fatal:", "Command failed"]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if prefixes.contains(where: { line.hasPrefix($0) || line.contains(" \($0)") }) {
                return true
            }
        }
        return false
    }

    private static func meaningfulErrorSnippet(from text: String) -> String? {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let priorityMarkers = ["Error:", "error:", "Exception:", "FAILED", "fatal:", "Command failed"]
        let chosen = lines.first(where: { line in
            priorityMarkers.contains(where: { line.contains($0) })
        }) ?? lines.first ?? ""
        guard !chosen.isEmpty else { return nil }

        let redacted = SecretRedactor.redact(chosen).text
        return String(redacted.prefix(maxErrorCharacters))
    }

    // MARK: - DeepSeek Harness (.dsh)

    private static func lightweightDeepSeekCwd(in file: URL) -> String? {
        guard let object = FileTools.json(file),
              let record = object["record"] as? [String: Any]
        else { return nil }
        return extractDeepSeekCwd(from: record)
    }

    private static func parseDeepSeek(_ file: URL) -> SessionRecord? {
        guard let object = FileTools.json(file),
              let record = object["record"] as? [String: Any],
              let cwd = extractDeepSeekCwd(from: record)
        else { return nil }

        let identity = record["identity"] as? [String: Any]
        let rows = record["rows"] as? [String: Any]

        let startedAt = dateFromEpochMillis(identity?["createdAt"])
        let timeVal = (rows?["timeContext"] as? [String: Any])?["val"] as? [String: Any]
        let modified = dateFromEpochMillis(timeVal?["lastMessageTime"])
            ?? FileTools.modificationDate(file)
            ?? startedAt
            ?? Date()

        let titleText = (rows?["title"] as? [String: Any])?["val"] as? String
        let firstInputText = (((rows?["titleInput"] as? [String: Any])?["val"] as? [String: Any])?["first"] as? [String: Any])?["text"] as? String
        let turns = ((rows?["turnOutline"] as? [String: Any])?["val"] as? [String: Any])?["turns"] as? [[String: Any]]
        let lastTurnPrompt = turns?.last?["prompt"] as? String
        let rawTitle = [titleText, firstInputText, lastTurnPrompt]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let lastUser = rawTitle.map { cleanUserText($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let firstUser = firstInputText.map { cleanUserText($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let turnCount = turns.flatMap { $0.isEmpty ? nil : $0.count }

        let modelVal = (rows?["modelSelection"] as? [String: Any])?["val"] as? [String: Any]
        let lastUsedModel = (modelVal?["lastUsed"] as? [String: Any])?["model"] as? String
        let activityModel = ((rows?["contextActivity"] as? [String: Any])?["val"] as? [String: Any])?["model"] as? String
        let model = [lastUsedModel, activityModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let totals = ((rows?["tokenUsage"] as? [String: Any])?["val"] as? [String: Any])?["totals"] as? [String: Any]
        var usage: TokenUsage?
        if let totals {
            let uncached = int(totals["uncachedInputTokens"])
            let cacheRead = int(totals["cacheReadTokens"])
            let cacheWrite = int(totals["cacheWriteTokens"])
            let output = int(totals["outputTokens"])
            let inputTokens = uncached + cacheRead
            let totalTokens = inputTokens + cacheWrite + output
            if totalTokens > 0 {
                usage = TokenUsage(
                    inputTokens: inputTokens,
                    cachedInputTokens: cacheRead,
                    cacheWriteInputTokens: cacheWrite,
                    outputTokens: output,
                    reasoningOutputTokens: 0,
                    totalTokens: totalTokens
                )
            }
        }

        let cost = PricingCatalog.estimate(model: model, usage: usage)
        return SessionRecord(
            tool: "deepseek",
            id: file.deletingPathExtension().lastPathComponent,
            cwd: cwd,
            startedAt: startedAt,
            modified: modified,
            lastUser: lastUser,
            kind: .conversation,
            model: model,
            usage: usage,
            costUSD: cost,
            costIsEstimate: cost != nil ? true : nil,
            firstUser: firstUser,
            turnCount: turnCount
        )
    }

    private static func extractDeepSeekCwd(from record: [String: Any]) -> String? {
        let identity = record["identity"] as? [String: Any]
        let rows = record["rows"] as? [String: Any]
        let workingDirVal = (rows?["workingDirectory"] as? [String: Any])?["val"] as? String
        let raw = [identity?["cwd"] as? String, workingDirVal]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return raw
    }

    // MARK: - Antigravity / AGY CLI

    private struct AgySummaryRow {
        let id: String
        let title: String
        let lastModifiedTime: String
        let cwd: String
        let parentID: String
    }

    private static func lightweightAgyCwds(homeDirectory: URL) -> Set<String> {
        let rows = loadAgySummaryRows(homeDirectory: homeDirectory)
        return Set(rows.map { PathTools.canonical($0.cwd) })
    }

    private static func agyRecords(
        homeDirectory: URL,
        cache: [String: SessionCacheEntry]
    ) -> (records: [SessionRecord], cacheEntries: [String: SessionCacheEntry], changed: Bool) {
        let rows = loadAgySummaryRows(homeDirectory: homeDirectory)
        guard !rows.isEmpty else { return ([], [:], false) }

        var childrenByParent: [String: [String]] = [:]
        var topLevelRows: [AgySummaryRow] = []
        for row in rows {
            if row.parentID.isEmpty {
                topLevelRows.append(row)
            } else {
                childrenByParent[row.parentID, default: []].append(row.id)
            }
        }

        let brainRoot = homeDirectory.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        var records: [SessionRecord] = []
        var cacheEntries: [String: SessionCacheEntry] = [:]
        var changed = false

        for row in topLevelRows {
            let childIDs = childrenByParent[row.id] ?? []
            let transcriptFiles = ([row.id] + childIDs).compactMap { id -> URL? in
                let url = brainRoot
                    .appendingPathComponent(id, isDirectory: true)
                    .appendingPathComponent(".system_generated/logs/transcript.jsonl")
                return FileTools.exists(url) ? url : nil
            }

            let parsedModified = parseAgyTimestamp(row.lastModifiedTime)
            let stamp = bundleStamp(transcriptFiles) ?? (
                mtime: parsedModified?.timeIntervalSince1970 ?? 0,
                fileSize: Int64(childIDs.count)
            )
            let key = "\(agyCachePrefix)\(row.id)"

            let entry: SessionCacheEntry
            if let cached = cache[key],
               abs(cached.mtime - stamp.mtime) < 0.001,
               cached.fileSize == stamp.fileSize,
               (parsedModified == nil || abs((cached.record?.modified ?? .distantPast).timeIntervalSince1970 - (parsedModified?.timeIntervalSince1970 ?? 0)) < 1.0) {
                entry = cached
            } else {
                let info = agyUsageInfo(in: transcriptFiles)
                let modified = parsedModified
                    ?? transcriptFiles.compactMap(FileTools.modificationDate).max()
                    ?? Date()
                let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let lastUser = title.isEmpty ? nil : String(title.prefix(400))
                let cost = PricingCatalog.estimate(model: info.model, usage: info.usage)
                let record = SessionRecord(
                    tool: "agy",
                    id: row.id,
                    cwd: row.cwd,
                    startedAt: info.startedAt,
                    modified: modified,
                    lastUser: lastUser,
                    kind: .conversation,
                    model: info.model,
                    usage: info.usage,
                    costUSD: cost,
                    costIsEstimate: cost != nil ? true : nil
                )
                entry = SessionCacheEntry(
                    mtime: stamp.mtime,
                    fileSize: stamp.fileSize,
                    record: record
                )
                changed = true
            }

            cacheEntries[key] = entry
            if let record = entry.record {
                records.append(record)
            }
        }

        return (records, cacheEntries, changed)
    }

    private static func loadAgySummaryRows(homeDirectory: URL) -> [AgySummaryRow] {
        let dbURL = homeDirectory.appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
        guard FileTools.exists(dbURL) else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            dbURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK,
            let database
        else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 120)
        var statement: OpaquePointer?
        let sql = "SELECT conversation_id, title, last_modified_time, workspace_uris, parent_conversation_id FROM conversation_summaries WHERE workspace_uris != '' AND workspace_uris != '[]';"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return [] }
        defer { sqlite3_finalize(statement) }

        var rows: [AgySummaryRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let urisPtr = sqlite3_column_text(statement, 3)
            else { continue }
            let id = String(cString: idPtr)
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let modified = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let urisRaw = String(cString: urisPtr)
            let parentID = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""

            guard let cwd = firstWorkspacePath(from: urisRaw) else { continue }
            rows.append(AgySummaryRow(
                id: id,
                title: title,
                lastModifiedTime: modified,
                cwd: cwd,
                parentID: parentID
            ))
        }
        return rows
    }

    private static func firstWorkspacePath(from workspaceUrisJSON: String) -> String? {
        guard let data = workspaceUrisJSON.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        for uri in array {
            if let url = URL(string: uri), url.isFileURL, !url.path.isEmpty {
                return PathTools.normalize(url.path)
            }
        }
        return nil
    }

    private static func agyUsageInfo(
        in files: [URL]
    ) -> (model: String?, usage: TokenUsage?, startedAt: Date?) {
        var uncachedInput = 0
        var cacheRead = 0
        var cacheWrite = 0
        var output = 0
        var latestModel: String?
        var latestModelTime = Date.distantPast
        var earliestDate: Date?

        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("input_tokens") || line.contains("output_tokens") || line.contains("created_at"),
                      let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                let createdAt = (object["created_at"] as? String).flatMap(parseAgyTimestamp)
                if let createdAt, earliestDate == nil || createdAt < earliestDate! {
                    earliestDate = createdAt
                }

                let hasUsage = object["input_tokens"] != nil || object["output_tokens"] != nil
                guard hasUsage else { continue }

                uncachedInput += int(object["input_tokens"])
                cacheRead += int(object["cache_read_tokens"])
                cacheWrite += int(object["cache_write_tokens"])
                output += int(object["output_tokens"])

                if let modelName = object["model"] as? String, !modelName.isEmpty {
                    let timestamp = createdAt ?? Date.distantPast
                    if latestModel == nil || timestamp >= latestModelTime {
                        latestModel = modelName
                        latestModelTime = timestamp
                    }
                }
            }
        }

        let inputTokens = uncachedInput + cacheRead
        let totalTokens = inputTokens + cacheWrite + output
        let usage = totalTokens > 0
            ? TokenUsage(
                inputTokens: inputTokens,
                cachedInputTokens: cacheRead,
                cacheWriteInputTokens: cacheWrite,
                outputTokens: output,
                reasoningOutputTokens: 0,
                totalTokens: totalTokens
            )
            : nil

        return (latestModel, usage, earliestDate)
    }

    private static func dateFromEpochMillis(_ raw: Any?) -> Date? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1000.0 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseAgyTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }

        let sqliteFormats = [
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
        ]
        for format in sqliteFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}
