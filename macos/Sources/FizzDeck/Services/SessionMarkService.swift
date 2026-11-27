import Foundation

enum SessionMarkKind: String, Codable, Sendable, Hashable {
    case pureMark
    case gitSnapshot
}

struct SessionMark: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let projectPath: String
    let sessionID: String?
    let sessionStableID: String?
    let tool: String?
    let createdAt: Date
    var kind: SessionMarkKind
    let headSHA: String?
    let snapshotSHA: String?
    let changedFilesAtMark: [String]
    var pinned: Bool = false
    var label: String? = nil
    var isProtectionBaseline: Bool { label == SessionMarkService.baselineLabel && sessionID == nil }

    init(
        id: String = UUID().uuidString,
        projectPath: String,
        sessionID: String? = nil,
        sessionStableID: String? = nil,
        tool: String? = nil,
        createdAt: Date = Date(),
        kind: SessionMarkKind,
        headSHA: String? = nil,
        snapshotSHA: String? = nil,
        changedFilesAtMark: [String] = [],
        pinned: Bool = false,
        label: String? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.sessionID = sessionID
        self.sessionStableID = sessionStableID
        self.tool = tool
        self.createdAt = createdAt
        self.kind = kind
        self.headSHA = headSHA
        self.snapshotSHA = snapshotSHA
        self.changedFilesAtMark = changedFilesAtMark
        self.pinned = pinned
        self.label = label
    }
}

enum MarkPreferences {
    static let implicitMarksEnabledKey = "fizzdeck.marks.implicitEnabled"
    static let firstMarkToastShownKey = "fizzdeck.marks.firstToastShown"
    static let saveVersionToastDisabledKey = "fizzdeck.marks.saveVersionToastDisabled"

    static func implicitMarksEnabled(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: implicitMarksEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: implicitMarksEnabledKey)
    }

    static func setImplicitMarksEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: implicitMarksEnabledKey)
    }

    static func firstMarkToastShown(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: firstMarkToastShownKey)
    }

    static func setFirstMarkToastShown(_ shown: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(shown, forKey: firstMarkToastShownKey)
    }

    static func saveVersionToastDisabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: saveVersionToastDisabledKey)
    }

    static func setSaveVersionToastDisabled(_ disabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(disabled, forKey: saveVersionToastDisabledKey)
    }
}

enum MarkStore {
    private static let maxUnpinnedPerProject = 60

    static func load(from file: URL = AppPaths.marksFile) -> [SessionMark] {
        (try? read(from: file)) ?? []
    }

    private static func read(from file: URL) throws -> [SessionMark] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SessionMark].self, from: data)
    }

    static func save(_ marks: [SessionMark], to file: URL = AppPaths.marksFile) {
        try? write(marks, to: file)
    }

    private static func write(_ marks: [SessionMark], to file: URL) throws {
        try FileTools.manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marks).write(to: file, options: .atomic)
    }

    static func marks(for projectPath: String, in marks: [SessionMark]) -> [SessionMark] {
        let target = PathTools.normalize(projectPath)
        return marks
            .filter { PathTools.normalize($0.projectPath) == target }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func upsert(_ mark: SessionMark, in file: URL = AppPaths.marksFile) -> [SessionMark] {
        (try? upsertChecked(mark, in: file)) ?? load(from: file)
    }

    @discardableResult
    static func upsertChecked(_ mark: SessionMark, in file: URL) throws -> [SessionMark] {
        var all = try read(from: file)
        if let existing = all.firstIndex(where: { $0.id == mark.id }) {
            all[existing] = mark
        } else {
            all.append(mark)
        }
        let pruned = prune(all)
        try write(pruned, to: file)
        return pruned
    }

    private static func prune(_ marks: [SessionMark]) -> [SessionMark] {
        let grouped = Dictionary(grouping: marks) { PathTools.normalize($0.projectPath) }
        var kept: [SessionMark] = []
        for (_, projectMarks) in grouped {
            let pinned = projectMarks.filter(\.pinned)
            let unpinned = projectMarks
                .filter { !$0.pinned }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(maxUnpinnedPerProject)
            kept.append(contentsOf: pinned)
            kept.append(contentsOf: unpinned)
        }
        return kept.sorted { $0.createdAt > $1.createdAt }
    }
}

