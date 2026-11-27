import SwiftUI

struct WorkbenchStatusCard: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    let runningProjects: [RepoProject]
    let healthAlerts: [HealthAlert]

    private var activeAIProjects: [RepoProject] {
        store.projects
            .filter { store.activeAIProjectPaths.contains($0.path) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var hasContent: Bool {
        !runningProjects.isEmpty || !activeAIProjects.isEmpty || !healthAlerts.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 14) {
                if !runningProjects.isEmpty || !activeAIProjects.isEmpty {
                    runningSection
                }

                if (!runningProjects.isEmpty || !activeAIProjects.isEmpty) && !healthAlerts.isEmpty {
                    Divider()
                        .opacity(0.45)
                }

                if !healthAlerts.isEmpty {
                    healthSection
                }
            }
            .padding(16)
            .fizzCard(radius: FizzRadius.panel)
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RunningPulseDot(size: 7)
                Text("正在运行")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(runningProjects.count + activeAIProjects.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            ForEach(runningProjects) { project in
                HStack(spacing: 8) {
                    Button {
                        store.openProject(project)
                    } label: {
                        HStack(spacing: 7) {
                            ProjectBadgeIcon(project: project, size: 20, framed: false)
                            Text(project.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)

                    if let port = project.run?.port, port > 0 {
                        Text(verbatim: ":\(port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    if let preview = project.run?.previewURL {
                        Button(copyMode == .plain ? "打开看看" : "预览") {
                            SystemActions.openURL(preview)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.mini)
                    } else if let port = project.run?.port, port > 0 {
                        Button(copyMode == .plain ? "打开看看" : "预览") {
                            SystemActions.openURL("http://127.0.0.1:\(port)")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.mini)
                    }

                    Button("停止") {
                        Task { await actions.stop(project, store: store) }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                    .disabled(actions.isBusy(project.path))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    FizzTheme.recessedFill,
                    in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                )
            }

            ForEach(activeAIProjects) { project in
                HStack(spacing: 8) {
                    RunningPulseDot(size: 6)
                    ProjectBadgeIcon(project: project, size: 18, framed: false)
                    Text("AI 正在 \(project.displayName) 里干活")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("去看看") {
                        store.openProject(project, tab: .progress)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    FizzTheme.recessedFill,
                    in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                )
            }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                FizzIcon(symbol: "exclamationmark.triangle", size: 12)
                    .foregroundStyle(.orange)
                Text("健康提醒")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }

            ForEach(healthAlerts) { alert in
                HStack(spacing: 8) {
                    FizzIcon(symbol: alertSymbol(alert.kind), size: 12)
                        .foregroundStyle(.orange)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(alert.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    switch alert.kind {
                    case .highCleanup:
                        Button("去清理") {
                            store.openCleanup()
                        }
                        .buttonStyle(.glass)
                        .controlSize(.mini)
                    case .staleDirty:
                        if let path = alert.targetProjectPath,
                           let project = store.projects.first(where: { $0.path == path }) {
                            Button("查看") {
                                store.openProject(project, tab: .version)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                        }
                    case .lowDisk:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    FizzTheme.recessedFill,
                    in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                )
            }
        }
    }

    private func alertSymbol(_ kind: HealthAlert.Kind) -> String {
        switch kind {
        case .lowDisk: "internaldrive"
        case .highCleanup: "archivebox"
        case .staleDirty: "exclamationmark.triangle"
        }
    }
}
