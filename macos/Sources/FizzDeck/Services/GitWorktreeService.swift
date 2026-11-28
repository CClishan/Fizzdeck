import Darwin
import Foundation
import os

struct GitWorktree: Identifiable, Sendable, Hashable {
    let path: String
    fileprivate let objectID: String?
    let branch: String?
    let isMain: Bool
    let isDetached: Bool
    let isBare: Bool
    let isLocked: Bool
    let isPrunable: Bool

    var id: String { path }
    var head: String? { objectID.map { String($0.prefix(12)) } }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum GitWorktreeService {
    struct Overview: Sendable {
        let rows: [Row]
        let mainBranch: String?
    }

    struct Row: Identifiable, Sendable {
        let worktree: GitWorktree
        let changedCount: Int?
        let ahead: Int?
        let behind: Int?

        var id: String { worktree.id }
        var canManage: Bool { worktree.canManage }
    }

    struct DiscardConfirmation: Sendable {
        let changedCount: Int
        let ignoredCount: Int
        fileprivate let worktree: GitWorktree
        fileprivate let entries: String
        fileprivate let stamps: [FileStamp?]
        fileprivate let unused = OSAllocatedUnfairLock(initialState: true)
    }

    enum Failure: LocalizedError {
        case dirtyRemoval(DiscardConfirmation)
        case mergeConflict(mainPath: String, rollbackSucceeded: Bool)
        case blocked(String)
        case git(String)

        var errorDescription: String? {
            switch self {
            case .dirtyRemoval:
                FizzL10n.text("目录有未提交改动或被 Git 忽略的内容。确认丢弃后才能移除。", "This worktree has uncommitted or ignored files. Confirm that you want to discard them before removing it.")
            case let .mergeConflict(_, rollbackSucceeded):
                rollbackSucceeded
                    ? FizzL10n.text("这次合并遇到冲突，已用 Git 中止，主仓恢复到合并前。可以在编辑器或终端处理后再合并。", "Git aborted the conflicting merge and restored the main worktree. Resolve the differences in your editor or Terminal, then try again.")
                    : FizzL10n.text("这次合并未能自动恢复。请在主仓的编辑器或终端核对并处理现有合并，不要重复合并。", "Git couldn’t restore the main worktree automatically. Resolve the existing merge in your editor or Terminal before trying again.")
            case let .blocked(message), let .git(message):
                message
            }
        }
    }

    private static let activeWrites = OSAllocatedUnfairLock(initialState: Set<String>())
    private static let gitLocationOverrides = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_NAMESPACE",
        "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_QUARANTINE_PATH",
        "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_PREFIX", "GIT_CEILING_DIRECTORIES",
    ]

    static func list(in directory: URL) async -> [GitWorktree] {
        (try? await inventory(in: directory)) ?? []
    }

    static func status(in directory: URL) async throws -> Overview {
        let worktrees = try await inventory(in: directory)
        let primary = try primaryDirectory(worktrees)
        let base = await mainBranch(in: primary)
        let baseID = if let base { await branchObject(base, in: primary) } else { nil as String? }
        var rows: [Row] = []
        for worktree in worktrees {
            try Task.checkCancellation()
            let checkout = URL(fileURLWithPath: worktree.path, isDirectory: true)
            async let working = worktree.isBare || worktree.isPrunable ? nil : (try? await changes(in: checkout))
            async let diverged = divergence(from: baseID, to: worktree.objectID, in: primary)
            let (snapshot, counts) = await (working, diverged)
            rows.append(Row(worktree: worktree, changedCount: snapshot?.changes.count, ahead: counts?.ahead, behind: counts?.behind))
        }
        return Overview(rows: rows, mainBranch: base)
    }

    static func destination(for branch: String, beside mainDirectory: URL) -> URL? {
        guard plausibleBranch(branch) else { return nil }
        let slug = branch.replacingOccurrences(of: "/", with: "-")
        let parent = mainDirectory.deletingLastPathComponent()
        let container = mainDirectory.lastPathComponent + "-wt"
        guard !mainDirectory.lastPathComponent.isEmpty, parent.path != mainDirectory.path,
              slug.utf8.count <= Int(NAME_MAX), container.utf8.count <= Int(NAME_MAX) else { return nil }
        return parent.appendingPathComponent(container, isDirectory: true).appendingPathComponent(slug, isDirectory: true)
    }

