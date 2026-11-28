import AppIntents
import Foundation

struct ShortcutProject: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "FizzDeck Project"
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
    static let title: LocalizedStringResource = "Open FizzDeck Project"
    static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "Project") var project: ShortcutProject

    @MainActor func perform() async throws -> some IntentResult {
        guard RootStore.load().contains(project.id) else { throw ShortcutProjectError.unavailable }
        AppRouting.openProject(path: project.id, tab: nil)
        return .result()
    }
}

struct CopyFizzHandoffIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Project Handoff Card"
    @Parameter(title: "Project") var project: ShortcutProject

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let projects = await ShortcutProjectData.cachedProjects()
        guard let current = projects.first(where: { $0.path == project.id }) else { throw ShortcutProjectError.unavailable }
        let text = HandoffCardBuilder.build(project: current, copyMode: CopyModePreferences.mode()).markdown
        await MainActor.run { SystemActions.copy(text, feedback: nil) }
        return .result(value: text)
    }
}

struct FocusedFizzDoctorIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Followed Projects"

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
                checked = FizzL10n.text("体检正常", "All checks passed")
            } else {
                report = await DoctorService.inspectL0(entry.project, exemptions: exemptions[entry.id] ?? [])
                checked = FizzL10n.text("轻量体检正常", "Quick checks passed")
            }
            let status = report.actionableCount == 0 ? checked : report.issues.map(\.title).joined(separator: FizzL10n.text("；", "; "))
            lines.append(entry.project.displayName + FizzL10n.text("：", ": ") + status)
        }
        return .result(value: lines.isEmpty ? FizzL10n.text("没有已扫描的关注项目", "No followed projects have been scanned") : lines.joined(separator: "\n"))
    }
}

struct FizzDeckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFizzProjectIntent(), phrases: ["Open a project in \(.applicationName)"], shortTitle: "Open Project", systemImageName: "folder")
        AppShortcut(intent: CopyFizzHandoffIntent(), phrases: ["Copy a handoff card with \(.applicationName)"], shortTitle: "Copy Handoff Card", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: FocusedFizzDoctorIntent(), phrases: ["Check followed projects in \(.applicationName)"], shortTitle: "Check Followed Projects", systemImageName: "stethoscope")
    }
}

private enum ShortcutProjectError: LocalizedError {
    case unavailable
    var errorDescription: String? { FizzL10n.text("项目未加入 FizzDeck 或尚未完成扫描。", "This project hasn’t been added to FizzDeck or hasn’t been scanned yet.") }
}

enum ShortcutProjectData {
    @MainActor static weak var liveStore: RepositoryStore?
    static func cachedProjects() async -> [RepoProject] {
        if let live = await MainActor.run(body: { liveStore?.projects }), !live.isEmpty { return live }
        return await Task.detached(priority: .utility) { ScanCacheStore.load(for: RootStore.load(), meta: MetaStore.load()) }.value
    }
}
