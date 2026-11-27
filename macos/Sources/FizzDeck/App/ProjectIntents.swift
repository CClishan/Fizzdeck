import AppIntents
import Foundation

struct ShortcutProject: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "FizzDeck 项目"
    static let defaultQuery = ShortcutProjectQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", subtitle: "\(PathTools.displayPath(id))") }
}

struct ShortcutProjectQuery: EntityStringQuery {
    private func entities() async -> [ShortcutProject] {
        await Task.detached(priority: .utility) {
            RootStore.load().map { ShortcutProject(id: $0, name: URL(fileURLWithPath: $0).lastPathComponent) }
        }.value
    }
    func entities(for identifiers: [String]) async throws -> [ShortcutProject] {
        let ids = Set(identifiers)
        return await entities().filter { ids.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ShortcutProject] {
        await entities().filter { $0.name.localizedStandardContains(string) || $0.id.localizedStandardContains(string) }
    }
    func suggestedEntities() async throws -> [ShortcutProject] { await entities() }
}

struct OpenFizzProjectIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 FizzDeck 项目"
    static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "项目") var project: ShortcutProject

    @MainActor func perform() async throws -> some IntentResult {
        guard RootStore.load().contains(project.id) else { throw ShortcutProjectError.unavailable }
        AppRouting.openProject(path: project.id, tab: nil)
        return .result()
    }
}

struct CopyFizzHandoffIntent: AppIntent {
    static let title: LocalizedStringResource = "复制项目接力卡"
    @Parameter(title: "项目") var project: ShortcutProject

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let projects = await ShortcutProjectData.cachedProjects()
        guard let current = projects.first(where: { $0.path == project.id }) else { throw ShortcutProjectError.unavailable }
        let text = HandoffCardBuilder.build(project: current, copyMode: CopyModePreferences.mode()).markdown
        await MainActor.run { SystemActions.copy(text, feedback: nil) }
        return .result(value: text)
    }
}

struct FocusedFizzDoctorIntent: AppIntent {
    static let title: LocalizedStringResource = "查询关注项目体检状态"

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let projects = await ShortcutProjectData.cachedProjects()
        let reports = await MainActor.run { ShortcutProjectData.liveStore?.doctorReports ?? [:] }
        let exemptions = await Task.detached(priority: .utility) { MetaStore.load().mapValues(\.doctorExemptions) }.value
        let focused = ProjectFocusPolicy.partition(projects: projects).focused
        var lines: [String] = []
        for entry in focused {
            try Task.checkCancellation()
            let report: DoctorProjectReport
            let checked: String
            if let latest = reports[entry.id] {
                report = latest
                checked = "体检正常"
            } else {
                report = await DoctorService.inspectL0(entry.project, exemptions: exemptions[entry.id] ?? [])
                checked = "轻量体检正常"
            }
            let status = report.actionableCount == 0 ? checked : report.issues.map(\.title).joined(separator: "；")
            lines.append("\(entry.project.displayName)：\(status)")
        }
        return .result(value: lines.isEmpty ? "没有已扫描的关注项目" : lines.joined(separator: "\n"))
    }
}

struct FizzDeckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFizzProjectIntent(), phrases: ["在 \(.applicationName) 打开项目"], shortTitle: "打开项目", systemImageName: "folder")
        AppShortcut(intent: CopyFizzHandoffIntent(), phrases: ["用 \(.applicationName) 复制接力卡"], shortTitle: "复制接力卡", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: FocusedFizzDoctorIntent(), phrases: ["查看 \(.applicationName) 关注项目体检"], shortTitle: "关注项目体检", systemImageName: "stethoscope")
    }
}

private enum ShortcutProjectError: LocalizedError {
    case unavailable
    var errorDescription: String? { "项目未加入 FizzDeck 或尚未完成扫描。" }
}

enum ShortcutProjectData {
    @MainActor static weak var liveStore: RepositoryStore?
    static func cachedProjects() async -> [RepoProject] {
        if let live = await MainActor.run(body: { liveStore?.projects }), !live.isEmpty { return live }
        return await Task.detached(priority: .utility) { ScanCacheStore.load(for: RootStore.load(), meta: MetaStore.load()) }.value
    }
}
