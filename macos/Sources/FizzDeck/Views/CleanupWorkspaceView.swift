import SwiftUI

struct CleanupWorkspaceView: View {
    @Environment(RepositoryStore.self) private var store
    @State private var feedback: String?

    private var cleanableProjects: [RepoProject] {
        store.projects
            .filter { !$0.cleanup.items.isEmpty }
            .sorted { $0.cleanup.reusableBytes > $1.cleanup.reusableBytes }
    }

    private var totalBytes: Int64 {
        cleanableProjects.reduce(0) { $0 + $1.cleanup.reusableBytes }
    }

    private var totalItemCount: Int {
        cleanableProjects.reduce(0) { $0 + $1.cleanup.items.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                header

                if cleanableProjects.isEmpty {
                    ContentUnavailableView {
                        Label("没有可清理项", systemImage: "archivebox")
                    } description: {
                        Text("已扫描的项目中没有命中依赖、构建产物或缓存清理规则的目录。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(spacing: FizzSpacing.grid) {
                        ForEach(cleanableProjects) { project in
                            projectCard(project)
                        }
                    }
                }
            }
            .padding(FizzSpacing.page)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("可清理")
                        .font(.system(size: 27, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(headerSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 12)

                if !cleanableProjects.isEmpty {
                    Button {
                        copyAllCommands()
                    } label: {
                        Label("复制全部命令", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            if let feedback {
                HStack(spacing: 5) {
                    FizzIcon(symbol: "info.circle", size: 11)
                        .foregroundStyle(FizzTheme.accent)
                    Text(feedback)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerSubtitle: String {
        if cleanableProjects.isEmpty {
            return "只复制清理命令，不自动删除文件"
        }
        return "\(Format.bytes(totalBytes)) · \(cleanableProjects.count) 个项目 · \(totalItemCount) 个目录 · 只复制命令，不自动删除"
    }

    private func projectCard(_ project: RepoProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProjectBadgeIcon(project: project, size: 26, framed: false)

                Button {
                    store.openProject(project, tab: .cleanup)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("\(project.cleanup.items.count) 个目录")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("打开 \(project.displayName) 的清理页")

                Spacer(minLength: 8)

                Text(Format.bytes(project.cleanup.reusableBytes))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.orange)

                Button("复制") {
                    SystemActions.copy(
                        "# \(project.displayName)\n\(project.cleanup.removalCommand)",
                        microViz: .compact(state: .done)
                    )
                    feedback = "已复制 \(project.displayName) 的清理命令"
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 14)
                .opacity(0.45)

            VStack(spacing: 0) {
                ForEach(project.cleanup.items) { item in
                    cleanupRow(item, project: project)
                    if item != project.cleanup.items.last {
                        Divider()
                            .padding(.leading, 44)
                            .opacity(0.28)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .fizzCard(radius: FizzRadius.panel)
    }

    private func cleanupRow(_ item: CleanupItem, project: RepoProject) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FizzIcon(symbol: "folder", size: 12)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text(Format.bytes(item.bytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Text(item.reason)
                    if !item.regen.isEmpty {
                        Text("·")
                        Text(item.regen)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                SystemActions.copy(
                    project.cleanup.removalCommand(for: item),
                    microViz: .compact(state: .done)
                )
                feedback = "已复制 \(project.displayName)/\(item.label) 清理命令"
            } label: {
                FizzIcon(symbol: "doc.on.doc", size: 11)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("复制删除命令")
            .accessibilityLabel("复制 \(item.label) 删除命令")
        }
        .padding(.vertical, 7)
    }

    private func copyAllCommands() {
        let blocks = cleanableProjects.compactMap { project -> String? in
            let command = project.cleanup.removalCommand
            guard !command.isEmpty else { return nil }
            return "# \(project.displayName)\n\(command)"
        }
        guard !blocks.isEmpty else { return }
        SystemActions.copy(
            blocks.joined(separator: "\n"),
            microViz: .compact(state: .done)
        )
        feedback = "已复制 \(blocks.count) 个项目的全部清理命令"
    }
}
