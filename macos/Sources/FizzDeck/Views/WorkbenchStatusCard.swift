import SwiftUI

struct WorkbenchStatusCard: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions

    let runningProjects: [RepoProject]
    let cloudProjects: [RepoProject]
    let healthAlerts: [HealthAlert]

    private var activeAIProjects: [RepoProject] {
        store.projects
            .filter { store.activeAIProjectPaths.contains($0.path) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        let active = activeAIProjects
        if !runningProjects.isEmpty || !active.isEmpty || !healthAlerts.isEmpty || !cloudProjects.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("运行与健康")
                    .font(FizzTypography.caption(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(runningProjects) { project in runningRow(project) }
                ForEach(active) { project in
                    HStack(spacing: FizzSpacing.row) {
                        RunningPulseDot()
                        Text("AI 正在 \(project.displayName) 里干活")
                        Spacer(minLength: FizzSpacing.row)
                        FizzActionButton(title: "去看看", height: .compact) {
                            store.openProject(project, tab: .progress)
                        }
                    }
                }
                ForEach(healthAlerts) { alert in healthRow(alert) }
                ForEach(cloudProjects) { project in
                    HStack(spacing: FizzSpacing.row) {
                        FizzStatusDot(tint: FizzTheme.statusWarning)
                        Text(project.displayName)
                        Text("云端领先 \(project.behind) 个提交").foregroundStyle(.secondary)
                        Spacer(minLength: FizzSpacing.row)
                        FizzIconButton(title: "查看版本", symbol: "chevron.right", height: .compact) {
                            store.openProject(project, tab: .version)
                        }
                    }
                }
            }
            .font(FizzTypography.caption)
            .padding(.horizontal, FizzSpacing.panel)
            .padding(.vertical, FizzSpacing.row)
            .fizzCard()
        }
    }

    private func runningRow(_ project: RepoProject) -> some View {
        HStack(spacing: FizzSpacing.row) {
            FizzStatusDot(tint: FizzTheme.statusSuccess)
            Button(project.displayName) { store.openProject(project) }
                .buttonStyle(.plain)
                .accessibilityHint("服务正在运行")
            if let port = project.run?.port, port > 0 {
                Text(verbatim: ":\(port)")
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: FizzSpacing.row)
            FizzActionButton(title: "停止…", height: .compact, role: .destructive) {
                Task { await actions.stop(project, store: store) }
            }
            .disabled(actions.isBusy(project.path))
            if let preview = previewURL(project) {
                FizzIconButton(title: "预览", symbol: "arrow.up.right", height: .compact) {
                    SystemActions.openURL(preview)
                }
            }
        }
    }

    private func healthRow(_ alert: HealthAlert) -> some View {
        HStack(spacing: FizzSpacing.row) {
            FizzStatusDot(tint: FizzTheme.statusWarning)
            Text(alert.title)
            Text(alert.detail).foregroundStyle(.secondary)
            Spacer(minLength: FizzSpacing.row)
            switch alert.kind {
            case .highCleanup:
                FizzActionButton(title: "去清理", height: .compact) { store.openCleanup() }
            case .staleDirty:
                if let path = alert.targetProjectPath, let project = store.projects.first(where: { $0.path == path }) {
                    FizzActionButton(title: "查看", height: .compact) { store.openProject(project, tab: .version) }
                }
            case .lowDisk:
                EmptyView()
            }
        }
        .frame(minHeight: FizzControlHeight.compact.rawValue)
    }

    private func previewURL(_ project: RepoProject) -> String? {
        if let url = project.run?.previewURL { return url }
        guard let port = project.run?.port, port > 0 else { return nil }
        return "http://127.0.0.1:\(port)"
    }
}
