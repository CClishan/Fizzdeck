import Darwin
import Foundation
import SQLite3

enum OpenCodeSessionReader {
    static let storagePath = ".local/share/opencode"

    struct Snapshot: Sendable {
        // An opaque cache key. SessionRecord.modified holds the real session timestamp.
        let revision: Int64
        let record: SessionRecord?
    }

    private static let maxSessions = 1_000
    private static let maxRowsPerSession = 4_096
    private static let maxPayloadBytes = 256 * 1_024
    private static let maxBytesPerSession = 4 * 1_024 * 1_024
    private static let maxFiles = 40

    static func database(in homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(storagePath + "/opencode.db", isDirectory: false)
    }

    static func sourceExists(at database: URL) -> Bool {
        guard database.isFileURL, let path = PathTools.localFilePath(database.absoluteString) else { return false }
        return FileStamp(path) != nil
    }

    // nil means the source could not be read safely; a successful empty scan returns [:].
    static func read(database: URL, cached: [String: Snapshot] = [:]) -> [String: Snapshot]? {
        guard database.isFileURL, let path = PathTools.localFilePath(database.absoluteString),
              let source = FileStamp(path) else { return nil }
        let wal = path + "-wal"
        let shm = path + "-shm"
        let journal = path + "-journal"
        let sidecarsAbsent = isMissing(wal) && isMissing(shm)
        guard sidecarsAbsent || (FileStamp(wal) != nil && FileStamp(shm) != nil) else { return nil }
        let uri = URL(fileURLWithPath: path).absoluteString + "?mode=ro&readonly_shm=1"

        do {
            // The Unix VFS otherwise opens writable SHM even for a read-only connection.
            // FizzDeck never opens this database as a writer in its own process.
            let result = try readSQLite(uri, source: source, cached: cached)
            guard let current = FileStamp(path), current.device == source.device,
                  current.inode == source.inode else { return nil }
            return result
        } catch let error as SQLiteError where error.code == SQLITE_CANTOPEN && sidecarsAbsent {
            // A cleanly closed WAL database keeps its WAL header, even after removing both sidecars.
            // Only accept its checkpointed contents if nothing changed around the unlocked read.
            guard isMissing(wal), isMissing(shm), isMissing(journal), FileStamp(path) == source,
                  let result = try? readSQLite(uri + "&immutable=1", source: source, cached: cached),
                  isMissing(wal), isMissing(shm), isMissing(journal), FileStamp(path) == source
            else { return nil }
            return result
        } catch {
            return nil
        }
    }

    private static func readSQLite(
        _ uri: String, source: FileStamp, cached: [String: Snapshot]
    ) throws -> [String: Snapshot] {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        try check(sqlite3_open_v2(uri, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_PRIVATECACHE, "unix"))
        guard let connection else { throw SQLiteError(code: SQLITE_CANTOPEN) }
        sqlite3_busy_timeout(connection, 50)
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_500_000_000
        return try withUnsafePointer(to: deadline) { deadline in
            sqlite3_progress_handler(connection, 1_000, { context in
                guard let context else { return 1 }
                return DispatchTime.now().uptimeNanoseconds >= context.load(as: UInt64.self) ? 1 : 0
            }, UnsafeMutableRawPointer(mutating: deadline))
            defer { sqlite3_progress_handler(connection, 0, nil, nil) }
            try check(sqlite3_exec(connection, "PRAGMA trusted_schema=OFF; PRAGMA temp_store=MEMORY; BEGIN DEFERRED;", nil, nil, nil))
            return try readRows(connection, source: source, cached: cached)
        }
    }

