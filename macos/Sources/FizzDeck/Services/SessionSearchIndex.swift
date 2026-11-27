import Foundation
import SQLite3

struct SessionSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let projectPath: String
    let projectName: String
    let sessionID: String
    let sessionStableID: String
    let tool: String
    let primaryIntent: String
    let lastUser: String?
    let lastError: String?
    let touchedFilesText: String
    let modified: Date
    let endedWithError: Bool
    let matchedSnippet: String?
}

struct SessionSearchDocument: Sendable, Equatable {
    let docKey: String
    let projectPath: String
    let projectName: String
    let sessionID: String
    let sessionStableID: String
    let tool: String
    let primaryIntent: String
    let lastUser: String
    let aiSummary: String
    let lastError: String
    let touchedFilesText: String
    let searchBody: String
    let modifiedTimestamp: TimeInterval
    let endedWithError: Bool

    init(
        project: RepoProject,
        session: SessionRecord,
        aiSummaryHeadline: String? = nil
    ) {
        let intentRaw = session.primaryIntent ?? "\(HomeDashboardModel.toolTitle(session.tool)) 会话"
        let cleanIntent = SecretRedactor.redact(String(intentRaw.prefix(400))).text
        let cleanLastUser = SecretRedactor.redact(String((session.lastUser ?? "").prefix(400))).text
        let cleanAI = SecretRedactor.redact(String((aiSummaryHeadline ?? "").prefix(300))).text
        let cleanError = SecretRedactor.redact(String((session.lastError ?? "").prefix(300))).text
        let cleanFiles = session.touchedFiles.prefix(40).map {
            let name = URL(fileURLWithPath: $0).lastPathComponent
            let redacted = SecretRedactor.redact($0).text
            return name == redacted ? name : "\(name) \(redacted)"
        }.joined(separator: " ")

        let toolTitle = HomeDashboardModel.toolTitle(session.tool)

        self.docKey = "\(PathTools.normalize(project.path))::\(session.stableID)"
        self.projectPath = project.path
        self.projectName = project.displayName
        self.sessionID = session.id
        self.sessionStableID = session.stableID
        self.tool = session.tool
        self.primaryIntent = cleanIntent
        self.lastUser = cleanLastUser
        self.aiSummary = cleanAI
        self.lastError = cleanError
        self.touchedFilesText = cleanFiles
        self.searchBody = [
            project.displayName,
            toolTitle,
            session.tool,
            cleanIntent,
            cleanLastUser,
            cleanAI,
            cleanError,
            cleanFiles,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .lowercased()
        self.modifiedTimestamp = session.modified.timeIntervalSince1970
        self.endedWithError = session.endedWithError
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor SessionSearchIndex {
    static let shared = SessionSearchIndex()

    private let databaseURL: URL
    private var initializedSchema = false
    private var ftsAvailable = true

    init(databaseURL: URL = AppPaths.sessionSearchDBFile) {
        self.databaseURL = databaseURL
    }

    func rebuild(
        from projects: [RepoProject],
        aiHeadlines: [String: String] = [:]
    ) {
        var documents: [SessionSearchDocument] = []
        for project in projects {
            for session in project.sessions.recentSessions where session.kind == .conversation {
                documents.append(
                    SessionSearchDocument(
                        project: project,
                        session: session,
                        aiSummaryHeadline: aiHeadlines[session.stableID]
                    )
                )
            }
        }
        rebuild(documents: documents)
    }

    func rebuild(documents: [SessionSearchDocument]) {
        guard let db = openDatabase() else { return }
        defer { sqlite3_close(db) }

        guard ensureSchema(db: db) else { return }
        guard exec(db, "BEGIN IMMEDIATE;") else { return }

        var committed = false
        defer {
            if !committed {
                _ = exec(db, "ROLLBACK;")
            }
        }

        guard exec(db, "DELETE FROM sessions_meta;") else { return }
        if ftsAvailable {
            _ = exec(db, "DELETE FROM sessions_fts;")
        }

        let insertMetaSQL = """
        INSERT OR REPLACE INTO sessions_meta (
            doc_key, project_path, project_name, session_id, session_stable_id,
            tool, primary_intent, last_user, ai_summary, last_error,
            touched_files, search_body, modified, ended_with_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var metaStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertMetaSQL, -1, &metaStmt, nil) == SQLITE_OK,
              let metaStmt else {
            return
        }
        defer { sqlite3_finalize(metaStmt) }

        var ftsStmt: OpaquePointer?
        if ftsAvailable {
            let insertFTSSQL = """
            INSERT INTO sessions_fts (
                doc_key, project_name, primary_intent, last_user, ai_summary, last_error, touched_files
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(db, insertFTSSQL, -1, &ftsStmt, nil) != SQLITE_OK {
                ftsStmt = nil
            }
        }
        defer {
            if let ftsStmt { sqlite3_finalize(ftsStmt) }
        }

        for doc in documents {
            sqlite3_reset(metaStmt)
            sqlite3_clear_bindings(metaStmt)
            bindText(metaStmt, index: 1, value: doc.docKey)
            bindText(metaStmt, index: 2, value: doc.projectPath)
            bindText(metaStmt, index: 3, value: doc.projectName)
            bindText(metaStmt, index: 4, value: doc.sessionID)
            bindText(metaStmt, index: 5, value: doc.sessionStableID)
            bindText(metaStmt, index: 6, value: doc.tool)
            bindText(metaStmt, index: 7, value: doc.primaryIntent)
            bindText(metaStmt, index: 8, value: doc.lastUser)
            bindText(metaStmt, index: 9, value: doc.aiSummary)
            bindText(metaStmt, index: 10, value: doc.lastError)
            bindText(metaStmt, index: 11, value: doc.touchedFilesText)
            bindText(metaStmt, index: 12, value: doc.searchBody)
            sqlite3_bind_double(metaStmt, 13, doc.modifiedTimestamp)
            sqlite3_bind_int(metaStmt, 14, doc.endedWithError ? 1 : 0)
            guard sqlite3_step(metaStmt) == SQLITE_DONE else { return }

            if let ftsStmt {
                sqlite3_reset(ftsStmt)
                sqlite3_clear_bindings(ftsStmt)
                bindText(ftsStmt, index: 1, value: doc.docKey)
                bindText(ftsStmt, index: 2, value: doc.projectName)
                bindText(ftsStmt, index: 3, value: doc.primaryIntent)
                bindText(ftsStmt, index: 4, value: doc.lastUser)
                bindText(ftsStmt, index: 5, value: doc.aiSummary)
                bindText(ftsStmt, index: 6, value: doc.lastError)
                bindText(ftsStmt, index: 7, value: doc.touchedFilesText)
                _ = sqlite3_step(ftsStmt)
            }
        }

        if exec(db, "COMMIT;") {
            committed = true
        }
    }

    func search(
        query: String,
        toolFilter: String? = nil,
        errorOnly: Bool = false,
        limit: Int = 40
    ) -> [SessionSearchResult] {
        let terms = Self.tokenizeQuery(query)
        guard !terms.isEmpty else { return [] }

        guard let db = openDatabase() else { return [] }
        defer { sqlite3_close(db) }
        guard ensureSchema(db: db) else { return [] }

        let canUseTrigram = ftsAvailable && terms.allSatisfy { $0.count >= 3 }
        if canUseTrigram {
            let ftsResults = queryFTS(
                db: db,
                terms: terms,
                toolFilter: toolFilter,
                errorOnly: errorOnly,
                limit: limit
            )
            if !ftsResults.isEmpty {
                return ftsResults
            }
        }

        return queryLike(
            db: db,
            terms: terms,
            toolFilter: toolFilter,
            errorOnly: errorOnly,
            limit: limit
        )
    }

    static func inMemorySearch(
        projects: [RepoProject],
        query: String,
        aiHeadlines: [String: String] = [:],
        toolFilter: String? = nil,
        errorOnly: Bool = false,
        limit: Int = 40
    ) -> [SessionSearchResult] {
        let terms = tokenizeQuery(query).map { $0.lowercased() }
        guard !terms.isEmpty else { return [] }

        var matches: [SessionSearchResult] = []
        for project in projects {
            for session in project.sessions.recentSessions where session.kind == .conversation {
                if let toolFilter, !toolFilter.isEmpty, session.tool != toolFilter {
                    continue
                }
                if errorOnly, !session.endedWithError {
                    continue
                }
                let doc = SessionSearchDocument(
                    project: project,
                    session: session,
                    aiSummaryHeadline: aiHeadlines[session.stableID]
                )
                guard terms.allSatisfy({ doc.searchBody.contains($0) }) else {
                    continue
                }
                let snippet = makeSnippet(
                    queryTerms: terms,
                    primaryIntent: doc.primaryIntent,
                    lastUser: doc.lastUser,
                    aiSummary: doc.aiSummary,
                    lastError: doc.lastError,
                    touchedFiles: doc.touchedFilesText
                )
                matches.append(
                    SessionSearchResult(
                        id: doc.docKey,
                        projectPath: doc.projectPath,
                        projectName: doc.projectName,
                        sessionID: doc.sessionID,
                        sessionStableID: doc.sessionStableID,
                        tool: doc.tool,
                        primaryIntent: doc.primaryIntent,
                        lastUser: doc.lastUser.isEmpty ? nil : doc.lastUser,
                        lastError: doc.lastError.isEmpty ? nil : doc.lastError,
                        touchedFilesText: doc.touchedFilesText,
                        modified: Date(timeIntervalSince1970: doc.modifiedTimestamp),
                        endedWithError: doc.endedWithError,
                        matchedSnippet: snippet
                    )
                )
            }
        }

        return matches
            .sorted { $0.modified > $1.modified }
            .prefix(max(1, limit))
            .map { $0 }
    }

    static func tokenizeQuery(_ raw: String) -> [String] {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func makeSnippet(
        queryTerms: [String],
        primaryIntent: String,
        lastUser: String,
        aiSummary: String,
        lastError: String,
        touchedFiles: String
    ) -> String? {
        let lowerTerms = queryTerms.map { $0.lowercased() }
        if !lastError.isEmpty, lowerTerms.contains(where: { lastError.lowercased().contains($0) }) {
            return "命中报错：\(String(lastError.prefix(70)))"
        }
        if !aiSummary.isEmpty, lowerTerms.contains(where: { aiSummary.lowercased().contains($0) }) {
            return "✦ \(String(aiSummary.prefix(70)))"
        }
        if !touchedFiles.isEmpty, lowerTerms.contains(where: { touchedFiles.lowercased().contains($0) }) {
            let fileTokens = touchedFiles
                .split(separator: " ")
                .map(String.init)
                .filter { token in lowerTerms.contains { token.lowercased().contains($0) } }
            if let first = fileTokens.first {
                return "命中文件：\(URL(fileURLWithPath: first).lastPathComponent)"
            }
        }
        if !lastUser.isEmpty,
           lastUser != primaryIntent,
           lowerTerms.contains(where: { lastUser.lowercased().contains($0) }) {
            return "对话提及：\(String(lastUser.prefix(70)))"
        }
        return nil
    }

    private func queryFTS(
        db: OpaquePointer,
        terms: [String],
        toolFilter: String?,
        errorOnly: Bool,
        limit: Int
    ) -> [SessionSearchResult] {
        let matchExpression = terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " ")

        var filters = ["sessions_fts MATCH ?"]
        if let toolFilter, !toolFilter.isEmpty {
            filters.append("m.tool = ?")
        }
        if errorOnly {
            filters.append("m.ended_with_error = 1")
        }

        let sql = """
        SELECT
            m.doc_key, m.project_path, m.project_name, m.session_id, m.session_stable_id,
            m.tool, m.primary_intent, m.last_user, m.ai_summary, m.last_error,
            m.touched_files, m.modified, m.ended_with_error
        FROM sessions_fts
        JOIN sessions_meta m ON m.doc_key = sessions_fts.doc_key
        WHERE \(filters.joined(separator: " AND "))
        ORDER BY bm25(sessions_fts), m.modified DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        bindText(stmt, index: bindIndex, value: matchExpression)
        bindIndex += 1
        if let toolFilter, !toolFilter.isEmpty {
            bindText(stmt, index: bindIndex, value: toolFilter)
            bindIndex += 1
        }
        sqlite3_bind_int(stmt, bindIndex, Int32(max(1, limit)))

        return collectResults(stmt: stmt, queryTerms: terms)
    }

    private func queryLike(
        db: OpaquePointer,
        terms: [String],
        toolFilter: String?,
        errorOnly: Bool,
        limit: Int
    ) -> [SessionSearchResult] {
        var clauses: [String] = []
        var patterns: [String] = []
        for term in terms {
            clauses.append("search_body LIKE ? ESCAPE '\\'")
            patterns.append("%\(Self.escapeLike(term.lowercased()))%")
        }
        if let toolFilter, !toolFilter.isEmpty {
            clauses.append("tool = ?")
        }
        if errorOnly {
            clauses.append("ended_with_error = 1")
        }

        let sql = """
        SELECT
            doc_key, project_path, project_name, session_id, session_stable_id,
            tool, primary_intent, last_user, ai_summary, last_error,
            touched_files, modified, ended_with_error
        FROM sessions_meta
        WHERE \(clauses.joined(separator: " AND "))
        ORDER BY modified DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        for pattern in patterns {
            bindText(stmt, index: bindIndex, value: pattern)
            bindIndex += 1
        }
        if let toolFilter, !toolFilter.isEmpty {
            bindText(stmt, index: bindIndex, value: toolFilter)
            bindIndex += 1
        }
        sqlite3_bind_int(stmt, bindIndex, Int32(max(1, limit)))

        return collectResults(stmt: stmt, queryTerms: terms)
    }

    private func collectResults(stmt: OpaquePointer, queryTerms: [String]) -> [SessionSearchResult] {
        var results: [SessionSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let docKey = columnText(stmt, index: 0)
            let projectPath = columnText(stmt, index: 1)
            let projectName = columnText(stmt, index: 2)
            let sessionID = columnText(stmt, index: 3)
            let sessionStableID = columnText(stmt, index: 4)
            let tool = columnText(stmt, index: 5)
            let primaryIntent = columnText(stmt, index: 6)
            let lastUser = columnText(stmt, index: 7)
            let aiSummary = columnText(stmt, index: 8)
            let lastError = columnText(stmt, index: 9)
            let touchedFiles = columnText(stmt, index: 10)
            let modified = sqlite3_column_double(stmt, 11)
            let endedWithError = sqlite3_column_int(stmt, 12) != 0

            let snippet = Self.makeSnippet(
                queryTerms: queryTerms,
                primaryIntent: primaryIntent,
                lastUser: lastUser,
                aiSummary: aiSummary,
                lastError: lastError,
                touchedFiles: touchedFiles
            )
            results.append(
                SessionSearchResult(
                    id: docKey,
                    projectPath: projectPath,
                    projectName: projectName,
                    sessionID: sessionID,
                    sessionStableID: sessionStableID,
                    tool: tool,
                    primaryIntent: primaryIntent,
                    lastUser: lastUser.isEmpty ? nil : lastUser,
                    lastError: lastError.isEmpty ? nil : lastError,
                    touchedFilesText: touchedFiles,
                    modified: Date(timeIntervalSince1970: modified),
                    endedWithError: endedWithError,
                    matchedSnippet: snippet
                )
            )
        }
        return results
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func openDatabase() -> OpaquePointer? {
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        _ = exec(db, "PRAGMA journal_mode = WAL;")
        _ = exec(db, "PRAGMA busy_timeout = 2000;")
        return db
    }

    private func ensureSchema(db: OpaquePointer) -> Bool {
        if initializedSchema { return true }

        let metaTableSQL = """
        CREATE TABLE IF NOT EXISTS sessions_meta (
            doc_key TEXT PRIMARY KEY,
            project_path TEXT NOT NULL,
            project_name TEXT NOT NULL,
            session_id TEXT NOT NULL,
            session_stable_id TEXT NOT NULL,
            tool TEXT NOT NULL,
            primary_intent TEXT NOT NULL,
            last_user TEXT NOT NULL,
            ai_summary TEXT NOT NULL,
            last_error TEXT NOT NULL,
            touched_files TEXT NOT NULL,
            search_body TEXT NOT NULL,
            modified REAL NOT NULL,
            ended_with_error INTEGER NOT NULL
        );
        """
        guard exec(db, metaTableSQL) else { return false }

        let ftsTableSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS sessions_fts USING fts5(
            doc_key UNINDEXED,
            project_name,
            primary_intent,
            last_user,
            ai_summary,
            last_error,
            touched_files,
            tokenize='trigram'
        );
        """
        ftsAvailable = exec(db, ftsTableSQL)
        initializedSchema = true
        return true
    }

    @discardableResult
    private func exec(_ db: OpaquePointer?, _ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bindText(_ stmt: OpaquePointer, index: Int32, value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func columnText(_ stmt: OpaquePointer, index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }
}