enum MarkFileChangeStatus: String, Sendable, Equatable {
    case modified
    case deleted
    case createdAfterMark
}

struct MarkFileChange: Identifiable, Sendable, Hashable {
    let path: String
    let status: MarkFileChangeStatus

    var id: String { path }
}

struct MarkDiffSummary: Sendable, Equatable {
    let mark: SessionMark
    let available: Bool
    let modifiedOrDeleted: [MarkFileChange]
    let createdAfterMark: [MarkFileChange]
}

struct MarkRestoreResult: Sendable, Equatable {
    let succeeded: Bool
    let message: String
    let restoredCount: Int
    let trashedCount: Int
    let preRestoreMark: SessionMark?
}

enum SessionMarkService {
    static let baselineLabel = "开启版本保护时的基线"
    static let maxFileBytes: Int64 = 5 * 1024 * 1024
    static let maxTrackedCount = 5_000
    private static let maxDirtyFilesStored = 50

    static let excludedDirectories: [String] = [
        "node_modules",
        ".next",
        "dist",
        "build",
        ".venv",
        "venv",
        ".build",
        "target",
        "Pods",
        ".turbo",
        ".cache",
        "DerivedData",
    ]

    static func protectionBaseline(for directory: URL, stagedGit: URL, gitignore: Data, tmpDir: URL) async -> SessionMark? {
        let id = UUID().uuidString
        guard let sha = await buildInvisibleCommit(in: directory, headSHA: nil, message: "fizzdeck baseline \(id)",
                                                  tmpDir: tmpDir, stagedGit: stagedGit, gitignore: gitignore) else { return nil }
        let mark = SessionMark(id: id, projectPath: PathTools.normalize(directory.path), kind: .gitSnapshot,
                               snapshotSHA: sha, pinned: true, label: baselineLabel)
        return await setPinned(true, mark: mark, in: stagedGit.deletingLastPathComponent()) ? mark : nil
    }

    static func createMark(
        for directory: URL,
        sessionID: String? = nil,
        sessionStableID: String? = nil,
        tool: String? = nil,
        label: String? = nil,
        allowGitSnapshot: Bool = true,
        tmpDir: URL = AppPaths.tmpDir
    ) async -> SessionMark {
        let markID = UUID().uuidString
        let projectPath = PathTools.normalize(directory.path)
        let now = Date()

        guard GitService.hasGit(directory) else {
            return SessionMark(
                id: markID,
                projectPath: projectPath,
                sessionID: sessionID,
                sessionStableID: sessionStableID,
                tool: tool,
                createdAt: now,
                kind: .pureMark,
                label: label
            )
        }

        async let headTask = currentHeadSHA(in: directory)
        async let dirtyTask = currentDirtyFiles(in: directory)
        let (headSHA, dirtyFiles) = await (headTask, dirtyTask)

        guard allowGitSnapshot else {
            return SessionMark(
                id: markID,
                projectPath: projectPath,
                sessionID: sessionID,
                sessionStableID: sessionStableID,
                tool: tool,
                createdAt: now,
                kind: .pureMark,
                headSHA: headSHA,
                changedFilesAtMark: dirtyFiles,
                label: label
            )
        }

        if let snapshotSHA = await buildInvisibleCommit(
            in: directory,
            headSHA: headSHA,
            message: "fizzdeck mark \(sessionID ?? markID)",
            tmpDir: tmpDir
        ) {
            return SessionMark(
                id: markID,
                projectPath: projectPath,
                sessionID: sessionID,
                sessionStableID: sessionStableID,
                tool: tool,
                createdAt: now,
                kind: .gitSnapshot,
                headSHA: headSHA,
                snapshotSHA: snapshotSHA,
                changedFilesAtMark: dirtyFiles,
                label: label
            )
        }

        return SessionMark(
            id: markID,
            projectPath: projectPath,
            sessionID: sessionID,
            sessionStableID: sessionStableID,
            tool: tool,
            createdAt: now,
            kind: .pureMark,
            headSHA: headSHA,
            changedFilesAtMark: dirtyFiles,
            label: label
        )
    }