    @discardableResult
    static func create(_ branch: String, in directory: URL) async throws -> GitWorktree {
        try await withWrite(in: directory) { primary, _ in
            guard let target = destination(for: branch, beside: primary),
                  (await command(["check-ref-format", "--branch", branch], in: primary))?.succeeded == true else {
                throw Failure.blocked(FizzL10n.text("分支名不合法。请使用 Git 分支名，例如 feature/layout。", "Enter a valid Git branch name, such as feature/layout."))
            }
            guard let base = await mainBranch(in: primary), let start = await branchObject(base, in: primary) else {
                throw Failure.blocked(FizzL10n.text("找不到已提交的主分支，不能新建并行目录。", "No main branch with a commit was found. The worktree can’t be created."))
            }
            guard await branchObject(branch, in: primary) == nil else {
                throw Failure.blocked(FizzL10n.text("分支「\(branch)」已存在，请换一个名字。", "Branch “\(branch)” already exists. Choose another name."))
            }

            try Task.checkCancellation()
            let container = target.deletingLastPathComponent()
            try ensureContainer(container)
            // Reserve the exact name first: Git will accept an existing empty directory on its own.
            guard mkdir(target.path, 0o755) == 0 else {
                if errno == EEXIST { throw Failure.blocked(FizzL10n.text("目标位置已存在，不会覆盖：\(target.path)", "The destination already exists and won’t be overwritten: \(target.path)")) }
                throw Failure.blocked(FizzL10n.text("无法创建并行目录：\(target.path)", "Couldn’t create a worktree at \(target.path)"))
            }
            let reserved = FileStamp(target.path)
            do {
                _ = try await git(["worktree", "add", "-b", branch, "--", target.path, start], in: primary, timeout: 120)
            } catch {
                if reserved?.sameEntry(as: FileStamp(target.path)) == true { _ = rmdir(target.path) }
                throw error
            }
            guard let created = try await inventory(in: primary).first(where: {
                $0.branch == branch && PathTools.canonical($0.path) == target.path
            }) else { throw Failure.git(FizzL10n.text("Git 已创建目录，但暂时无法读取记录，请刷新后核对。", "Git created the worktree, but its record couldn’t be read. Refresh to check it.")) }
            return created
        }
    }

    @discardableResult
    static func mergeIntoMain(_ worktree: GitWorktree, in directory: URL) async throws -> String {
        try await withWrite(in: directory) { primary, worktrees in
            let checkout = try await checkedDirectory(worktree, among: worktrees, primary: primary)
            guard let branch = worktree.branch, let source = worktree.objectID,
                  let base = await mainBranch(in: primary), let original = await branchObject(base, in: primary),
                  worktrees.first?.branch == base, await currentBranch(in: primary) == base else {
                throw Failure.blocked(FizzL10n.text("请先在主仓检出主分支，再重新合并。FizzDeck 不会自动切换分支。", "Check out the main branch in the main worktree before merging. FizzDeck won’t switch branches automatically."))
            }
            try await requireIdleGit(in: checkout)
            guard try await changes(in: checkout).changes.isEmpty else {
                throw Failure.blocked(FizzL10n.text("并行目录还有未提交的改动，请先提交，再合并。", "Commit changes in the worktree before merging."))
            }
            let gitDir = try await requireIdleGit(in: primary)
            guard try await changes(in: primary).changes.isEmpty else {
                throw Failure.blocked(FizzL10n.text("主仓有未提交的改动，请先处理后再合并。", "Resolve uncommitted changes in the main worktree before merging."))
            }
            guard await currentBranch(in: primary) == base, await branchObject(base, in: primary) == original,
                  await currentBranch(in: checkout) == branch, await branchObject(branch, in: checkout) == source else {
                throw Failure.blocked(FizzL10n.text("分支已变化。请刷新并重新确认要合并的版本。", "The branch has changed. Refresh and confirm the version to merge."))
            }
            try Task.checkCancellation()
            let result = await command(
                ["-c", "rerere.enabled=false", "merge", "--ff", "--no-autostash", "--no-overwrite-ignore", "--no-edit", "--no-gpg-sign",
                 "-m", "Merge branch '\(branch)' into \(base)", "--", source],
                in: primary, timeout: 120
            )
            if let result, result.succeeded, !result.timedOut {
                return FizzL10n.text("已将「\(branch)」合并到「\(base)」。并行目录仍保留。", "Merged “\(branch)” into “\(base)”. The worktree was kept.")
            }

            let mergeHead = gitDir.appendingPathComponent("MERGE_HEAD")
            // Only abort the merge that we started. Leave unrelated Git operations alone.
            if (try? String(contentsOf: mergeHead, encoding: .utf8).trimmingCharacters(in: .newlines)) == source {
                let conflict = (try? await changes(in: primary).changes.contains(where: \.conflicted)) == true
                let abort = await command(["merge", "--abort"], in: primary, timeout: 60)
                let restored: Bool
                if abort?.succeeded == true, abort?.timedOut == false,
                   await branchObject(base, in: primary) == original, !FileTools.exists(mergeHead) {
                    restored = (try? await changes(in: primary).changes.isEmpty) == true
                } else { restored = false }
                if conflict || !restored {
                    throw Failure.mergeConflict(mainPath: primary.path, rollbackSucceeded: restored)
                }
            }
            throw gitFailure(result, fallback: FizzL10n.text("合并未完成，请在主仓的终端核对状态。", "Merge incomplete. Check the status in the main worktree’s terminal."))
        }
    }