    private static func readRows(
        _ db: OpaquePointer, source: FileStamp, cached: [String: Snapshot]
    ) throws -> [String: Snapshot] {
        let sessions = try Statement(db, """
            SELECT id, directory, time_created, time_updated FROM session
            WHERE parent_id IS NULL AND octet_length(id) BETWEEN 1 AND 256
                AND octet_length(directory) BETWEEN 1 AND 4096
            ORDER BY time_updated DESC, id DESC LIMIT \(maxSessions)
            """)
        let metadata = try Statement(db, """
            SELECT 0, id, time_created, time_updated, size FROM (
                SELECT id, time_created, time_updated, octet_length(data) AS size FROM message
                WHERE session_id = ?1 LIMIT \(maxRowsPerSession + 1)
            )
            UNION ALL
            SELECT 1, id, time_created, time_updated, size FROM (
                SELECT id, time_created, time_updated, octet_length(data) AS size FROM part
                WHERE session_id = ?1 LIMIT \(maxRowsPerSession + 1)
            )
            """)
        let payload = "CASE WHEN typeof(data) = 'text' AND octet_length(data) <= \(maxPayloadBytes) THEN data END"
        let messages = try Statement(db, """
            SELECT id, \(payload) FROM message WHERE session_id = ?1 ORDER BY time_created, id
            """)
        let parts = try Statement(db, """
            SELECT message_id, \(payload) FROM part WHERE session_id = ?1 ORDER BY id
            """)
        var result: [String: Snapshot] = [:]
        var remainingBytes = 64 * 1_024 * 1_024
        while try sessions.next() {
            guard let id = sessions.text(0, maxBytes: 256), !id.contains("\0"),
                  let directory = sessions.text(1, maxBytes: 4_096), let path = PathTools.localFilePath(directory),
                  let created = sessions.milliseconds(2), let updated = sessions.milliseconds(3)
            else { continue }

            // OpenCode projects message and part updates independently of session.time_updated.
            try metadata.bind(id)
            var rowCount = 0
            var payloadBytes = 0
            var childRevision: UInt64 = 0
            while try metadata.next() {
                rowCount += 1
                guard rowCount <= maxRowsPerSession else { break }
                let size = metadata.integer(4)
                if size > 0, size <= maxPayloadBytes { payloadBytes += Int(size) }
                var row = Revision()
                row.add(metadata.integer(0))
                row.add(metadata.text(1, maxBytes: 256) ?? "")
                row.add(metadata.integer(2))
                row.add(metadata.integer(3))
                row.add(size)
                childRevision &+= row.value
            }
            // shortcut: leave very large transcripts out if their first/last turns cannot be verified within the budget.
            guard rowCount <= maxRowsPerSession, payloadBytes <= maxBytesPerSession else { continue }
            var revision = Revision()
            revision.add(2) // Snapshot record format.
            revision.add(Int64(source.device))
            revision.add(Int64(bitPattern: source.inode))
            revision.add(directory)
            revision.add(created)
            revision.add(updated)
            revision.add(Int64(rowCount))
            revision.add(Int64(bitPattern: childRevision))
            let key = Int64(truncatingIfNeeded: revision.value & UInt64(Int64.max))
            if let previous = cached[id], previous.revision == key {
                result[id] = previous
            } else if payloadBytes <= remainingBytes, let cwd = PathTools.canonicalWithMissingSuffix(path) {
                remainingBytes -= payloadBytes
                result[id] = Snapshot(revision: key, record: try record(
                    id: id, cwd: cwd, created: created, updated: updated,
                    messages: messages, parts: parts
                ))
            }
        }
        return result
    }

    private static func record(
        id: String, cwd: String, created: Int64, updated: Int64, messages: Statement, parts: Statement
    ) throws -> SessionRecord? {
        try messages.bind(id)
        var order: [String] = []
        var prompts: [String: String] = [:]
        var assistants = Set<String>()
        var errors: [String: AssistantFailure] = [:]
        var model: String?
        var agentTime = SessionLogMetrics.AgentTime()
        var tests = SessionLogMetrics.Tests()
        var finishedUserTurns: [String: Bool] = [:]
        var complete = true
        while try messages.next() {
            guard let messageID = messages.text(0, maxBytes: 256), let data = messages.object(1) else {
                complete = false
                continue
            }
            switch data["role"] as? String {
            case "user":
                order.append(messageID)
                prompts[messageID] = ""
            case "assistant":
                order.append(messageID)
                assistants.insert(messageID)
                errors[messageID] = AssistantFailure(data["error"])
                if let time = data["time"] as? [String: Any],
                   let start = SessionLogMetrics.integer(time["created"]),
                   let end = SessionLogMetrics.integer(time["completed"]), start > 0, end >= start {
                    agentTime.add(start: start, end: end)
                    if let parent = data["parentID"] as? String {
                        finishedUserTurns[parent] = data["finish"] as? String == "stop" && (data["error"] == nil || data["error"] is NSNull)
                    }
                } else {
                    complete = false
                }
                if let value = data["modelID"] as? String, !value.isEmpty, value.utf8.count <= 256 {
                    model = value
                }
            default: break
            }
        }
        guard !prompts.isEmpty else { return nil }

        var files: [String] = []
        var seen = Set<String>()
        try parts.bind(id)
        while try parts.next() {
            guard let messageID = parts.text(0, maxBytes: 256), let data = parts.object(1) else {
                complete = false
                continue
            }
            if let prompt = prompts[messageID], prompt.count < 400,
               data["type"] as? String == "text", data["synthetic"] as? Bool != true,
               data["ignored"] as? Bool != true, let text = data["text"] as? String {
                let body = SessionSummaryText.clean(SecretRedactor.redact(text).text)
                if !body.isEmpty { prompts[messageID] = String((prompt.isEmpty ? body : prompt + "\n" + body).prefix(400)) }
            } else if assistants.contains(messageID), data["type"] as? String == "tool" {
                let state = data["state"] as? [String: Any]
                let status = state?["status"] as? String
                if status != "completed", status != "error" { complete = false }
                if data["tool"] as? String == "bash",
                   let attempt = tests.start((state?["input"] as? [String: Any])?["command"]), status == "completed" {
                    let metadata = state?["metadata"] as? [String: Any]
                    if metadata?["timeout"] as? Bool != true {
                        tests.finish(attempt, exitCode: SessionLogMetrics.integer(metadata?["exit"]))
                    }
                }
                if files.count < maxFiles {
                    for raw in editedPaths(in: data) {
                        guard let path = PathTools.projectRelativeFile(raw, in: cwd), seen.insert(path).inserted else { continue }
                        files.append(path)
                        if files.count == maxFiles { break }
                    }
                }
            } else if prompts[messageID] == nil && !assistants.contains(messageID) {
                complete = false
            }
        }
        var actual: [String] = []
        var lastError: String?
        var endedWithError = false
        for messageID in order {
            if let prompt = prompts[messageID], !prompt.isEmpty {
                actual.append(prompt)
                if finishedUserTurns[messageID] != true { complete = false }
                endedWithError = false
            } else if assistants.contains(messageID) {
                let failure = errors[messageID]
                endedWithError = failure != nil
                if let failure { lastError = failure.message }
            }
        }
        guard let first = actual.first else { return nil }
        let span = Double(max(0, updated - created)) / 1_000
        return SessionRecord(
            tool: "opencode", id: id, cwd: cwd, startedAt: Date(timeIntervalSince1970: Double(created) / 1_000),
            modified: Date(timeIntervalSince1970: Double(updated) / 1_000), lastUser: actual.last, model: model,
            firstUser: first, touchedFiles: files, lastError: lastError, endedWithError: endedWithError,
            turnCount: actual.count,
            durationMinutes: span >= 10 ? max(1, Int((span / 60).rounded())) : 0,
            agentTimeSeconds: agentTime.seconds,
            testResult: tests.result(complete: complete)
        )
    }