    static func isAvailable(_ mark: SessionMark, in directory: URL) async -> Bool {
        guard mark.kind == .gitSnapshot, let sha = mark.snapshotSHA, !sha.isEmpty else {
            return false
        }
        guard let result = await Shell.run(
            "git",
            ["cat-file", "-e", "\(sha)^{commit}"],
            cwd: directory,
            timeout: 10
        ) else { return false }
        return result.succeeded
    }

    static func setPinned(_ pinned: Bool, mark: SessionMark, in directory: URL) async -> Bool {
        guard let sha = mark.snapshotSHA, !sha.isEmpty else { return false }
        let refName = "refs/fizzdeck/marks/\(mark.id)"
        let arguments = pinned
            ? ["update-ref", refName, sha]
            : ["update-ref", "-d", refName]
        guard let result = await Shell.run(
            "git",
            ["-c", "core.hooksPath=/dev/null"] + arguments,
            cwd: directory,
            timeout: 10
        ) else { return false }
        return result.succeeded
    }

    static func diffSummary(
        for mark: SessionMark,
        in directory: URL,
        tmpDir: URL = AppPaths.tmpDir
    ) async -> MarkDiffSummary {
        guard let sha = mark.snapshotSHA,
              await isAvailable(mark, in: directory)
        else {
            return MarkDiffSummary(
                mark: mark,
                available: false,
                modifiedOrDeleted: [],
                createdAfterMark: []
            )
        }

        return await withTemporaryWorktreeIndex(in: directory, tmpDir: tmpDir) { idxPath in
            guard let idxPath,
                  let diffOutput = await Shell.run(
                    "git",
                    ["diff", "--cached", "--no-renames", "--name-status", "-z", sha],
                    cwd: directory,
                    timeout: 20,
                    extraEnvironment: ["GIT_INDEX_FILE": idxPath]
                  ),
                  diffOutput.succeeded
            else {
                return MarkDiffSummary(
                    mark: mark,
                    available: true,
                    modifiedOrDeleted: [],
                    createdAfterMark: []
                )
            }

            let tokens = diffOutput.text
                .split(separator: "\0", omittingEmptySubsequences: false)
                .map(String.init)
            var modifiedOrDeleted: [MarkFileChange] = []
            var createdAfterMark: [MarkFileChange] = []
            let protected = FileTools.exists(directory.appendingPathComponent(ProtectionFiles.marker))

            var index = 0
            while index + 1 < tokens.count {
                let status = tokens[index]
                let path = tokens[index + 1]
                index += 2
                guard !status.isEmpty, !path.isEmpty else { continue }

                if status.hasPrefix("D") {
                    // A file may now be ignored, oversized or contain a credential. Its current bytes are not backed up.
                    if protected,
                       (try? FileTools.manager.attributesOfItem(atPath: directory.appendingPathComponent(path).path)) != nil { continue }
                    modifiedOrDeleted.append(MarkFileChange(path: path, status: .deleted))
                } else if status.hasPrefix("A") {
                    createdAfterMark.append(MarkFileChange(path: path, status: .createdAfterMark))
                } else {
                    modifiedOrDeleted.append(MarkFileChange(path: path, status: .modified))
                }
            }

            modifiedOrDeleted.sort { $0.path < $1.path }
            createdAfterMark.sort { $0.path < $1.path }

            return MarkDiffSummary(
                mark: mark,
                available: true,
                modifiedOrDeleted: modifiedOrDeleted,
                createdAfterMark: createdAfterMark
            )
        }
    }