    static func remove(
        _ worktree: GitWorktree,
        in directory: URL,
        confirmingDiscardOf reviewed: DiscardConfirmation? = nil,
        managedActivity: @escaping @MainActor @Sendable (String) -> Bool = { _ in false }
    ) async throws {
        try await withWrite(in: directory) { primary, worktrees in
            let checkout = try await checkedDirectory(worktree, among: worktrees, primary: primary)
            try await requireIdleGit(in: checkout)
            let snapshot = try await changes(in: checkout, includingIgnored: true)
            guard try !hasProcess(in: checkout), await !managedActivity(checkout.path) else {
                throw Failure.blocked(FizzL10n.text("该目录仍有服务、测试或其他进程在使用。请先停止它们或让终端离开此目录。", "A service, test or other process is using this folder. Stop it or change the terminal’s working directory first."))
            }
            var arguments = ["worktree", "remove"]
            if !snapshot.changes.isEmpty {
                let paths = snapshot.changes.flatMap { [$0.path, $0.originalPath].compactMap { $0 } }
                let stamps = [FileStamp(checkout.path), FileStamp(checkout.appendingPathComponent(".git").path)]
                    + paths.map { FileStamp(checkout.appendingPathComponent($0).standardizedFileURL.path) }
                let ignored = snapshot.changes.filter { $0.indexStatus == "!" }.count
                let current = DiscardConfirmation(
                    changedCount: snapshot.changes.count - ignored, ignoredCount: ignored,
                    worktree: worktree, entries: snapshot.raw, stamps: stamps
                )
                guard let reviewed, reviewed.worktree == current.worktree, reviewed.entries == current.entries,
                      reviewed.stamps == current.stamps, reviewed.unused.withLock({ available in
                          defer { available = false }
                          return available
                      }) else { throw Failure.dirtyRemoval(current) }
                arguments.append("--force")
            }
            try Task.checkCancellation()
            _ = try await git(arguments + ["--", checkout.path], in: primary, timeout: 120)
        }
    }

    private static func inventory(in directory: URL) async throws -> [GitWorktree] {
        let current = URL(fileURLWithPath: PathTools.canonical(directory.path), isDirectory: true)
        let raw = try await git(["worktree", "list", "--porcelain", "-z"], in: current)
        let worktrees = parsePorcelain(raw)
        guard raw.last == "\0", worktrees.contains(where: { PathTools.canonical($0.path) == current.path }) else {
            throw Failure.blocked(FizzL10n.text("当前目录不是 Git 登记的工作区，无法确认要操作的仓库。", "This folder isn’t a registered Git worktree. The repository could not be verified."))
        }
        return worktrees
    }

    private static func primaryDirectory(_ worktrees: [GitWorktree]) throws -> URL {
        guard let primary = worktrees.first, !primary.isBare, !primary.isPrunable else {
            throw Failure.blocked(FizzL10n.text("找不到可用的主工作区。", "No main worktree found."))
        }
        return URL(fileURLWithPath: PathTools.canonical(primary.path), isDirectory: true)
    }

