import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RepositoryStore {
    static let homeSelection = "__repodeck_home__"
    static let filterPrefix = "__repodeck_filter__:"
    private static let recentProjectsKey = "fizzdeck.recentProjects"
    private static let recentActionsKey = "fizzdeck.recentActions"

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case failed(String)
    }

    var projects: [RepoProject] = []
    var roots: [String] = []
    var selectedPath: String? = homeSelection {
        didSet {
            guard let selectedPath,
                  selectedPath != Self.homeSelection,
                  !selectedPath.hasPrefix(Self.filterPrefix),
                  projects.contains(where: { $0.path == selectedPath })
            else { return }
            recordRecentProject(selectedPath)
        }
    }
    var query = ""
    var phase: Phase = .idle
    var scannedAt: Date?
    var scanDuration: TimeInterval = 0
    var requestedTab: ProjectTab?
    var isCommandPalettePresented = false
    var isFolderManagerPresented = false
    private(set) var remotes: [String: GitRemote] = [:]
    private(set) var missingRemotes: Set<String> = []
    private(set) var recentProjectPaths: [String] = []
    private(set) var recentActionIDs: [String] = []

    private var metadata: [String: ProjectMeta] = [:]
    private var remoteTasks: [String: Task<GitRemote?, Never>] = [:]
    private var didPrepare = false

    init() {
        recentProjectPaths = UserDefaults.standard.stringArray(forKey: Self.recentProjectsKey) ?? []
        recentActionIDs = (UserDefaults.standard.stringArray(forKey: Self.recentActionsKey) ?? [])
            .filter { !$0.hasPrefix("project.") }
    }

    var filteredProjects: [RepoProject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return projects }
        return projects.filter { project in
            project.displayName.lowercased().contains(needle)
                || project.name.lowercased().contains(needle)
                || project.path.lowercased().contains(needle)
                || project.stacks.contains(where: { group in
                    group.items.contains(where: { $0.lowercased().contains(needle) })
                })
        }
    }

    var selectedProject: RepoProject? {
        guard let selectedPath,
              selectedPath != Self.homeSelection,
              !selectedPath.hasPrefix(Self.filterPrefix)
        else { return nil }
        return projects.first { $0.path == selectedPath }
    }

    var selectedHomeFilter: HomeFilter? {
        guard let selectedPath else { return nil }
        if selectedPath == Self.homeSelection { return .all }
        guard selectedPath.hasPrefix(Self.filterPrefix) else { return nil }
        return HomeFilter(rawValue: String(selectedPath.dropFirst(Self.filterPrefix.count))) ?? .all
    }

    var runningCount: Int {
        projects.filter { $0.port == .running }.count
    }

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        metadata = MetaStore.load()
        roots = RootStore.load()
        await scan()
    }

    func scan() async {
        guard phase != .scanning else { return }
        phase = .scanning
        let roots = RootStore.load()
        let metadata = metadata
        let output = await RepositoryScanner.scan(roots: roots, meta: metadata)
        self.roots = output.roots
        projects = output.projects
        scannedAt = output.scannedAt
        scanDuration = output.duration
        phase = .ready
        pruneRemotes(for: output.projects)

        if selectedPath == Self.homeSelection
            || selectedPath?.hasPrefix(Self.filterPrefix) == true {
            return
        }
        if let selectedPath, projects.contains(where: { $0.path == selectedPath }) {
            return
        }
        selectedPath = Self.homeSelection
    }

    func rescanProjects(_ projects: [RepoProject]) async {
        let paths = projects.map(\.path)
        guard !paths.isEmpty else { return }

        let started = Date()
        let scanned = await RepositoryScanner.scan(paths: paths, meta: metadata)
        let replacements = Dictionary(
            scanned.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.projects = self.projects.map { replacements[$0.path] ?? $0 }
        scanDuration = Date().timeIntervalSince(started)
        scannedAt = Date()

        let refreshed = Set(paths)
        remotes = remotes.filter { !refreshed.contains($0.key) }
        missingRemotes.subtract(refreshed)
        remoteTasks = remoteTasks.filter { !refreshed.contains($0.key) }
    }

    func addRoot() async {
        isCommandPalettePresented = false
        isFolderManagerPresented = true
    }

    func chooseFolderForScan() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "添加项目文件夹"
        panel.message = "选择父文件夹后，自动查找其中的项目。"
        panel.prompt = "扫描"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return URL(fileURLWithPath: PathTools.normalize(url.path), isDirectory: true)
    }

    @discardableResult
    func addProjects(paths: [String]) async -> Int {
        var roots = RootStore.load()
        var existing = Set(roots)
        var added = 0

        for rawPath in paths {
            let path = PathTools.normalize(rawPath)
            guard FileTools.isDirectory(URL(fileURLWithPath: path)),
                  existing.insert(path).inserted
            else { continue }
            roots.append(path)
            added += 1
        }

        if added > 0 {
            try? RootStore.save(roots)
            await scan()
        }
        return added
    }

    func dismissFolderManager() {
        isFolderManagerPresented = false
    }

    func removeFromBoard(_ project: RepoProject) async {
        var roots = RootStore.load()
        roots.removeAll { $0 == project.path }
        try? RootStore.save(roots)
        if selectedPath == project.path {
            selectedPath = Self.homeSelection
            requestedTab = nil
        }
        await scan()
    }

    func removeProject(
        _ project: RepoProject,
        mode: ProjectRemovalMode,
        confirmation: String,
        testRunning: Bool
    ) async -> ProjectRemovalResult {
        let roots = RootStore.load()
        let result = await Task.detached(priority: .userInitiated) {
            ProjectRemovalService.remove(
                path: project.path,
                mode: mode,
                confirmation: confirmation,
                managedRoots: roots,
                testRunning: testRunning,
                devServerRunning: project.port == .running
            )
        }.value
        guard result.success else { return result }

        self.roots.removeAll { $0 == project.path }
        try? RootStore.save(self.roots)

        metadata.removeValue(forKey: project.path)
        try? MetaStore.save(metadata)

        projects.removeAll { $0.path == project.path }
        remotes.removeValue(forKey: project.path)
        missingRemotes.remove(project.path)
        remoteTasks[project.path]?.cancel()
        remoteTasks[project.path] = nil
        recentProjectPaths.removeAll { $0 == project.path }
        UserDefaults.standard.set(recentProjectPaths, forKey: Self.recentProjectsKey)

        if selectedPath == project.path {
            selectedPath = Self.homeSelection
            requestedTab = nil
        }
        return result
    }

    func openProject(_ project: RepoProject, tab: ProjectTab? = nil) {
        selectedPath = project.path
        requestedTab = tab
        isCommandPalettePresented = false
    }

    func recordRecentProject(_ path: String) {
        guard path != Self.homeSelection, !path.hasPrefix(Self.filterPrefix) else { return }
        var list = recentProjectPaths.filter { $0 != path }
        list.insert(path, at: 0)
        let next = Array(list.prefix(8))
        guard next != recentProjectPaths else { return }
        recentProjectPaths = next
        UserDefaults.standard.set(next, forKey: Self.recentProjectsKey)
    }

    func recordPaletteAction(_ id: String) {
        guard !id.hasPrefix("project.") else { return }
        var list = recentActionIDs.filter { $0 != id }
        list.insert(id, at: 0)
        let next = Array(list.prefix(6))
        guard next != recentActionIDs else { return }
        recentActionIDs = next
        UserDefaults.standard.set(next, forKey: Self.recentActionsKey)
    }

    func cachedRemote(for path: String) -> GitRemote? {
        remotes[path]
    }

    func hasResolvedRemote(for path: String) -> Bool {
        remotes[path] != nil || missingRemotes.contains(path)
    }

    func remote(for project: RepoProject) async -> GitRemote? {
        let path = project.path
        if let cached = remotes[path] { return cached }
        if missingRemotes.contains(path) { return nil }
        if let task = remoteTasks[path] { return await task.value }

        let directory = URL(fileURLWithPath: path)
        let task = Task { await GitService.remote(directory) }
        remoteTasks[path] = task
        let value = await task.value
        remoteTasks[path] = nil
        if let value {
            remotes[path] = value
        } else {
            missingRemotes.insert(path)
        }
        return value
    }

    func loadRemotes(for projects: [RepoProject], limit: Int = 80) async {
        let candidates = projects
            .filter { remotes[$0.path] == nil && !missingRemotes.contains($0.path) }
            .prefix(limit)
            .map(\.path)
        guard !candidates.isEmpty else { return }

        let results = await withTaskGroup(
            of: (String, GitRemote?).self,
            returning: [(String, GitRemote?)].self
        ) { group in
            var index = 0
            let maxConcurrent = 4
            while index < min(maxConcurrent, candidates.count) {
                let path = candidates[index]
                group.addTask {
                    (path, await GitService.remote(URL(fileURLWithPath: path)))
                }
                index += 1
            }

            var collected: [(String, GitRemote?)] = []
            while let result = await group.next() {
                collected.append(result)
                if index < candidates.count {
                    let path = candidates[index]
                    group.addTask {
                        (path, await GitService.remote(URL(fileURLWithPath: path)))
                    }
                    index += 1
                }
            }
            return collected
        }

        for (path, remote) in results {
            if let remote {
                remotes[path] = remote
            } else {
                missingRemotes.insert(path)
            }
        }
    }

    private func pruneRemotes(for projects: [RepoProject]) {
        let paths = Set(projects.map(\.path))
        remotes = remotes.filter { paths.contains($0.key) }
        missingRemotes.formIntersection(paths)
        remoteTasks = remoteTasks.filter { paths.contains($0.key) }
    }

    func toggleCommandPalette() {
        if !isCommandPalettePresented {
            isFolderManagerPresented = false
        }
        isCommandPalettePresented.toggle()
    }

    func toggleStar(_ project: RepoProject) {
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return }
        projects[index].starred.toggle()
        var meta = metadata[project.path] ?? ProjectMeta()
        meta.starred = projects[index].starred
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
    }

    func setColor(_ color: TagColor?, for project: RepoProject) {
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return }
        projects[index].color = color
        var meta = metadata[project.path] ?? ProjectMeta()
        meta.color = color
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
    }

    func setNote(_ note: String, for project: RepoProject) {
        let trimmed = String(note.prefix(200))
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return }
        projects[index].note = trimmed
        var meta = metadata[project.path] ?? ProjectMeta()
        meta.note = trimmed
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
    }

    func setGroup(_ group: String?, for project: RepoProject) {
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return }
        let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed?.isEmpty == false ? trimmed : nil
        projects[index].group = value ?? ProjectGrouping.detected(for: project.path)

        var meta = metadata[project.path] ?? ProjectMeta()
        meta.group = value
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
    }

    var knownGroups: [String] {
        ProjectGrouping.ordered(projects.map(\.group))
    }

    func setPort(_ state: PortState, for path: String) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].port = state
    }

    static func selection(for filter: HomeFilter) -> String {
        filter == .all ? homeSelection : filterPrefix + filter.rawValue
    }

    func count(for filter: HomeFilter) -> Int {
        projects.filter(filter.matches).count
    }

    func detail(for project: RepoProject) async -> ProjectDetail {
        let directory = URL(fileURLWithPath: project.path)
        async let gitTask = GitService.detail(directory)
        async let docsTask = Task.detached(priority: .utility) {
            DocService.list(directory)
        }
        let (git, commits) = await gitTask
        let docs = await docsTask.value
        return ProjectDetail(git: git, commits: commits, docs: docs)
    }

    func refreshGit(for path: String) async {
        let directory = URL(fileURLWithPath: path)
        guard let git = await GitService.summary(directory) else { return }
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }

        projects[index].branch = git.branch
        projects[index].lastCommit = git.lastCommit
        projects[index].dirtyCount = git.changes.total
        projects[index].changes = git.changes
        projects[index].ahead = git.ahead
        projects[index].behind = git.behind
        projects[index].recent = [
            git.lastCommit?.date,
            projects[index].sessions.lastSessionAt,
        ].compactMap { $0 }.max()
    }

    func isAttentionSuppressed(
        for project: RepoProject,
        kind: ProjectAttentionKind,
        at date: Date = Date()
    ) -> Bool {
        attentionPreference(for: project, kind: kind)?.suppresses(at: date) ?? false
    }

    func attentionPreference(
        for project: RepoProject,
        kind: ProjectAttentionKind
    ) -> AttentionPreference? {
        metadata[project.path]?.attention[kind.rawValue]
    }

    func snoozeAttention(
        for project: RepoProject,
        kind: ProjectAttentionKind,
        until date: Date
    ) {
        guard date > Date() else { return }
        var meta = metadata[project.path] ?? ProjectMeta()
        meta.attention[kind.rawValue] = AttentionPreference(snoozedUntil: date)
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
    }

    func muteAttention(for project: RepoProject, kind: ProjectAttentionKind) {
        var meta = metadata[project.path] ?? ProjectMeta()
        meta.attention[kind.rawValue] = AttentionPreference(muted: true)
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
    }

    func restoreAttention(for project: RepoProject, kind: ProjectAttentionKind) {
        restoreAttention(for: [(project.path, kind.rawValue)])
    }

    func restoreAttention(for rules: [(String, String)]) {
        var changed = false
        for (path, kind) in rules {
            guard var meta = metadata[path], meta.attention.removeValue(forKey: kind) != nil else {
                continue
            }
            metadata[path] = meta
            changed = true
        }
        if changed {
            try? MetaStore.save(metadata)
        }
    }

    func reloadProjectDetailMetadata() {}
}