    private struct AssistantFailure {
        let message: String?

        init?(_ value: Any?) {
            guard let error = value as? [String: Any], let name = error["name"] as? String,
                  !name.isEmpty, name != "MessageAbortedError", let data = error["data"] as? [String: Any]
            else { return nil }
            let text = (data["message"] as? String).map { SecretRedactor.redact($0).text }
            let line = text?.split(whereSeparator: \.isNewline).lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            message = line.map { String($0.prefix(240)) }
        }
    }

    private static func editedPaths(in part: [String: Any]) -> [String] {
        guard part["type"] as? String == "tool", let state = part["state"] as? [String: Any],
              state["status"] as? String == "completed" else { return [] }
        let metadata = state["metadata"] as? [String: Any]
        switch part["tool"] as? String {
        case "edit", "write":
            let input = state["input"] as? [String: Any]
            let diff = metadata?["filediff"] as? [String: Any]
            let path = metadata?["filepath"] as? String ?? diff?["file"] as? String ?? input?["filePath"] as? String
            return [path].compactMap { $0 }
        case "apply_patch":
            let files = metadata?["files"] as? [[String: Any]] ?? []
            return files.flatMap { [$0["filePath"] as? String, $0["movePath"] as? String].compactMap { $0 } }
        default: return []
        }
    }

    private struct FileStamp: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modified: [Int]
        let changed: [Int]

        init?(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modified = [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec]
            changed = [info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec]
        }
    }

    private static func isMissing(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) != 0 && errno == ENOENT
    }

    private struct Revision {
        // Stable across launches so a disk cache can also reuse the same snapshot.
        private(set) var value: UInt64 = 14_695_981_039_346_656_037

        mutating func add(_ integer: Int64) {
            withUnsafeBytes(of: integer.littleEndian) { add(bytes: $0) }
        }

        mutating func add(_ string: String) {
            add(Int64(string.utf8.count))
            add(bytes: string.utf8)
        }

        private mutating func add(bytes: some Sequence<UInt8>) {
            for byte in bytes { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        }
    }

    private struct SQLiteError: Error { let code: Int32 }

    private static func check(_ code: Int32) throws {
        if code != SQLITE_OK { throw SQLiteError(code: code) }
    }

    private final class Statement {
        private let handle: OpaquePointer

        init(_ db: OpaquePointer, _ sql: String) throws {
            var statement: OpaquePointer?
            try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
            guard let statement else { throw SQLiteError(code: SQLITE_ERROR) }
            handle = statement
        }

        deinit { sqlite3_finalize(handle) }

        func bind(_ id: String) throws {
            try check(sqlite3_reset(handle))
            let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            try check(sqlite3_bind_text(handle, 1, id, -1, copy))
        }

        func next() throws -> Bool {
            switch sqlite3_step(handle) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            case let code: throw SQLiteError(code: code)
            }
        }

        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }

        func milliseconds(_ column: Int32) -> Int64? {
            let value = integer(column)
            return sqlite3_column_type(handle, column) == SQLITE_INTEGER && value > 0 ? value : nil
        }

        func text(_ column: Int32, maxBytes: Int) -> String? {
            guard sqlite3_column_type(handle, column) == SQLITE_TEXT,
                  let bytes = sqlite3_column_text(handle, column) else { return nil }
            let count = Int(sqlite3_column_bytes(handle, column))
            guard count <= maxBytes else { return nil }
            return String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8)
        }

        func object(_ column: Int32) -> [String: Any]? {
            guard sqlite3_column_type(handle, column) == SQLITE_TEXT,
                  let bytes = sqlite3_column_text(handle, column) else { return nil }
            let count = Int(sqlite3_column_bytes(handle, column))
            guard count <= maxPayloadBytes else { return nil }
            let data = Data(bytes: bytes, count: count)
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }
}
