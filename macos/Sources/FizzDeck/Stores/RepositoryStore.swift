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
    var destination: AppDestination = .dashboard {
        didSet {
            guard case let .project(path) = destination,
                  projects.contains(where: { $0.path == path })
            else { return }
            recordRecentProject(path)
        }
    }
    var selectedPath: String? {
        get {
            switch destination {
            case .dashboard:
                Self.homeSelection
            case .project(let path):
                path
            case .conversations, .library, .cleanup:
                nil
            }
        }
        set {
            guard let newValue else {
                destination = .dashboard
                return
            }
            if newValue == Self.homeSelection {
                destination = .dashboard
            } else if newValue.hasPrefix(Self.filterPrefix) {
                let raw = String(newValue.dropFirst(Self.filterPrefix.count))
                switch HomeFilter(rawValue: raw) ?? .all {
                case .all:
                    destination = .library()
                case .starred:
                    destination = .library(LibraryQuery(starredOnly: true))
                case .dirty:
                    destination = .library(LibraryQuery(dirtyOnly: true))
                case .running:
                    destination = .library(LibraryQuery(runningOnly: true))
                }
            } else {
                destination = .project(newValue)
            }
        }
    }
    var query = ""
    var phase: Phase = .idle
    var isFirstRunPresented = false
    var isEnriching = false
    var pendingSizeCount = 0
    var scannedAt: Date?
    var scanDuration: TimeInterval = 0
    var requestedTab: ProjectTab?
    var requestedSessionID: String?
    var requestedMarkIDForDiff: String?
    var requestedSaveVersionForPath: String?
    var requestedCleanupSheet = false
    var commitActivity: CommitActivitySnapshot = .empty
    var isCommandPalettePresented = false
    var isFolderManagerPresented = false
    private(set) var remotes: [String: GitRemote] = [:]
    private(set) var missingRemotes: Set<String> = []
    private(set) var recentProjectPaths: [String] = []
    private(set) var recentActionIDs: [String] = []
    private(set) var activeAIProjectPaths: Set<String> = []
    private(set) var activeAISessionIDs: Set<String> = []
    private(set) var marks: [SessionMark] = MarkStore.load()
    private(set) var doctorReports: [String: DoctorProjectReport] = [:]
    private(set) var machineEnv: MachineEnvironmentReport?
    private(set) var isRunningDoctor = false
    private(set) var lastDoctorCheckAt: Date?

    private var metadata: [String: ProjectMeta] = [:]
    private var remoteTasks: [String: Task<GitRemote?, Never>] = [:]
    private var sizeEnrichmentTask: Task<Void, Never>?
    private var commitActivityTask: Task<Void, Never>?
    private var workspaceWatcher: WorkspaceWatcher?
    @ObservationIgnored private var quietFetchTask: Task<Void, Never>?
    @ObservationIgnored private var pendingQuietFetch: ArraySlice<String> = []
    @ObservationIgnored private var activeQuietFetch: String?
    @ObservationIgnored private var nextQuietFetch: [String: Date] = [:]
    private let quietFetchAttempts: QuietGitFetch.AttemptWindow
    private let quietFetchNow: () -> Date
    private let preferences: UserDefaults
    private let checkRemote: @Sendable (URL) async -> QuietGitFetch.Result?
    @ObservationIgnored private var pendingL0Paths: Set<String> = []
    @ObservationIgnored private var l0Task: Task<Void, Never>?
    @ObservationIgnored private var l0Revision: [String: Int] = [:]
    @ObservationIgnored private var rawDoctorReports: [String: DoctorProjectReport] = [:]
    @ObservationIgnored private var fullDoctorDates: [String: Date] = [:]
    @ObservationIgnored private var lastFullDoctorPageCheck: Date?
    @ObservationIgnored private var lastFullDoctorScope: [String: DoctorCheckScope] = [:]
    @ObservationIgnored private var checkingProjects: Set<String> = []
    private var isRefreshingSessions = false
    private var refreshSessionsAfterScan = false
    private var scheduledSessionRefresh: Task<Void, Never>?
    private var sessionSearchRebuildTask: Task<Void, Never>?
    private(set) var hasIndexedSessionSearch = false
    private var didPrepare = false
    private var previousActiveAISessionIDs: Set<String> = []
    private var hasSeededActiveAISessions = false
    private var lastSessionFinishToastByProject: [String: Date] = [:]

    init(preferences: UserDefaults = .standard, quietFetchAttempts: QuietGitFetch.AttemptWindow = .shared,
         quietFetchNow: @escaping () -> Date = Date.init,
         checkRemote: @escaping @Sendable (URL) async -> QuietGitFetch.Result? = { await QuietGitFetch.check(in: $0) }) {
        self.preferences = preferences
        self.quietFetchAttempts = quietFetchAttempts
        self.quietFetchNow = quietFetchNow
        self.checkRemote = checkRemote
        recentProjectPaths = preferences.stringArray(forKey: Self.recentProjectsKey) ?? []
        recentActionIDs = (preferences.stringArray(forKey: Self.recentActionsKey) ?? [])
            .filter { !$0.hasPrefix("project.") }
    }

    var filteredProjects: [RepoProject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return projects }
        return projects.filter { project in
            project.displayName.lowercased().contains(needle)
                || project.name.lowercased().contains(needle)
                || project.path.lowercased().contains(needle)
                || project.kind.title.lowercased().contains(needle)
                || project.stacks.contains(where: { group in
                    group.items.contains(where: { $0.lowercased().contains(needle) })
                })
        }
    }

    var selectedProject: RepoProject? {
        guard let path = destination.projectPath else { return nil }
        return projects.first { $0.path == path }
    }

    var selectedHomeFilter: HomeFilter? {
        switch destination {
        case .dashboard:
            return .all
        case .library(let query):
            if query.starredOnly { return .starred }
            if query.dirtyOnly { return .dirty }
            if query.runningOnly { return .running }
            return .all
        case .conversations, .cleanup, .project:
            return nil
        }
    }

    var runningCount: Int {
        projects.filter { $0.port == .running }.count
    }

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        metadata = MetaStore.load()
        roots = RootStore.load()

        if OnboardingStore.isNeeded {
            isFirstRunPresented = true
            phase = .ready
            startWorkspaceWatcher()
            return
        }

        let cached = ScanCacheStore.load(for: roots, meta: metadata)
        if !cached.isEmpty {
            projects = cached
            phase = .ready
            scheduleSessionSearchRebuild()
        }
        commitActivity = CommitActivityService.loadCache()
        await scan()
        startWorkspaceWatcher()
    }

    func presentFirstRunScan() {
        isCommandPalettePresented = false
        isFolderManagerPresented = false
        isFirstRunPresented = true
    }

    func completeFirstRun(selectedPaths: [String], skipped: Bool) async {
        let existing = Set(RootStore.load())
        var nextRoots = RootStore.load()
        for rawPath in selectedPaths {
            let path = PathTools.normalize(rawPath)
            guard FileTools.isDirectory(URL(fileURLWithPath: path)),
                  !existing.contains(path),
                  !nextRoots.contains(path)
            else { continue }
            nextRoots.append(path)
        }

        try? RootStore.save(nextRoots)
        try? OnboardingStore.markCompleted(skipped: skipped)
        roots = nextRoots
        isFirstRunPresented = false

        if !nextRoots.isEmpty {
            await scan()
            startWorkspaceWatcher()
            await requestNotificationsIfNeeded()
        } else {
            projects = []
            phase = .ready
        }
    }

    func scan() async {
        guard phase != .scanning else { return }
        sizeEnrichmentTask?.cancel()
        sizeEnrichmentTask = nil
        pendingSizeCount = 0
        isEnriching = false

        let roots = RootStore.load()
        self.roots = roots
        guard !roots.isEmpty else {
            projects = []
            scannedAt = Date()
            syncFocusedChecks()
            scanDuration = 0
            phase = .ready
            flushDeferredSessionRefresh()
            return
        }

        phase = .scanning
        let started = Date()
        let metadata = metadata

        // Stage 1: instant local manifest scan (or preserve cached metrics while refreshing)
        let fast = await RepositoryScanner.scanFast(paths: roots, meta: metadata)
        let existingByPath = Dictionary(
            projects.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        projects = fast.map { fresh in
            guard let existing = existingByPath[fresh.path] else { return fresh }
            var merged = fresh
            if existing.sizeLoadState == .ready {
                merged.size = existing.size
                merged.cleanup = existing.cleanup
                merged.sizeLoadState = .ready
            }
            if existing.gitLoadState == .ready {
                merged.branch = existing.branch
                merged.lastCommit = existing.lastCommit
                merged.dirtyCount = existing.dirtyCount
                merged.changes = existing.changes
                merged.ahead = existing.ahead
                merged.behind = existing.behind
                merged.weekly = existing.weekly
                merged.recent = existing.recent ?? fresh.recent
                merged.gitLoadState = .ready
            }
            if existing.sessionLoadState == .ready {
                merged.sessions = existing.sessions
                merged.sessionLoadState = .ready
            }
            return merged
        }
        phase = .ready
        isEnriching = true

        // Stage 2: Git + incremental SessionIndex + ports (single batch update)
        let enriched = await RepositoryScanner.enrichGitAndSessions(projects: projects, meta: metadata)
        let preservedSizes = Dictionary(
            projects.map { ($0.path, ($0.size, $0.cleanup, $0.sizeLoadState)) },
            uniquingKeysWith: { first, _ in first }
        )
        projects = enriched.map { item in
            var item = item
            if let old = preservedSizes[item.path], old.2 == .ready {
                item.size = old.0
                item.cleanup = old.1
                item.sizeLoadState = .ready
            }
            return item
        }
        scannedAt = Date()
        scanDuration = Date().timeIntervalSince(started)
        pruneRemotes(for: projects)
        ensureValidSelection()
        ScanCacheStore.save(projects)

        // Stage 3: per-project du + cleanup enrichment in background (no re-sort)
        startSizeEnrichment(for: projects.map(\.path))
        startCommitActivityRefresh(for: projects)
        flushDeferredSessionRefresh()
        scheduleSessionSearchRebuild()
        Task { await refreshActiveAISessions() }
        syncFocusedChecks()
    }

    func rescanProjects(_ projects: [RepoProject]) async {
        let paths = projects.map(\.path)
        guard !paths.isEmpty else { return }

        let started = Date()
        let fast = await RepositoryScanner.scanFast(paths: paths, meta: metadata)
        let enriched = await RepositoryScanner.enrichGitAndSessions(projects: fast, meta: metadata)
        let replacements = Dictionary(
            enriched.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.projects = self.projects.map { existing in
            guard var next = replacements[existing.path] else { return existing }
            next.sizeLoadState = .loading
            next.size = existing.size
            next.cleanup = existing.cleanup
            return next
        }
        scanDuration = Date().timeIntervalSince(started)
        scannedAt = Date()

        let refreshed = Set(paths)
        remotes = remotes.filter { !refreshed.contains($0.key) }
        missingRemotes.subtract(refreshed)
        remoteTasks = remoteTasks.filter { !refreshed.contains($0.key) }

        startSizeEnrichment(for: paths)
        startCommitActivityRefresh(for: self.projects)
        scheduleSessionSearchRebuild()
        syncFocusedChecks()
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
        var addedPaths: [String] = []

        for rawPath in paths {
            let path = PathTools.normalize(rawPath)
            guard FileTools.isDirectory(URL(fileURLWithPath: path)),
                  existing.insert(path).inserted
            else { continue }
            roots.append(path)
            addedPaths.append(path)
        }

        if !addedPaths.isEmpty {
            let hadProjectsBefore = !projects.isEmpty
            try? RootStore.save(roots)
            try? OnboardingStore.markCompleted(skipped: false)
            self.roots = roots

            let fast = await RepositoryScanner.scanFast(paths: addedPaths, meta: metadata)
            projects.append(contentsOf: fast)
            phase = .ready
            isEnriching = true

            Task { @MainActor [weak self] in
                guard let self else { return }
                let enriched = await RepositoryScanner.enrichGitAndSessions(projects: fast, meta: metadata)
                let map = Dictionary(
                    enriched.map { ($0.path, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                projects = projects.map { map[$0.path] ?? $0 }
                scannedAt = Date()
                syncFocusedChecks()
                ScanCacheStore.save(projects)
                startSizeEnrichment(for: addedPaths)
                if !hadProjectsBefore {
                    await requestNotificationsIfNeeded()
                }
            }
        }
        return addedPaths.count
    }

    func dismissFolderManager() {
        isFolderManagerPresented = false
    }

    func removeFromBoard(_ project: RepoProject) async {
        var roots = RootStore.load()
        roots.removeAll { $0 == project.path }
        try? RootStore.save(roots)
        self.roots = roots
        projects.removeAll { $0.path == project.path }
        forgetDoctorReport(project.path)
        syncFocusedChecks()
        ScanCacheStore.save(projects)
        if destination.projectPath == project.path {
            destination = .dashboard
            requestedTab = nil
        }
    }

    private func ensureValidSelection() {
        guard case let .project(path) = destination else { return }
        if projects.contains(where: { $0.path == path }) {
            return
        }
        destination = .dashboard
    }

    private func startSizeEnrichment(for paths: [String]) {
        let unique = Array(Set(paths.map(PathTools.normalize)))
        guard !unique.isEmpty else {
            pendingSizeCount = 0
            isEnriching = false
            return
        }

        sizeEnrichmentTask?.cancel()
        pendingSizeCount = unique.count
        isEnriching = true

        sizeEnrichmentTask = Task { @MainActor [weak self] in
            for await (path, size, cleanup) in RepositoryScanner.enrichSizesStream(paths: unique) {
                guard let self, !Task.isCancelled else { return }
                if let index = self.projects.firstIndex(where: { $0.path == path }) {
                    self.projects[index].size = size
                    self.projects[index].cleanup = cleanup
                    self.projects[index].sizeLoadState = .ready
                }
                self.pendingSizeCount = max(0, self.pendingSizeCount - 1)
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingSizeCount = 0
            self.isEnriching = false
            ScanCacheStore.save(self.projects)
        }
    }

    private func startCommitActivityRefresh(for projects: [RepoProject]) {
        commitActivityTask?.cancel()
        let snapshotProjects = projects
        guard !snapshotProjects.isEmpty else {
            commitActivity = .empty
            return
        }
        let existing = commitActivity
        commitActivityTask = Task(priority: .utility) { @MainActor [weak self] in
            let updated = await Task.detached(priority: .utility) {
                let fresh = await CommitActivityService.refresh(
                    projects: snapshotProjects,
                    cached: existing
                )
                CommitActivityService.saveCache(fresh)
                return fresh
            }.value
            guard let self, !Task.isCancelled else { return }
            self.commitActivity = updated
        }
    }

    private func requestNotificationsIfNeeded() async {
        let status = await SystemPermissionService.notificationPermission()
        if status == .notDetermined {
            _ = await SystemPermissionService.requestNotifications()
        }
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
        forgetDoctorReport(project.path)
        syncFocusedChecks()
        remotes.removeValue(forKey: project.path)
        missingRemotes.remove(project.path)
        remoteTasks[project.path]?.cancel()
        remoteTasks[project.path] = nil
        recentProjectPaths.removeAll { $0 == project.path }
        preferences.set(recentProjectPaths, forKey: Self.recentProjectsKey)

        if destination.projectPath == project.path {
            destination = .dashboard
            requestedTab = nil
        }
        return result
    }

    func openDashboard() {
        destination = .dashboard
        requestedTab = nil
        requestedSessionID = nil
        isCommandPalettePresented = false
    }

    func openConversations() {
        destination = .conversations
        requestedTab = nil
        requestedSessionID = nil
        isCommandPalettePresented = false
    }

    func openLibrary(_ query: LibraryQuery = LibraryQuery()) {
        destination = .library(query)
        requestedTab = nil
        requestedSessionID = nil
        isCommandPalettePresented = false
    }

    func openCleanup() {
        destination = .cleanup
        requestedTab = nil
        requestedSessionID = nil
        isCommandPalettePresented = false
    }

    func openProject(_ project: RepoProject, tab: ProjectTab? = nil, sessionID: String? = nil) {
        destination = .project(project.path)
        requestedTab = tab
        requestedSessionID = sessionID
        isCommandPalettePresented = false
    }

    func marks(for projectPath: String) -> [SessionMark] {
        MarkStore.marks(for: projectPath, in: marks)
    }

    func reloadMarks() {
        marks = MarkStore.load()
    }

    func openProjectDiff(project: RepoProject, markID: String) {
        requestedMarkIDForDiff = markID
        openProject(project, tab: .progress)
    }

    func openProjectSaveVersion(project: RepoProject) {
        requestedSaveVersionForPath = project.path
        openProject(project, tab: .version)
    }

    @discardableResult
    func createMark(
        for project: RepoProject,
        session: SessionRecord? = nil,
        label: String? = nil,
        allowGitSnapshot: Bool? = nil
    ) async -> SessionMark {
        let allowSnapshot = allowGitSnapshot ?? MarkPreferences.implicitMarksEnabled()
        let mark = await SessionMarkService.createMark(
            for: URL(fileURLWithPath: project.path),
            sessionID: session?.id,
            sessionStableID: session?.stableID,
            tool: session?.tool,
            label: label,
            allowGitSnapshot: allowSnapshot
        )
        marks = MarkStore.upsert(mark)

        if mark.kind == .gitSnapshot, !MarkPreferences.firstMarkToastShown() {
            MarkPreferences.setFirstMarkToastShown(true)
            ToastCenter.shared.show(
                "已为这次对话记下开始前的样子，保留约 14 天",
                symbol: "bookmark.circle.fill",
                tint: .secondary,
                duration: 4.0,
                subtitle: "以后随时可在进度时间线对比或还原"
            )
        }
        return mark
    }

    @discardableResult
    func togglePin(mark: SessionMark) async -> Bool {
        let updatedPinned = !mark.pinned
        let ok = await SessionMarkService.setPinned(
            updatedPinned,
            mark: mark,
            in: URL(fileURLWithPath: mark.projectPath)
        )
        guard ok else { return false }
        var copy = mark
        copy.pinned = updatedPinned
        marks = MarkStore.upsert(copy)
        return true
    }

    func recordRecentProject(_ path: String) {
        guard path != Self.homeSelection, !path.hasPrefix(Self.filterPrefix) else { return }
        var list = recentProjectPaths.filter { $0 != path }
        list.insert(path, at: 0)
        let next = Array(list.prefix(8))
        guard next != recentProjectPaths else { return }
        recentProjectPaths = next
        preferences.set(next, forKey: Self.recentProjectsKey)
    }

    func recordPaletteAction(_ id: String) {
        guard !id.hasPrefix("project.") else { return }
        var list = recentActionIDs.filter { $0 != id }
        list.insert(id, at: 0)
        let next = Array(list.prefix(6))
        guard next != recentActionIDs else { return }
        recentActionIDs = next
        preferences.set(next, forKey: Self.recentActionsKey)
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
        syncFocusedChecks()
    }

    func setStarred(_ starred: Bool, for targets: [RepoProject]) {
        guard !targets.isEmpty else { return }
        let targetPaths = Set(targets.map(\.path))
        var changed = false
        for index in projects.indices where targetPaths.contains(projects[index].path) {
            projects[index].starred = starred
            var meta = metadata[projects[index].path] ?? ProjectMeta()
            meta.starred = starred
            metadata[projects[index].path] = meta
            changed = true
        }
        if changed {
            try? MetaStore.save(metadata)
            syncFocusedChecks()
        }
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

    @discardableResult
    func setCustomArtwork(from sourceURL: URL, for project: RepoProject) -> Bool {
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return false }
        let previous = metadata[project.path]?.customArtwork ?? projects[index].customArtwork
        guard let savedPath = try? ProjectArtwork.saveCustomArtwork(
            from: sourceURL,
            for: project.path,
            existingCustomPath: previous
        ) else { return false }

        projects[index].customArtwork = savedPath
        projects[index].artwork = savedPath
        var meta = metadata[project.path] ?? ProjectMeta()
        meta.customArtwork = savedPath
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
        ScanCacheStore.save(projects)
        return true
    }

    func clearCustomArtwork(for project: RepoProject) {
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return }
        let existing = metadata[project.path]?.customArtwork ?? projects[index].customArtwork
        ProjectArtwork.removeCustomArtwork(at: existing)

        var meta = metadata[project.path] ?? ProjectMeta()
        meta.customArtwork = nil
        metadata[project.path] = meta
        projects[index].customArtwork = nil
        projects[index].artwork = ProjectArtwork.find(in: URL(fileURLWithPath: project.path))
        try? MetaStore.save(metadata)
        ScanCacheStore.save(projects)
    }

    func setGroup(_ group: String?, for project: RepoProject) {
        guard let index = projects.firstIndex(where: { $0.path == project.path }) else { return }
        let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed?.isEmpty == false ? trimmed : nil
        projects[index].group = value ?? ProjectGrouping.detected(for: project.path, kind: project.kind)

        var meta = metadata[project.path] ?? ProjectMeta()
        meta.group = value
        metadata[project.path] = meta
        try? MetaStore.save(metadata)
        ScanCacheStore.save(projects)
    }

    func setGroup(_ group: String?, for targets: [RepoProject]) {
        guard !targets.isEmpty else { return }
        let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed?.isEmpty == false ? trimmed : nil
        let targetPaths = Set(targets.map(\.path))
        var changed = false
        for index in projects.indices where targetPaths.contains(projects[index].path) {
            projects[index].group = value ?? ProjectGrouping.detected(
                for: projects[index].path,
                kind: projects[index].kind
            )
            var meta = metadata[projects[index].path] ?? ProjectMeta()
            meta.group = value
            metadata[projects[index].path] = meta
            changed = true
        }
        if changed {
            try? MetaStore.save(metadata)
            ScanCacheStore.save(projects)
        }
    }

    var knownGroups: [String] {
        ProjectGrouping.ordered(projects.map(\.group))
    }

    func setPort(_ state: PortState, for path: String) {
        guard let index = projects.firstIndex(where: { $0.path == path }), projects[index].port != state else { return }
        projects[index].port = state
        syncFocusedChecks()
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

        let headChanged = projects[index].lastCommit?.hash != git.lastCommit?.hash
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
        updateCloudReport(for: projects[index])
        if headChanged {
            syncFocusedChecks()
            startCommitActivityRefresh(for: projects)
        }
    }

    func startWatchingGit(for path: String) {
        workspaceWatcher?.setGitPath(path)
    }

    func stopWatchingGit() {
        workspaceWatcher?.setGitPath(nil)
    }

    func refreshSessions() async {
        guard !projects.isEmpty else { return }
        if phase == .scanning || isRefreshingSessions {
            refreshSessionsAfterScan = true
            scheduleDeferredSessionRefresh()
            return
        }
        isRefreshingSessions = true
        defer { isRefreshingSessions = false }

        let index = await Task.detached(priority: .utility) {
            SessionIndex.build()
        }.value
        guard !Task.isCancelled else { return }

        var updated = projects
        for position in updated.indices {
            let sessions = SessionIndex.summary(
                for: URL(fileURLWithPath: updated[position].path),
                in: index
            )
            var tools = updated[position].detectedTools
            for rawTool in sessions.detected {
                if let detected = DetectedTool(rawValue: rawTool), !tools.contains(detected) {
                    tools.append(detected)
                }
            }
            updated[position].detectedTools = DetectedTool.allCases.filter { tools.contains($0) }
            updated[position].sessions = sessions
            updated[position].sessionLoadState = .ready
        }
        projects = updated
        syncFocusedChecks()
        ScanCacheStore.save(projects)
        pruneRemotes(for: projects)
        scheduleSessionSearchRebuild()
        Task { await refreshActiveAISessions() }
    }

    func scheduleSessionSearchRebuild() {
        let snapshot = projects
        let headlines = SummaryEngine.shared.sessionSummaries.mapValues(\.headline)
        sessionSearchRebuildTask?.cancel()
        sessionSearchRebuildTask = Task(priority: .utility) { @MainActor [weak self] in
            await Task.detached(priority: .utility) {
                await SessionSearchIndex.shared.rebuild(from: snapshot, aiHeadlines: headlines)
            }.value
            guard !Task.isCancelled else { return }
            self?.hasIndexedSessionSearch = true
        }
    }

    func searchSessions(
        query: String,
        toolFilter: String? = nil,
        errorOnly: Bool = false,
        limit: Int = 40
    ) async -> [SessionSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if hasIndexedSessionSearch {
            return await SessionSearchIndex.shared.search(
                query: trimmed,
                toolFilter: toolFilter,
                errorOnly: errorOnly,
                limit: limit
            )
        }
        scheduleSessionSearchRebuild()
        let headlines = SummaryEngine.shared.sessionSummaries.mapValues(\.headline)
        return SessionSearchIndex.inMemorySearch(
            projects: projects,
            query: trimmed,
            aiHeadlines: headlines,
            toolFilter: toolFilter,
            errorOnly: errorOnly,
            limit: limit
        )
    }

    func relatedSessions(
        forFile file: String,
        in project: RepoProject,
        limit: Int = 30
    ) async -> [SessionSearchResult] {
        if hasIndexedSessionSearch {
            let indexed = await SessionSearchIndex.shared.sessions(
                touchingFile: file,
                projectPath: project.path,
                limit: limit
            )
            if !indexed.isEmpty {
                return indexed
            }
        }

        scheduleSessionSearchRebuild()
        let headlines = SummaryEngine.shared.sessionSummaries.mapValues(\.headline)
        return SessionSearchIndex.inMemorySessions(
            touchingFile: file,
            projectPath: project.path,
            projects: projects,
            aiHeadlines: headlines,
            limit: limit
        )
    }

    func preferredMark(for session: SessionRecord, in project: RepoProject) -> SessionMark? {
        preferredMark(
            sessionStableID: session.stableID,
            sessionID: session.id,
            startedAt: session.startedAt,
            modified: session.modified,
            projectPath: project.path
        )
    }

    func preferredMark(
        sessionStableID: String,
        sessionID: String,
        startedAt: Date?,
        modified: Date,
        projectPath: String
    ) -> SessionMark? {
        let projectMarks = marks(for: projectPath)
        if let exact = projectMarks.first(where: {
            $0.sessionStableID == sessionStableID || $0.sessionID == sessionID
        }) {
            return exact
        }

        let anchor = startedAt ?? modified
        return projectMarks.first { mark in
            let delta = anchor.timeIntervalSince(mark.createdAt)
            return delta >= -120 && delta <= 900
        }
    }

    var focusedDoctorIssueCount: Int {
        let focused = ProjectFocusPolicy.partition(projects: projects).focused
        return focused.reduce(0) { sum, entry in
            sum + (doctorReports[entry.project.path]?.actionableCount ?? 0)
        }
    }

    func refreshDoctorForFocused(includeIdle: Bool = false, force: Bool = true) async {
        guard !isRunningDoctor, !projects.isEmpty,
              force || Date().timeIntervalSince(lastFullDoctorPageCheck ?? .distantPast) >= 300 else { return }
        isRunningDoctor = true
        defer { isRunningDoctor = false }
        let partition = ProjectFocusPolicy.partition(projects: projects)
        // Bound expensive page checks, but give unexamined projects the next turn in both groups.
        func batch(_ candidates: [RepoProject]) -> ArraySlice<RepoProject> {
            candidates.sorted { (fullDoctorDates[$0.path] ?? .distantPast) < (fullDoctorDates[$1.path] ?? .distantPast) }
                .prefix(ProjectFocusPolicy.defaultMaxFocused)
        }
        for project in batch(partition.focused.map(\.project)) {
            guard !Task.isCancelled else { return }
            await refreshDoctor(for: project, scope: .focused, force: force)
        }
        if includeIdle {
            for project in batch(partition.idle) {
                guard !Task.isCancelled else { return }
                await refreshDoctor(for: project, scope: .idle, force: force)
            }
        }
        if !Task.isCancelled { lastFullDoctorPageCheck = Date() }
    }

    func refreshDoctor(for project: RepoProject, scope: DoctorCheckScope = .focused, force: Bool = true) async {
        let path = project.path
        guard projects.contains(where: { $0.path == path }), !Task.isCancelled,
              force || lastFullDoctorScope[path] != scope || Date().timeIntervalSince(fullDoctorDates[path] ?? .distantPast) >= 300,
              checkingProjects.insert(path).inserted else { return }
        defer { checkingProjects.remove(path) }
        let revision = l0Revision[path]
        let report = await DoctorService.inspectProject(project, scope: scope, copyMode: CopyModePreferences.mode())
        guard !Task.isCancelled, let current = projects.first(where: { $0.path == path }) else { return }
        let issues: [DoctorIssue]
        if revision != l0Revision[path], let newer = rawDoctorReports[path] {
            issues = report.issues.filter { !DoctorService.l0Kinds.contains($0.kind) } + newer.issues.filter { DoctorService.l0Kinds.contains($0.kind) }
        } else { issues = report.issues }
        fullDoctorDates[path] = report.checkedAt
        lastFullDoctorScope[path] = scope
        publishDoctor(issues, for: current)
    }

    private func publishDoctor(_ issues: [DoctorIssue], for project: RepoProject) {
        var issues = issues.filter { $0.kind != .cloudBehind }
        if let cloud = DoctorService.cloudIssue(for: project) { issues.append(cloud) }
        let report = DoctorService.report(for: project.path, issues: issues)
        rawDoctorReports[project.path] = report
        doctorReports[project.path] = report.applying(doctorExemptions(for: project))
        lastDoctorCheckAt = report.checkedAt
    }

    private func updateCloudReport(for project: RepoProject) {
        guard let report = rawDoctorReports[project.path] else {
            if project.behind > 0 { publishDoctor([], for: project) }
            return
        }
        let previous = report.issues.first { $0.kind == .cloudBehind }
        if previous != DoctorService.cloudIssue(for: project) { publishDoctor(report.issues, for: project) }
    }

    func doctorExemptions(for project: RepoProject) -> Set<DoctorIssueKind> {
        metadata[project.path]?.doctorExemptions ?? []
    }

    func exemptibleIssues(for project: RepoProject) -> [DoctorIssueKind] {
        let kinds = rawDoctorReports[project.path]?.issues.compactMap { $0.severity != .critical && $0.kind.canExempt ? $0.kind : nil } ?? []
        return Set(kinds).union(doctorExemptions(for: project)).sorted { $0.rawValue < $1.rawValue }
    }

    func setDoctorExemption(_ kind: DoctorIssueKind, exempt: Bool, for project: RepoProject) {
        guard kind.canExempt, projects.contains(where: { $0.path == project.path }) else { return }
        var meta = metadata[project.path] ?? ProjectMeta()
        if exempt { meta.doctorExemptions.insert(kind) } else { meta.doctorExemptions.remove(kind) }
        do { try MetaStore.saveDoctorExemptions(meta.doctorExemptions, for: project.path) } catch {
            ToastCenter.shared.show("未能保存体检豁免", symbol: "exclamationmark.triangle", tint: FizzTheme.statusWarning)
            return
        }
        metadata[project.path] = meta
        doctorReports[project.path] = rawDoctorReports[project.path]?.applying(meta.doctorExemptions)
    }

    private func forgetDoctorReport(_ path: String) {
        rawDoctorReports[path] = nil
        doctorReports[path] = nil
        fullDoctorDates[path] = nil
        lastFullDoctorScope[path] = nil
        l0Revision[path] = nil
        pendingL0Paths.remove(path)
    }

    private func syncFocusedChecks() {
        let focused = ProjectFocusPolicy.partition(projects: projects).focused
        if let watcher = workspaceWatcher {
            watcher.setFocusedPaths(focused.map(\.id)) // Only the file watcher caps persistent subscriptions.
            pendingL0Paths.formIntersection(watcher.focusedPaths)
        }
        guard scannedAt != nil else { return }
        let candidates = focused.compactMap { entry -> String? in
            let project = entry.project
            guard project.gitLoadState == .ready else { return nil }
            updateCloudReport(for: project)
            guard let branch = project.branch, branch != "HEAD", project.lastCommit != nil else { return nil }
            return project.path
        }
        scheduleQuietFetch(for: candidates)
    }

    private func enqueueL0(_ path: String) {
        guard workspaceWatcher?.focusedPaths.contains(path) == true else { return }
        pendingL0Paths.insert(path)
        guard l0Task == nil else { return }
        l0Task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { l0Task = nil }
            while let path = pendingL0Paths.popFirst() {
                guard let project = projects.first(where: { $0.path == path }), workspaceWatcher?.isPaused == false else { continue }
                let fresh = await DoctorService.inspectL0(project, copyMode: CopyModePreferences.mode())
                guard workspaceWatcher?.focusedPaths.contains(path) == true, let current = projects.first(where: { $0.path == path }) else { continue }
                let other = rawDoctorReports[path]?.issues.filter { !DoctorService.l0Kinds.contains($0.kind) } ?? []
                l0Revision[path, default: 0] += 1
                publishDoctor(other + fresh.issues, for: current)
            }
        }
    }

    private func scheduleQuietFetch(for paths: [String]) {
        let targets = Set(paths), now = quietFetchNow()
        nextQuietFetch = nextQuietFetch.filter { targets.contains($0.key) }
        pendingQuietFetch = pendingQuietFetch.filter(targets.contains)[...]
        var queued = Set(pendingQuietFetch)
        for path in paths where path != activeQuietFetch && now >= (nextQuietFetch[path] ?? .distantPast) && queued.insert(path).inserted {
            pendingQuietFetch.append(path)
        }
        guard quietFetchTask == nil, !pendingQuietFetch.isEmpty else { return }
        quietFetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { quietFetchTask = nil; activeQuietFetch = nil; pendingQuietFetch = [] }
            while let path = pendingQuietFetch.popFirst() {
                activeQuietFetch = path
                let attempt = await quietFetchAttempts.reserve(path: path, now: quietFetchNow())
                nextQuietFetch[path] = attempt.next
                guard attempt.allowed, let result = await checkRemote(URL(fileURLWithPath: path)),
                      let i = projects.firstIndex(where: { $0.path == path }), projects[i].branch == result.branch,
                      let abbreviated = projects[i].lastCommit?.hash, abbreviated.count >= 7, result.head.hasPrefix(abbreviated) else { continue }
                projects[i].behind = result.counts.behind
                projects[i].ahead = result.counts.ahead
                updateCloudReport(for: projects[i])
            }
        }
    }

    func refreshMachineEnvironment(force: Bool = true) async {
        guard force || machineEnv == nil else { return }
        machineEnv = await DoctorService.inspectMachineEnvironment()
    }

    func refreshActiveAISessions() async {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        var recentSessions: [SessionRecord] = []
        var contextBySessionID: [String: (project: RepoProject, session: SessionRecord)] = [:]

        for project in projects {
            for session in project.sessions.recentSessions
            where session.kind == .conversation && session.modified >= cutoff {
                recentSessions.append(session)
                contextBySessionID[session.stableID] = (project, session)
            }
        }

        let live: [String: [Int32]] = recentSessions.isEmpty
            ? [:]
            : await SessionProcessService.liveProcesses(for: recentSessions)
        let activeIDs = Set(live.keys)
        let activePaths = Set(activeIDs.compactMap { contextBySessionID[$0]?.project.path })
        if activeAISessionIDs != activeIDs {
            activeAISessionIDs = activeIDs
        }
        if activeAIProjectPaths != activePaths {
            activeAIProjectPaths = activePaths
        }

        guard hasSeededActiveAISessions else {
            hasSeededActiveAISessions = true
            previousActiveAISessionIDs = activeIDs
            return
        }

        let startedIDs = activeIDs.subtracting(previousActiveAISessionIDs)
        let endedIDs = previousActiveAISessionIDs.subtracting(activeIDs)
        previousActiveAISessionIDs = activeIDs

        if MarkPreferences.implicitMarksEnabled() {
            for id in startedIDs {
                guard let context = contextBySessionID[id] else { continue }
                let alreadyMarked = marks.contains { $0.sessionStableID == id }
                guard !alreadyMarked else { continue }
                Task { @MainActor [weak self] in
                    _ = await self?.createMark(
                        for: context.project,
                        session: context.session,
                        label: "对话开始前的样子",
                        allowGitSnapshot: true
                    )
                }
            }
        }

        for id in endedIDs {
            guard let context = contextBySessionID[id] else { continue }
            Task { @MainActor [weak self] in
                await self?.handleAISessionEnded(project: context.project, session: context.session)
            }
        }
    }

    private func handleAISessionEnded(project: RepoProject, session: SessionRecord) async {
        await refreshGit(for: project.path)
        let updatedProject = projects.first { $0.path == project.path } ?? project
        let copyMode = CopyModePreferences.mode()
        let issues = await LightweightProjectCheckService.check(
            directory: URL(fileURLWithPath: updatedProject.path),
            copyMode: copyMode
        )

        if session.endedWithError {
            let errSubtitle = session.lastError.map { String($0.prefix(80)) }
            ToastCenter.shared.show(
                "「\(updatedProject.displayName)」的对话以报错结束",
                symbol: "exclamationmark.triangle.fill",
                tint: FizzTheme.statusWarning,
                subtitle: errSubtitle,
                action: ToastAction(title: "去看看", symbol: "arrow.right.circle") { [weak self] in
                    self?.openProject(updatedProject, tab: .progress, sessionID: session.id)
                }
            )
            return
        }

        let changedCount = max(updatedProject.dirtyCount, session.touchedFiles.count)
        guard (updatedProject.dirtyCount > 0 || !issues.isEmpty),
              !MarkPreferences.saveVersionToastDisabled() else {
            return
        }

        let now = Date()
        if let lastShown = lastSessionFinishToastByProject[updatedProject.path],
           now.timeIntervalSince(lastShown) < 30 * 60 {
            return
        }
        lastSessionFinishToastByProject[updatedProject.path] = now

        let subtitle = issues.first?.title ?? "可查看改动或顺手存个版本"
        let toolTitle = HomeDashboardModel.toolTitle(session.tool)
        let mark = marks(for: updatedProject.path).first { $0.kind == .gitSnapshot }
        let action: ToastAction = if let mark {
            ToastAction(title: "看改了什么", symbol: "doc.text.magnifyingglass") { [weak self] in
                self?.openProjectDiff(project: updatedProject, markID: mark.id)
            }
        } else {
            ToastAction(title: "存个版本", symbol: "checkmark.circle") { [weak self] in
                self?.openProjectSaveVersion(project: updatedProject)
            }
        }

        ToastCenter.shared.show(
            "\(toolTitle) 刚在 \(updatedProject.displayName) 改了 \(max(1, changedCount)) 个文件",
            symbol: "sparkles",
            tint: .secondary,
            subtitle: subtitle,
            action: action
        )
    }

    private func scheduleDeferredSessionRefresh() {
        guard scheduledSessionRefresh == nil else { return }
        scheduledSessionRefresh = Task { @MainActor [weak self] in
            defer { self?.scheduledSessionRefresh = nil }
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            guard self.phase != .scanning, self.refreshSessionsAfterScan else { return }
            self.refreshSessionsAfterScan = false
            await self.refreshSessions()
        }
    }

    private func flushDeferredSessionRefresh() {
        guard refreshSessionsAfterScan else { return }
        refreshSessionsAfterScan = false
        scheduledSessionRefresh?.cancel()
        scheduledSessionRefresh = nil
        Task { @MainActor [weak self] in
            await self?.refreshSessions()
        }
    }

    private func startWorkspaceWatcher() {
        guard workspaceWatcher == nil else { return }
        let watcher = WorkspaceWatcher(onActivation: { [weak self] in self?.syncFocusedChecks() }) { [weak self] change in
            guard let self else { return }
            switch change {
            case .manifest(let path):
                self.enqueueL0(path)
            case .sessions:
                Task { @MainActor [weak self] in
                    await self?.refreshSessions()
                }
            case .git:
                guard let path = self.selectedProject?.path else { return }
                Task { @MainActor [weak self] in
                    await self?.refreshGit(for: path)
                }
            }
        }
        watcher.setGitPath(selectedProject?.path)
        watcher.start()
        workspaceWatcher = watcher
        syncFocusedChecks()
    }

    func isAttentionSuppressed(
        for project: RepoProject,
        kind: ProjectAttentionKind,
        at date: Date = Date()
    ) -> Bool {
        (kind == .behind && doctorExemptions(for: project).contains(.cloudBehind))
            || (attentionPreference(for: project, kind: kind)?.suppresses(at: date) ?? false)
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
