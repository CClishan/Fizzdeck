import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RepositoryStore {
    static let homeSelection = "__repodeck_home__"
    static let filterPrefix = "__repodeck_filter__:"

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case failed(String)
    }

    var projects: [RepoProject] = []
    var roots: [String] = []
    var selectedPath: String? = homeSelection
    var query = ""
    var phase: Phase = .idle
    var scannedAt: Date?
    var scanDuration: TimeInterval = 0

    private var metadata: [String: ProjectMeta] = [:]
    private var didPrepare = false

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

        if selectedPath == Self.homeSelection
            || selectedPath?.hasPrefix(Self.filterPrefix) == true {
            return
        }
        if let selectedPath, projects.contains(where: { $0.path == selectedPath }) {
            return
        }
        selectedPath = Self.homeSelection
    }

    func addRoot() async {
        let panel = NSOpenPanel()
        panel.title = "添加项目目录"
        panel.prompt = "添加"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var roots = RootStore.load()
        let path = PathTools.normalize(url.path)
        if !roots.contains(path) {
            roots.append(path)
            try? RootStore.save(roots)
        }
        await scan()
    }

    func removeFromBoard(_ project: RepoProject) async {
        var roots = RootStore.load()
        roots.removeAll { $0 == project.path }
        try? RootStore.save(roots)
        if selectedPath == project.path { selectedPath = Self.homeSelection }
        await scan()
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

    func reloadProjectDetailMetadata() {}
}