    private static func withWrite<T: Sendable>(
        in directory: URL, _ operation: (URL, [GitWorktree]) async throws -> T
    ) async throws -> T {
        let worktrees = try await inventory(in: directory)
        let primary = try primaryDirectory(worktrees)
        guard activeWrites.withLock({ $0.insert(primary.path).inserted }) else {
            throw Failure.blocked(FizzL10n.text("这个仓库正在执行并行目录操作，请稍后再试。", "Another worktree operation is in progress. Try again shortly."))
        }
        defer { _ = activeWrites.withLock { $0.remove(primary.path) } }
        try await requireTopLevel(primary)
        try Task.checkCancellation()
        return try await operation(primary, worktrees)
    }

    private static func checkedDirectory(_ worktree: GitWorktree, among worktrees: [GitWorktree], primary: URL) async throws -> URL {
        guard worktree.canManage, worktrees.contains(worktree) else {
            throw Failure.blocked(FizzL10n.text("目录、分支或版本已变化，或该目录已锁定。请先刷新再操作。", "The folder, branch or revision changed, or the worktree is locked. Refresh and try again."))
        }
        guard FileStamp(worktree.path)?.isDirectory == true else {
            throw Failure.blocked(FizzL10n.text("并行目录已移走或是符号链接，不能操作。", "The worktree moved or is a symbolic link. The operation stopped."))
        }
        let directory = URL(fileURLWithPath: PathTools.canonical(worktree.path), isDirectory: true)
        try await requireTopLevel(directory)
        let common = ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        async let expected = git(common, in: primary)
        async let actual = git(common, in: directory)
        guard try await expected == actual else {
            throw Failure.blocked(FizzL10n.text("该位置已不是主仓登记的并行目录，已停止操作。", "This location is no longer registered as a worktree. The operation stopped."))
        }
        return directory
    }

    private static func requireTopLevel(_ directory: URL) async throws {
        var root = try await git(["rev-parse", "--show-toplevel"], in: directory)
        if root.last == "\n" { root.removeLast() }
        guard root.hasPrefix("/"), PathTools.canonical(root) == directory.path else {
            throw Failure.blocked(FizzL10n.text("Git 根目录和所选目录不一致，已停止操作。", "The selected folder doesn’t match the Git root. The operation stopped."))
        }
    }