    static func fileDiff(
        for mark: SessionMark,
        change: MarkFileChange,
        in directory: URL,
        tmpDir: URL = AppPaths.tmpDir
    ) async -> GitFileDiff {
        if change.status == .createdAfterMark {
            let gitChange = GitChange(
                path: change.path,
                originalPath: nil,
                indexStatus: "?",
                worktreeStatus: "?",
                untracked: true,
                conflicted: false
            )
            return await GitService.fileDiff(for: gitChange, in: directory)
        }

        guard let sha = mark.snapshotSHA,
              await isAvailable(mark, in: directory)
        else {
            return GitFileDiff(
                path: change.path,
                sections: [],
                additions: 0,
                deletions: 0,
                truncated: false,
                binary: false,
                note: "标记已过期，无法读取对比内容。"
            )
        }

        return await withTemporaryWorktreeIndex(in: directory, tmpDir: tmpDir) { idxPath in
            guard let idxPath,
                  let diffResult = await Shell.run(
                    "git",
                    ["--literal-pathspecs", "--no-pager", "diff", "--cached", "--no-color", sha, "--", change.path],
                    cwd: directory,
                    timeout: 15,
                    extraEnvironment: ["GIT_INDEX_FILE": idxPath]
                  )
            else {
                return GitFileDiff(
                    path: change.path,
                    sections: [],
                    additions: 0,
                    deletions: 0,
                    truncated: false,
                    binary: false,
                    note: "无法生成文件对比。"
                )
            }

            let raw = diffResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                return GitFileDiff(
                    path: change.path,
                    sections: [],
                    additions: 0,
                    deletions: 0,
                    truncated: false,
                    binary: false,
                    note: nil
                )
            }
            if raw.contains("Binary files ") || raw.contains("GIT binary patch") {
                return GitFileDiff(
                    path: change.path,
                    sections: [],
                    additions: 0,
                    deletions: 0,
                    truncated: false,
                    binary: true,
                    note: "二进制文件仅显示状态，不展开内容。"
                )
            }

            let parsed = GitService.parseUnifiedDiff(raw)
            let sectionTitle = change.status == .deleted ? "标记时的内容（后来被删除）" : "与标记时的对比"
            return GitFileDiff(
                path: change.path,
                sections: [GitDiffSection(id: "mark-diff", title: sectionTitle, lines: parsed.lines)],
                additions: parsed.additions,
                deletions: parsed.deletions,
                truncated: parsed.truncated,
                binary: false,
                note: nil
            )
        }
    }

    static func restore(
        mark: SessionMark,
        filesToRestore: [String],
        newlyCreatedToTrash: [String] = [],
        in directory: URL,
        marksFile: URL = AppPaths.marksFile,
        tmpDir: URL = AppPaths.tmpDir
    ) async -> MarkRestoreResult {
        guard let sha = mark.snapshotSHA,
              await isAvailable(mark, in: directory)
        else {
            return MarkRestoreResult(
                succeeded: false,
                message: "这个对话标记已过期（超过 14 天被 Git 清理），无法还原",
                restoredCount: 0,
                trashedCount: 0,
                preRestoreMark: nil
            )
        }

        let uniqueRestore = Array(Set(filesToRestore)).sorted()
        let uniqueTrash = Array(Set(newlyCreatedToTrash)).sorted()
        guard !uniqueRestore.isEmpty || !uniqueTrash.isEmpty else {
            return MarkRestoreResult(
                succeeded: false,
                message: "没有选择要还原的文件",
                restoredCount: 0,
                trashedCount: 0,
                preRestoreMark: nil
            )
        }

        let backupMark = await createMark(
            for: directory,
            label: "还原前自动备份",
            allowGitSnapshot: true,
            tmpDir: tmpDir
        )
        if FileTools.exists(directory.appendingPathComponent(ProtectionFiles.marker)) {
            guard let backupSHA = backupMark.snapshotSHA,
                  let tree = await Shell.run("git", ["ls-tree", "-rz", "--name-only", backupSHA], cwd: directory), tree.succeeded else {
                return MarkRestoreResult(succeeded: false, message: "无法核对还原前的备份，未修改文件。", restoredCount: 0, trashedCount: 0, preRestoreMark: nil)
            }
            let captured = Set(tree.text.split(separator: "\0").map(String.init))
            for path in uniqueRestore + uniqueTrash {
                let file = directory.appendingPathComponent(path)
                if (try? FileTools.manager.attributesOfItem(atPath: file.path)) != nil, !captured.contains(path) {
                    return MarkRestoreResult(succeeded: false, message: "所选文件已变化，无法安全备份。请重新查看差异。", restoredCount: 0, trashedCount: 0, preRestoreMark: nil)
                }
            }
        }
        guard backupMark.kind == .gitSnapshot, (try? MarkStore.upsertChecked(backupMark, in: marksFile)) != nil else {
            return MarkRestoreResult(succeeded: false, message: "无法保存还原前的备份，未修改文件。", restoredCount: 0,
                                     trashedCount: 0, preRestoreMark: nil)
        }

        var restoredCount = 0
        if !uniqueRestore.isEmpty {
            let args = ["--literal-pathspecs", "restore", "--source=\(sha)", "--worktree", "--"] + uniqueRestore
            guard let restoreResult = await Shell.run(
                "git",
                args,
                cwd: directory,
                timeout: 30,
                extraEnvironment: ["GIT_TERMINAL_PROMPT": "0"]
            ), restoreResult.succeeded else {
                return MarkRestoreResult(
                    succeeded: false,
                    message: "还原文件失败，请检查文件是否被其他程序占用",
                    restoredCount: 0,
                    trashedCount: 0,
                    preRestoreMark: backupMark
                )
            }
            restoredCount = uniqueRestore.count
        }

        var trashedCount = 0
        if !uniqueTrash.isEmpty {
            let rootURL = directory.resolvingSymlinksInPath().standardizedFileURL
            let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            for relPath in uniqueTrash {
                let candidate = rootURL.appendingPathComponent(relPath).standardizedFileURL
                guard candidate.path.hasPrefix(rootPrefix) else { continue }
                guard FileTools.exists(candidate) else { continue }
                do {
                    try FileTools.manager.trashItem(at: candidate, resultingItemURL: nil)
                    trashedCount += 1
                } catch {
                    return MarkRestoreResult(
                        succeeded: false,
                        message: "部分新建文件移入废纸篓失败：\(relPath)",
                        restoredCount: restoredCount,
                        trashedCount: trashedCount,
                        preRestoreMark: backupMark
                    )
                }
            }
        }

        let summary: String
        if restoredCount > 0 && trashedCount > 0 {
            summary = "已还原 \(restoredCount) 个文件，并将 \(trashedCount) 个新建文件移入废纸篓"
        } else if restoredCount > 0 {
            summary = "已还原 \(restoredCount) 个文件"
        } else {
            summary = "已将 \(trashedCount) 个新建文件移入废纸篓"
        }

        return MarkRestoreResult(
            succeeded: true,
            message: summary,
            restoredCount: restoredCount,
            trashedCount: trashedCount,
            preRestoreMark: backupMark
        )
    }

    // MARK: - Private Git Helpers

    private static func currentHeadSHA(in directory: URL) async -> String? {
        guard let output = await Shell.output(
            "git",
            ["rev-parse", "--verify", "HEAD"],
            cwd: directory,
            timeout: 10
        ), !output.isEmpty else {
            return nil
        }
        return output
    }

    private static func currentDirtyFiles(in directory: URL) async -> [String] {
        guard let result = await Shell.run(
            "git",
            ["status", "--porcelain=v1", "-uall"],
            cwd: directory,
            timeout: 15, extraEnvironment: ["GIT_OPTIONAL_LOCKS": "0"]
        ), result.succeeded else {
            return []
        }

        var files: [String] = []
        for line in result.text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count > 3 else { continue }
            let path = String(line.dropFirst(3))
            if !isExcludedPath(path) {
                files.append(path)
            }
            if files.count >= maxDirtyFilesStored { break }
        }
        return files
    }

    private static func buildInvisibleCommit(
        in directory: URL,
        headSHA: String?,
        message: String,
        tmpDir: URL, stagedGit: URL? = nil, gitignore: Data? = nil
    ) async -> String? {
        let objectRepo = stagedGit?.deletingLastPathComponent() ?? directory
        return await withTemporaryWorktreeIndex(in: directory, tmpDir: tmpDir, stagedGit: stagedGit, gitignore: gitignore) { idxPath in
            guard let idxPath else { return nil }
            guard let treeResult = await Shell.run(
                "git",
                ["write-tree"],
                cwd: objectRepo,
                timeout: 20,
                extraEnvironment: ["GIT_INDEX_FILE": idxPath]
            ), treeResult.succeeded else {
                return nil
            }
            let treeSHA = treeResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidSHA(treeSHA) else { return nil }

            var commitArgs = ["-c", "commit.gpgSign=false", "commit-tree", treeSHA]
            if let headSHA, !headSHA.isEmpty {
                commitArgs.append(contentsOf: ["-p", headSHA])
            }
            commitArgs.append(contentsOf: ["-m", message])

            let fallbackEnv = [
                "GIT_AUTHOR_NAME": "FizzDeck",
                "GIT_AUTHOR_EMAIL": "fizzdeck@local",
                "GIT_COMMITTER_NAME": "FizzDeck",
                "GIT_COMMITTER_EMAIL": "fizzdeck@local",
            ]
            guard let commitResult = await Shell.run(
                "git",
                commitArgs,
                cwd: objectRepo,
                timeout: 15,
                extraEnvironment: fallbackEnv
            ), commitResult.succeeded else {
                return nil
            }
            let sha = commitResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidSHA(sha) ? sha : nil
        }
    }

    private static func withTemporaryWorktreeIndex<T>(
        in directory: URL,
        tmpDir: URL,
        stagedGit: URL? = nil, gitignore: Data? = nil,
        _ body: (String?) async -> T
    ) async -> T {
        if stagedGit != nil || FileTools.exists(directory.appendingPathComponent(ProtectionFiles.marker)) {
            return await ProtectionFiles.withIndex(in: directory, gitDir: stagedGit ?? directory.appendingPathComponent(".git"),
                                                   tmpDir: tmpDir, gitignore: gitignore, body)
        }
        guard let candidateFiles = await candidatePaths(in: directory) else {
            return await body(nil)
        }
        if candidateFiles.count > maxTrackedCount {
            return await body(nil)
        }

        let oversized = oversizedCandidatePaths(candidateFiles, in: directory)

        do {
            try FileTools.manager.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return await body(nil)
        }

        let idxURL = tmpDir.appendingPathComponent("\(UUID().uuidString).index")
        defer { try? FileTools.manager.removeItem(at: idxURL) }

        if let realIndex = await realIndexURL(in: directory),
           FileTools.exists(realIndex) {
            try? FileTools.manager.copyItem(at: realIndex, to: idxURL)
        }

        var addArgs = ["add", "-A", "--", "."]
        for dir in excludedDirectories {
            addArgs.append(":(exclude)\(dir)")
            addArgs.append(":(glob,exclude)**/\(dir)/**")
        }
        for path in oversized.prefix(200) {
            addArgs.append(":(literal,exclude)\(path)")
        }

        guard let addResult = await Shell.run(
            "git",
            addArgs,
            cwd: directory,
            timeout: 30,
            extraEnvironment: [
                "GIT_INDEX_FILE": idxURL.path,
                "GIT_TERMINAL_PROMPT": "0",
            ]
        ), addResult.succeeded else {
            return await body(nil)
        }

        if !oversized.isEmpty {
            let rmArgs = ["rm", "--cached", "--ignore-unmatch", "-q", "--"] + Array(oversized.prefix(200))
            _ = await Shell.run(
                "git",
                rmArgs,
                cwd: directory,
                timeout: 15,
                extraEnvironment: ["GIT_INDEX_FILE": idxURL.path]
            )
        }

        return await body(idxURL.path)
    }

    private static func candidatePaths(in directory: URL) async -> [String]? {
        guard let result = await Shell.run(
            "git",
            ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd: directory,
            timeout: 20
        ), result.succeeded else {
            return nil
        }

        return result.text
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !isExcludedPath($0) }
    }

    private static func oversizedCandidatePaths(_ paths: [String], in directory: URL) -> [String] {
        paths.filter { relPath in
            let url = directory.appendingPathComponent(relPath)
            guard FileTools.exists(url) else { return false }
            return FileTools.fileSize(url) > maxFileBytes
        }
    }

    private static func realIndexURL(in directory: URL) async -> URL? {
        guard let raw = await Shell.output(
            "git",
            ["rev-parse", "--git-path", "index"],
            cwd: directory,
            timeout: 10
        ), !raw.isEmpty else {
            return nil
        }
        return raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : directory.appendingPathComponent(raw)
    }

    private static func isExcludedPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return components.contains { excludedDirectories.contains($0) }
    }

    private static func isValidSHA(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy { $0.isHexDigit }
    }
}
