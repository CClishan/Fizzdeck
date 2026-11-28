import Foundation
import SQLite3
import XCTest
@testable import FizzDeck

final class OpenCodeSessionReaderTests: XCTestCase {
    func testDefaultDatabaseFeedsProjectCountsAndIncrementalChineseSearch() async throws {
        let fixture = try Fixture(useDefaultLocation: true)
        let home = fixture.folder
        let directory = home.appendingPathComponent("计费项目", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try fixture.session("ses_main", directory: directory.path)
        try fixture.message("msg_first", data: #"{"role":"user"}"#)
        try fixture.part("prt_first", "msg_first", #"{"type":"text","text":"核对费用统计"}"#)
        try fixture.message("msg_assistant", data: #"{"role":"assistant"}"#, offset: 100)
        try fixture.tool("prt_edit", name: "edit", input: ["filePath": "Sources/Cost.swift"])

        let cache = home.appendingPathComponent("session-cache.json")
        let initial = SessionIndex.build(homeDirectory: home, cacheFile: cache)
        XCTAssertEqual(initial.map(\.stableID), ["opencode:ses_main"])
        let cwdMap = SessionIndex.buildLightweightCwdMap(homeDirectory: home, cacheFile: cache)
        let evidence = ToolEvidenceIndex.build(homeDirectory: home, sessionCwdMap: cwdMap)
        let projects = await RepositoryScanner.scanFast(paths: [directory.path], meta: [:], evidenceIndex: evidence)
        var project = try XCTUnwrap(projects.first)
        XCTAssertTrue(project.detectedTools.contains(.opencode))
        project.sessions = SessionIndex.summary(for: directory, in: initial)
        XCTAssertEqual(project.sessions.byTool.first?.sessionCount, 1)

        let search = SessionSearchIndex(databaseURL: home.appendingPathComponent("search.sqlite"))
        await search.rebuild(from: [project])
        let first = await search.search(query: "费用统计")
        XCTAssertEqual(first.map(\.sessionStableID), ["opencode:ses_main"])

        try fixture.message("msg_followup", data: #"{"role":"user"}"#, offset: 200)
        try fixture.part("prt_followup", "msg_followup", #"{"type":"text","text":"覆盖自然日边界"}"#)
        let updated = SessionIndex.build(homeDirectory: home, cacheFile: cache)
        XCTAssertEqual(updated.first?.lastUser, "覆盖自然日边界")
        project.sessions = SessionIndex.summary(for: directory, in: updated)
        await search.rebuild(from: [project])
        let added = await search.search(query: "自然日边界", toolFilter: "opencode")
        let byFile = await search.sessions(touchingFile: "Sources/Cost.swift", projectPath: project.path)
        XCTAssertEqual(added.map(\.sessionStableID), ["opencode:ses_main"])
        XCTAssertEqual(byFile.map(\.sessionStableID), ["opencode:ses_main"])
    }

    func testReadsOrderedUTF8UserTurnsAndCompletedProjectEdits() throws {
        let fixture = try Fixture()
        let project = fixture.folder.appendingPathComponent("项目 # %", isDirectory: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
        let alias = fixture.folder.appendingPathComponent("项目入口", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        let localURL = alias.absoluteString.replacingOccurrences(of: "file:///", with: "file://localhost/")
        XCTAssertEqual(OpenCodeSessionReader.database(in: fixture.folder).path, fixture.folder.path + "/.local/share/opencode/opencode.db")

        try fixture.session("ses_main", directory: localURL)
        try fixture.message("msg_a_followup", data: #"{"role":"user"}"#, offset: 200)
        try fixture.message("msg_z_first", data: #"{"role":"user"}"#, offset: 100)
        try fixture.message("msg_assistant", data: #"{"role":"assistant","modelID":"example-model"}"#, offset: 150)
        try fixture.part("prt_01", "msg_z_first", #"{"type":"text","text":" 修复登录 "}"#)
        try fixture.part("prt_00", "msg_z_first", #"{"type":"text","text":"自动上下文","synthetic":true}"#)
        try fixture.part("prt_02", "msg_z_first", #"{"type":"text","text":"同时调整提示"}"#)
        try fixture.part("prt_03", "msg_z_first", #"{"type":"text","text":"已忽略","ignored":true}"#)
        try fixture.part("prt_04", "msg_a_followup", #"{"type":"file","url":"file:///tmp/context.txt"}"#)
        try fixture.part("prt_05", "msg_a_followup", #"{"type":"text","text":"补回归测试 🧪"}"#)
        try fixture.part("prt_06", "msg_assistant", #"{"type":"text","text":"不是用户正文"}"#)
        try fixture.part("prt_07", "msg_assistant", "{invalid JSON")
        try fixture.tool("prt_08", name: "edit", metadata: ["filediff": ["file": alias.path + "/src/入口.swift"]])
        try fixture.tool("prt_09", name: "write", input: ["filePath": "./src/../src/入口.swift"])
        try fixture.tool("prt_10", name: "write", metadata: ["filepath": project.path + "/src/新文件.swift"])
        try fixture.tool("prt_11", name: "apply_patch", metadata: ["files": [
            ["filePath": project.path + "/旧名.swift", "movePath": project.path + "/新名.swift"],
        ]])
        try fixture.tool("prt_12", name: "read", input: ["filePath": "read-only.md"])
        try fixture.tool("prt_13", name: "edit", status: "error", input: ["filePath": "failed.md"])
        try fixture.tool("prt_14", name: "write", status: "running", input: ["filePath": "pending.md"])
        try fixture.tool("prt_15", name: "write", input: ["filePath": "../outside.md"])
        try fixture.tool("prt_16", name: "write", input: ["filePath": "file://remote/repo/unsafe.md"])

        let before = try sourceState(fixture.folder)
        let snapshots = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database))
        let record = try XCTUnwrap(snapshots["ses_main"]?.record)
        XCTAssertEqual(record.stableID, "opencode:ses_main")
        XCTAssertEqual(record.cwd, PathTools.canonical(project.path))
        XCTAssertEqual(record.firstUser, "修复登录\n同时调整提示")
        XCTAssertEqual(record.lastUser, "补回归测试 🧪")
        XCTAssertEqual(record.turnCount, 2)
        XCTAssertEqual(record.startedAt, Date(timeIntervalSince1970: Double(Fixture.created) / 1_000))
        XCTAssertEqual(record.modified, Date(timeIntervalSince1970: Double(Fixture.updated) / 1_000))
        XCTAssertEqual(record.durationMinutes, 1)
        XCTAssertEqual(record.model, "example-model")
        XCTAssertEqual(record.touchedFiles, ["src/入口.swift", "src/新文件.swift", "旧名.swift", "新名.swift"])
        XCTAssertNil(record.usage)
        XCTAssertNil(record.costUSD)
        XCTAssertEqual(try sourceState(fixture.folder), before)
    }

    func testSkipsChildSessionsInvalidDirectoriesAndSessionsWithoutUserText() throws {
        let fixture = try Fixture()
        XCTAssertEqual(OpenCodeSessionReader.read(database: fixture.database)?.count, 0)
        try fixture.session("ses_empty")
        try fixture.session("ses_child", parent: "ses_empty")
        try fixture.session("ses_remote", directory: "file://remote/private/project")
        try fixture.session("ses_relative", directory: "./project")
        try fixture.session("ses_encodedNul", directory: "file:///private/project%00bad")
        try fixture.session("ses_not_user")
        try fixture.session("ses_no_text")

        for id in ["child", "remote", "relative", "encodedNul"] {
            try fixture.message("msg_\(id)", session: "ses_\(id)", data: #"{"role":"user"}"#)
            try fixture.part("prt_\(id)", "msg_\(id)", #"{"type":"text","text":"不应出现"}"#, session: "ses_\(id)")
        }
        try fixture.message("msg_broken", session: "ses_not_user", data: #"{"role": "#)
        try fixture.part("prt_broken", "msg_broken", #"{"type":"text","text":"伪正文"}"#, session: "ses_not_user")
        try fixture.message("msg_file", session: "ses_no_text", data: #"{"role":"user"}"#)
        try fixture.part("prt_file", "msg_file", #"{"type":"file","url":"file:///tmp/input.txt"}"#, session: "ses_no_text")
        try fixture.part("prt_fake", "msg_file", #"{"type":"text","text":"合成","synthetic":true}"#, session: "ses_no_text")
        try fixture.part("prt_spaces", "msg_file", #"{"type":"text","text":"  \n\t  "}"#, session: "ses_no_text")
        // This part cannot lend a turn to a message from a different session.
        try fixture.part("prt_mismatch", "msg_file", #"{"type":"text","text":"不同会话"}"#, session: "ses_empty")

        let snapshots = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database))
        XCTAssertEqual(Set(snapshots.keys), ["ses_empty", "ses_not_user", "ses_no_text"])
        XCTAssertTrue(snapshots.values.allSatisfy { $0.record == nil })

        let corrupt = fixture.folder.appendingPathComponent("corrupt.db")
        XCTAssertNil(OpenCodeSessionReader.read(database: corrupt, cached: snapshots))
        try Data("not a SQLite database".utf8).write(to: corrupt)
        let before = try sourceState(fixture.folder)
        XCTAssertNil(OpenCodeSessionReader.read(database: corrupt, cached: snapshots))
        XCTAssertEqual(try sourceState(fixture.folder), before)
    }

    func testRevisionReusesUnchangedSnapshotsAndRefreshesChildRowsWithoutSessionTouch() throws {
        let fixture = try Fixture()
        try fixture.session("ses_main")
        try fixture.session("ses_unchanged")
        try fixture.session("ses_empty")
        try fixture.message("msg_first", data: #"{"role":"user"}"#)
        try fixture.part("prt_first", "msg_first", #"{"type":"text","text":"第一轮"}"#)
        try fixture.message("msg_unchanged", session: "ses_unchanged", data: #"{"role":"user"}"#)
        try fixture.part("prt_unchanged", "msg_unchanged", #"{"type":"text","text":"未变化"}"#, session: "ses_unchanged")

        var cached = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database))
        let unchanged = try XCTUnwrap(cached["ses_unchanged"])
        var cachedRecord = try XCTUnwrap(unchanged.record)
        cachedRecord.lastUser = "cache sentinel"
        cached["ses_unchanged"] = .init(revision: unchanged.revision, record: cachedRecord)
        XCTAssertNil(cached["ses_empty"]?.record)

        try fixture.message("msg_second", data: #"{"role":"user"}"#, offset: 1)
        try fixture.part("prt_second", "msg_second", #"{"type":"text","text":"第二轮"}"#)
        try fixture.message("msg_later", session: "ses_empty", data: #"{"role":"user"}"#)
        try fixture.part("prt_later", "msg_later", #"{"type":"text","text":"首次输入"}"#, session: "ses_empty")
        let appended = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database, cached: cached))
        XCTAssertEqual(appended["ses_unchanged"]?.record, cachedRecord)
        XCTAssertNotEqual(appended["ses_main"]?.revision, cached["ses_main"]?.revision)
        XCTAssertEqual(appended["ses_main"]?.record?.modified, cached["ses_main"]?.record?.modified)
        XCTAssertEqual(appended["ses_main"]?.record?.lastUser, "第二轮")
        XCTAssertEqual(appended["ses_empty"]?.record?.lastUser, "首次输入")

        // Same row count and byte count; only part.time_updated changes.
        try fixture.exec(#"UPDATE part SET time_updated = time_updated + 1, data = '{"type":"text","text":"第三轮"}' WHERE id = 'prt_second'"#)
        let edited = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database, cached: appended))
        XCTAssertNotEqual(edited["ses_main"]?.revision, appended["ses_main"]?.revision)
        XCTAssertEqual(edited["ses_main"]?.record?.lastUser, "第三轮")

        // A session can have a new revision even if its transcript did not change.
        try fixture.exec("UPDATE session SET time_updated = time_updated + 7 WHERE id = 'ses_main'; DELETE FROM session WHERE id = 'ses_empty';")
        let touched = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database, cached: edited))
        XCTAssertNotEqual(touched["ses_main"]?.revision, edited["ses_main"]?.revision)
        XCTAssertEqual(touched["ses_main"]?.record?.modified, Date(timeIntervalSince1970: Double(Fixture.updated + 7) / 1_000))
        XCTAssertNil(touched["ses_empty"])
    }

    func testRedactsPromptsAndOnlyReportsExplicitAssistantFailures() throws {
        let fixture = try Fixture()
        let secret = String(repeating: "z", count: 24)
        try fixture.session("ses_main")
        try fixture.message("msg_user", data: #"{"role":"user"}"#)
        try fixture.part("prt_user", "msg_user", #"{"type":"text","text":"配置 FIZZ_TEST_TOKEN=\#(secret)"}"#)
        try fixture.message("msg_failure", data: #"{"role":"assistant","finish":"error","error":{"name":"APIError","data":{"message":"请求失败 Bearer \#(secret)\n不展示诊断细节","isRetryable":false}}}"#, offset: 1)

        let failed = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database)?["ses_main"]?.record)
        XCTAssertEqual(failed.firstUser, "配置 FIZZ_TEST_TOKEN=[已脱敏]")
        XCTAssertEqual(failed.lastUser, failed.firstUser)
        XCTAssertEqual(failed.lastError, "请求失败 Bearer [已脱敏]")
        XCTAssertTrue(failed.endedWithError)

        try fixture.message("msg_next", data: #"{"role":"user"}"#, offset: 2)
        try fixture.part("prt_next", "msg_next", #"{"type":"text","text":"再试一次"}"#)
        try fixture.message("msg_aborted", data: #"{"role":"assistant","error":{"name":"MessageAbortedError","data":{"message":"用户取消"}}}"#, offset: 3)
        let aborted = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database)?["ses_main"]?.record)
        XCTAssertFalse(aborted.endedWithError)
        XCTAssertEqual(aborted.lastError, failed.lastError)

        try fixture.message("msg_length", data: #"{"role":"assistant","error":{"name":"MessageOutputLengthError","data":{}}}"#, offset: 4)
        let noMessage = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database)?["ses_main"]?.record)
        XCTAssertTrue(noMessage.endedWithError)
        XCTAssertNil(noMessage.lastError)
    }

    func testBoundsOversizedPayloadsAndTranscripts() throws {
        let fixture = try Fixture()
        try fixture.session("ses_main")
        try fixture.message("msg_main", data: #"{"role":"user"}"#)
        try fixture.part("prt_big", "msg_main", """
            {"type":"text","text":"\(String(repeating: "a", count: 270_000))"}
            """)
        try fixture.part("prt_small", "msg_main", #"{"type":"text","text":"可读取的输入"}"#)
        try fixture.session("ses_many")
        try fixture.message("msg_many", session: "ses_many", data: #"{"role":"user"}"#)
        try fixture.exec("""
            WITH RECURSIVE rows(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM rows WHERE n < 4_100)
            INSERT INTO part SELECT 'prt_many_' || n, 'msg_many', 'ses_many', \(Fixture.created), \(Fixture.created),
                '{"type":"text","text":"这段无法完整读完"}' FROM rows;
            """)
        let snapshots = try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database))
        XCTAssertEqual(snapshots["ses_main"]?.record?.lastUser, "可读取的输入")
        XCTAssertNil(snapshots["ses_many"]?.record)
    }

    func testReadsWALWithExistingSidecarsWithoutChangingSource() throws {
        let writer = try Fixture()
        try writer.exec("PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0;")
        try writer.session("ses_main")
        try writer.message("msg_first", data: #"{"role":"user"}"#)
        try writer.part("prt_first", "msg_first", #"{"type":"text","text":"已 checkpoint"}"#)
        try writer.exec("PRAGMA wal_checkpoint(TRUNCATE);")

        let checkpointed = try copyDatabase(writer.database, into: "checkpointed", suffixes: [""])
        let checkpointedBefore = try sourceState(checkpointed.deletingLastPathComponent())
        XCTAssertEqual(OpenCodeSessionReader.read(database: checkpointed)?["ses_main"]?.record?.lastUser, "已 checkpoint")
        XCTAssertEqual(try sourceState(checkpointed.deletingLastPathComponent()), checkpointedBefore)

        try writer.message("msg_new", data: #"{"role":"user"}"#, offset: 500)
        try writer.part("prt_new", "msg_new", #"{"type":"text","text":"只在 WAL 里的提交"}"#)
        // A different inode avoids SQLite sharing the fixture writer's SHM mapping in this process.
        let copy = try copyDatabase(writer.database, into: "with-sidecars", suffixes: ["", "-wal", "-shm"])
        let folder = copy.deletingLastPathComponent()
        let before = try sourceState(folder)
        XCTAssertEqual(OpenCodeSessionReader.read(database: copy)?["ses_main"]?.record?.lastUser, "只在 WAL 里的提交")
        XCTAssertEqual(try sourceState(folder), before)

        try FileManager.default.removeItem(atPath: copy.path + "-shm")
        let missingSHM = try sourceState(folder)
        XCTAssertNil(OpenCodeSessionReader.read(database: copy))
        XCTAssertEqual(try sourceState(folder), missingSHM)

        try FileManager.default.removeItem(atPath: copy.path + "-wal")
        try FileManager.default.copyItem(atPath: writer.database.path + "-shm", toPath: copy.path + "-shm")
        let missingWAL = try sourceState(folder)
        XCTAssertNil(OpenCodeSessionReader.read(database: copy))
        XCTAssertEqual(try sourceState(folder), missingWAL)
    }

    func testOpenCodeMetricsUseAssistantSpansAndTypedBashExit() throws {
        let fixture = try Fixture()
        try fixture.session("ses_main")
        try fixture.message("msg_user", data: #"{"role":"user"}"#)
        try fixture.part("prt_user", "msg_user", #"{"type":"text","text":"说明 cargo test，但先别运行"}"#)
        func assistant(_ id: String, start: Int64, end: Int64, finish: String) throws {
            try fixture.message(id, data: #"{"role":"assistant","parentID":"msg_user","finish":"\#(finish)","time":{"created":\#(Fixture.created + start),"completed":\#(Fixture.created + end)}}"#, offset: start)
        }
        try assistant("msg_assistant", start: 2_000, end: 6_000, finish: "tool-calls")
        try assistant("msg_parallel", start: 3_000, end: 8_000, finish: "tool-calls")
        try assistant("msg_final", start: 10_000, end: 12_500, finish: "stop")
        try fixture.tool("prt_echo", name: "bash", input: ["command": "echo 'cargo test'"], metadata: ["exit": 0])
        func read() throws -> SessionRecord {
            try XCTUnwrap(OpenCodeSessionReader.read(database: fixture.database)?["ses_main"]?.record)
        }
        let idle = try read()
        XCTAssertEqual(idle.agentTimeSeconds, 8) // 6 + 2.5 seconds, with overlap counted once.
        XCTAssertEqual(idle.turnCount, 1)
        XCTAssertEqual(idle.testResult, .notRun)

        try fixture.tool("prt_test", name: "bash", input: ["command": "cargo test"], metadata: ["exit": 1])
        XCTAssertEqual(try read().testResult, .failed)
        try fixture.tool("prt_test2", name: "bash", input: ["command": "npm exec -- vitest run"], metadata: ["exit": 0])
        XCTAssertEqual(try read().testResult, .passed)
        try fixture.tool("prt_test3", name: "bash", input: ["command": "make test"], metadata: ["timeout": true])
        XCTAssertNil(try read().testResult)
        XCTAssertEqual(try read().agentTimeSeconds, idle.agentTimeSeconds)
    }

    func testSessionIndexPreservesWave4OpenCodeSnapshotWhileDatabaseIsBusyAndDropsAfterDeletion() throws {
        let fixture = try Fixture(useDefaultLocation: true)
        try fixture.session("ses_main")
        try fixture.message("msg_user", data: #"{"role":"user"}"#)
        try fixture.part("prt_user", "msg_user", #"{"type":"text","text":"当前数据库内容"}"#)
        try fixture.message("msg_assistant", data: #"{"role":"assistant","parentID":"msg_user","finish":"stop","time":{"created":1780000001123,"completed":1780000004123}}"#, offset: 1_000)
        let cache = fixture.folder.appendingPathComponent("cache.json")
        let key = "opencode:\(PathTools.normalize(fixture.database.path))\0ses_main"
        try FileTools.writeJSON(["version": 5, "entries": [key: [
            "mtime": 0, "fileSize": 0, "databaseRevision": 123,
            "record": ["tool": "opencode", "id": "ses_main", "cwd": "/tmp/opencode-project",
                       "modified": 0, "lastUser": "旧版仍可显示"],
        ]]], to: cache)
        let before = try Data(contentsOf: cache)
        try fixture.exec("PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE")
        XCTAssertNil(OpenCodeSessionReader.read(database: fixture.database))
        let cached = try XCTUnwrap(SessionIndex.build(homeDirectory: fixture.folder, cacheFile: cache).first)
        XCTAssertEqual(cached.lastUser, "旧版仍可显示")
        XCTAssertNil(cached.agentTimeSeconds)
        XCTAssertEqual(try Data(contentsOf: cache), before)
        try fixture.exec("ROLLBACK")

        let refreshed = try XCTUnwrap(SessionIndex.build(homeDirectory: fixture.folder, cacheFile: cache).first)
        XCTAssertEqual(refreshed.lastUser, "当前数据库内容")
        XCTAssertEqual(refreshed.agentTimeSeconds, 3)
        XCTAssertEqual(refreshed.testResult, .notRun)
        XCTAssertNotEqual(try Data(contentsOf: cache), before)

        try FileManager.default.removeItem(at: fixture.database)
        XCTAssertTrue(SessionIndex.build(homeDirectory: fixture.folder, cacheFile: cache).isEmpty)
        XCTAssertNil(SessionIndex.buildLightweightCwdMap(homeDirectory: fixture.folder, cacheFile: cache)["opencode"])
    }

    private struct FileState: Equatable {
        let bytes: Data
        let modified: Date?
    }

    private func sourceState(_ folder: URL) throws -> [String: FileState] {
        var state: [String: FileState] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]) {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if values.isRegularFile == true {
                state[file.lastPathComponent] = try FileState(bytes: Data(contentsOf: file), modified: values.contentModificationDate)
            }
        }
        return state
    }

    private func copyDatabase(_ source: URL, into name: String, suffixes: [String]) throws -> URL {
        let folder = source.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        for suffix in suffixes {
            try FileManager.default.copyItem(atPath: source.path + suffix, toPath: destination.path + suffix)
        }
        return destination
    }

    private final class Fixture {
        static let created: Int64 = 1_780_000_000_123
        static let updated: Int64 = created + 60_017
        let folder: URL
        let database: URL
        private let handle: OpaquePointer

        init(useDefaultLocation: Bool = false) throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let database = useDefaultLocation ? OpenCodeSessionReader.database(in: folder) : folder.appendingPathComponent("OpenCode ? # %.db")
            try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
            var handle: OpaquePointer?
            guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
                  let handle else {
                sqlite3_close(handle)
                try? FileManager.default.removeItem(at: folder)
                throw CocoaError(.fileWriteUnknown)
            }
            self.folder = folder
            self.database = database
            self.handle = handle
            try exec("""
                CREATE TABLE session(id TEXT PRIMARY KEY, directory TEXT NOT NULL, parent_id TEXT,
                    time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
                CREATE TABLE message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
                    time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
                CREATE TABLE part(id TEXT PRIMARY KEY, message_id TEXT NOT NULL, session_id TEXT NOT NULL,
                    time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
                CREATE INDEX session_parent_idx ON session(parent_id);
                CREATE INDEX message_session_time_created_id_idx ON message(session_id, time_created, id);
                CREATE INDEX part_session_idx ON part(session_id);
                CREATE INDEX part_message_id_id_idx ON part(message_id, id);
                """)
        }

        deinit {
            sqlite3_close(handle)
            try? FileManager.default.removeItem(at: folder)
        }

        func exec(_ sql: String) throws {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "OpenCode fixture", code: Int(sqlite3_errcode(handle)), userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle)),
                ])
            }
        }

        func session(_ id: String, directory: String = "/tmp/opencode-project/./nested/..", parent: String? = nil) throws {
            try exec("INSERT INTO session VALUES (\(quote(id)), \(quote(directory)), \(parent.map(quote) ?? "NULL"), \(Self.created), \(Self.updated));")
        }

        func message(_ id: String, session: String = "ses_main", data: String, offset: Int64 = 0) throws {
            let time = Self.created + offset
            try exec("INSERT INTO message VALUES (\(quote(id)), \(quote(session)), \(time), \(time), \(quote(data)));")
        }

        func part(_ id: String, _ message: String, _ data: String, session: String = "ses_main") throws {
            try exec("INSERT INTO part VALUES (\(quote(id)), \(quote(message)), \(quote(session)), \(Self.created), \(Self.created), \(quote(data)));")
        }

        func tool(_ id: String, name: String, status: String = "completed", input: [String: Any] = [:], metadata: [String: Any] = [:]) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "type": "tool", "tool": name, "state": ["status": status, "input": input, "metadata": metadata],
            ])
            try part(id, "msg_assistant", String(decoding: data, as: UTF8.self))
        }

        private func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
        }
    }
}