    private static func plausibleBranch(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= Int(NAME_MAX), name.uppercased() != "HEAD",
              !name.hasPrefix("-"), !name.contains(".."), !name.contains("@{"),
              name != "@", !name.hasSuffix(".") else { return false }
        let invalid = CharacterSet.controlCharacters.union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "~^:?*[\\"))
        guard name.rangeOfCharacter(from: invalid) == nil else { return false }
        return name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".lock")
        }
    }

    private static func ensureContainer(_ directory: URL) throws {
        if mkdir(directory.path, 0o755) != 0, errno != EEXIST {
            throw Failure.blocked(FizzL10n.text("无法创建并行目录的上级目录：\(directory.path)", "Couldn’t create the parent folder for the worktree: \(directory.path)"))
        }
        guard FileStamp(directory.path)?.isDirectory == true,
              FileStamp(directory.appendingPathComponent(".git").path) == nil else {
            throw Failure.blocked(FizzL10n.text("上级位置必须是普通目录，不能是符号链接或另一个 Git 仓库。", "The parent must be a regular folder, not a symbolic link or another Git repository."))
        }
    }

    private static func mainBranch(in directory: URL) async -> String? {
        let remotePrefix = "refs/remotes/origin/"
        if let ref = try? await git(["symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"], in: directory),
           ref.hasPrefix(remotePrefix) {
            let branch = String(ref.dropFirst(remotePrefix.count)).trimmingCharacters(in: .newlines)
            if await branchObject(branch, in: directory) != nil { return branch }
        }
        for branch in ["main", "master"] {
            if await branchObject(branch, in: directory) != nil { return branch }
        }
        return nil
    }

    private static func currentBranch(in directory: URL) async -> String? {
        let prefix = "refs/heads/"
        guard let ref = try? await git(["symbolic-ref", "--quiet", "HEAD"], in: directory),
              ref.hasPrefix(prefix) else { return nil }
        return String(ref.dropFirst(prefix.count)).trimmingCharacters(in: .newlines)
    }

    private static func branchObject(_ branch: String, in directory: URL) async -> String? {
        guard plausibleBranch(branch),
              let output = try? await git(["rev-parse", "--verify", "--end-of-options", "refs/heads/\(branch)^{commit}"], in: directory)
        else { return nil }
        let value = output.trimmingCharacters(in: .newlines)
        return isObjectID(value) ? value : nil
    }

    private static func isObjectID(_ value: String) -> Bool {
        (value.utf8.count == 40 || value.utf8.count == 64) && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func divergence(from base: String?, to head: String?, in directory: URL) async -> GitTrackingCounts? {
        guard let base, let head, isObjectID(head) else { return nil }
        if base == head { return GitTrackingCounts() }
        guard let output = try? await git(["rev-list", "--left-right", "--count", "\(base)...\(head)", "--"], in: directory),
              output.split(whereSeparator: \.isWhitespace).count == 2,
              output.split(whereSeparator: \.isWhitespace).allSatisfy({ Int($0) != nil }) else { return nil }
        return GitService.trackingCounts(output)
    }

    @discardableResult
    private static func requireIdleGit(in directory: URL) async throws -> URL {
        var path = try await git(["rev-parse", "--absolute-git-dir"], in: directory)
        if path.last == "\n" { path.removeLast() }
        guard path.hasPrefix("/") else { throw Failure.blocked(FizzL10n.text("无法确认 Git 状态，请先在终端核对。", "Couldn’t confirm Git status. Check it in Terminal first.")) }
        let gitDir = URL(fileURLWithPath: path, isDirectory: true)
        let states = ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "REBASE_HEAD", "rebase-apply", "rebase-merge", "sequencer", "BISECT_START"]
        guard !states.contains(where: { FileStamp(gitDir.appendingPathComponent($0).path) != nil }) else {
            throw Failure.blocked(FizzL10n.text("这个目录有未完成的 Git 操作，请先在终端处理。", "A Git operation is unfinished in this folder. Resolve it in Terminal first."))
        }
        return gitDir
    }

    private static func changes(in directory: URL, includingIgnored: Bool = false) async throws -> (raw: String, changes: [GitChange]) {
        var arguments = ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none"]
        // Expand ignored directories so a change to an existing file invalidates its discard confirmation.
        if includingIgnored { arguments.append("--ignored") }
        let raw = try await git(arguments, in: directory)
        let parsed = GitService.parseChanges(raw)
        let statuses: Set<Character> = [" ", "M", "T", "A", "D", "R", "C", "U", "?", "!"]
        guard raw.isEmpty || (raw.last == "\0" && !parsed.isEmpty && parsed.allSatisfy({
            !$0.path.isEmpty && statuses.contains($0.indexStatus) && statuses.contains($0.worktreeStatus)
        })) else { throw Failure.blocked(FizzL10n.text("无法可靠读取工作区状态，请先在终端核对。", "Couldn’t verify the working tree status. Check it in Terminal first.")) }
        return (raw, parsed)
    }

    private static func hasProcess(in directory: URL) throws -> Bool {
        // libproc reports the physical path even when Foundation displays /var or /tmp.
        guard let physicalPath = realpath(directory.path, nil) else {
            throw Failure.blocked(FizzL10n.text("无法确认工作区路径，先取消移除。", "Couldn’t verify the worktree path. Removal canceled."))
        }
        defer { free(physicalPath) }
        let root = String(cString: physicalPath)
        let count = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard count > 0 else { throw Failure.blocked(FizzL10n.text("无法核对运行中的服务，先取消移除。", "Couldn’t check for running services. Removal canceled.")) }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.stride + 64)
        let read = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count)) }
        guard read > 0, Int(read) < pids.count * MemoryLayout<pid_t>.stride else {
            throw Failure.blocked(FizzL10n.text("无法核对运行中的服务，先取消移除。", "Couldn’t check for running services. Removal canceled."))
        }
        let nestedPrefix = root + "/"
        for pid in pids.prefix(Int(read) / MemoryLayout<pid_t>.stride) where pid > 1 && pid != getpid() {
            var info = proc_vnodepathinfo()
            let bytes = Int32(MemoryLayout.size(ofValue: info))
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, bytes) == bytes else { continue }
            let cwd = withUnsafeBytes(of: &info.pvi_cdir.vip_path) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            if cwd == root || cwd.hasPrefix(nestedPrefix) { return true }
        }
        return false
    }

    private static func command(_ arguments: [String], in directory: URL, timeout: TimeInterval = 20) async -> ShellOutput? {
        await Shell.run("/usr/bin/env", gitLocationOverrides.flatMap { ["-u", $0] } + [
            DoctorCommand.git ?? "/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
        ] + arguments, cwd: directory, timeout: timeout, extraEnvironment: [
            "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_REPLACE_OBJECTS": "1",
            "GIT_NO_LAZY_FETCH": "1", "GIT_ALLOW_PROTOCOL": "", "LC_ALL": "C",
        ])
    }

    private static func git(_ arguments: [String], in directory: URL, timeout: TimeInterval = 20) async throws -> String {
        let result = await command(arguments, in: directory, timeout: timeout)
        guard let result, result.succeeded, !result.timedOut, result.hasUTF8Output else {
            throw gitFailure(result, fallback: FizzL10n.text("Git 操作未完成。", "Git did not complete the operation."))
        }
        return result.text
    }

    private static func gitFailure(_ result: ShellOutput?, fallback: String) -> Failure {
        guard let result, !result.timedOut else { return .git(FizzL10n.text("\(fallback) Git 超时或无法启动。", "\(fallback) Git timed out or could not start.")) }
        let lines = result.text.split(whereSeparator: \.isNewline)
        let detail = lines.first(where: { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") }) ?? lines.last
        let explanation = detail.map { " \(SecretRedactor.redact(String($0.prefix(200))).text)" } ?? ""
        return .git(fallback + explanation)
    }

    fileprivate struct FileStamp: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let bytes: off_t
        let modified: Int
        let nanoseconds: Int
        let changed: Int
        let changedNanoseconds: Int

        init?(_ path: String) {
            var value = stat()
            guard lstat(path, &value) == 0 else { return nil }
            device = value.st_dev
            inode = value.st_ino
            mode = value.st_mode
            bytes = value.st_size
            modified = value.st_mtimespec.tv_sec
            nanoseconds = value.st_mtimespec.tv_nsec
            changed = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }

        var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
        func sameEntry(as other: Self?) -> Bool { device == other?.device && inode == other?.inode }
    }

    static func parsePorcelain(_ output: String) -> [GitWorktree] {
        var records: [[String]] = []
        var current: [String] = []

        let fields = output.contains("\0") ? output.split(separator: "\0") : output.split(whereSeparator: \.isNewline)
        for rawLine in fields.map(String.init) {
            if rawLine.hasPrefix("worktree ") {
                if !current.isEmpty {
                    records.append(current)
                }
                current = [rawLine]
            } else if !rawLine.isEmpty, !current.isEmpty {
                current.append(rawLine)
            }
        }
        if !current.isEmpty {
            records.append(current)
        }

        return records.enumerated().compactMap { index, lines in
            guard let first = lines.first,
                  first.hasPrefix("worktree ")
            else { return nil }
            let path = String(first.dropFirst("worktree ".count))
            guard !path.isEmpty else { return nil }

            var head: String?
            var branch: String?
            var detached = false
            var bare = false
            var locked = false
            var prunable = false

            for line in lines.dropFirst() {
                if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line.hasPrefix("branch ") {
                    branch = String(line.dropFirst("branch ".count))
                } else if line == "detached" {
                    detached = true
                } else if line == "bare" {
                    bare = true
                } else if line.hasPrefix("locked") {
                    locked = true
                } else if line.hasPrefix("prunable") {
                    prunable = true
                }
            }

            let normalizedPath = PathTools.normalize(path)
            return GitWorktree(
                path: normalizedPath,
                objectID: head,
                branch: branch,
                isMain: index == 0,
                isDetached: detached || (branch == nil && !bare),
                isBare: bare,
                isLocked: locked,
                isPrunable: prunable
            )
        }
    }
}

private extension GitWorktree {
    var canManage: Bool { !isMain && !isBare && !isLocked && !isPrunable && !isDetached && branch != nil && objectID != nil }
}
