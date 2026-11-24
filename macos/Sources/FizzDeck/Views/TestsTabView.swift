import SwiftUI

struct TestsTabView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject

    private var runState: TestRunState? {
        actions.testRun(for: project.path)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Panel(title: "提交测试", symbol: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.test?.command ?? "未识别测试命令")
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                if let test = project.test {
                                    Text("来自 \(test.label)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 12)
                            statusBadge
                            actionsView
                        }

                        if let output = runState?.output, !output.isEmpty {
                            ScrollView {
                                Text(output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(minHeight: 220, maxHeight: 460)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
                            }
                        } else {
                            ContentUnavailableView {
                                Label("还没有测试输出", systemImage: "terminal")
                            } description: {
                                Text(project.test == nil ? "这个项目没有 test / check / typecheck 脚本。" : "点「跑测试」会在项目目录执行命令，并实时回显输出。")
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let run = runState {
            Text(statusText(run))
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(run.status))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(statusColor(run.status).opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private var actionsView: some View {
        HStack(spacing: 8) {
            if runState?.status == .running {
                Button {
                    actions.stopTests(project)
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    actions.runTests(project, store: store)
                } label: {
                    Label(runState == nil ? "跑测试" : "重跑", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(project.test == nil || runState?.status == .running)
            }

            Button {
                actions.openLog(for: project, test: true)
            } label: {
                Label("日志", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func statusText(_ run: TestRunState) -> String {
        switch run.status {
        case .running:
            "运行中"
        case .passed:
            "通过 · \(String(format: "%.1f", run.duration ?? 0))s"
        case .failed:
            "失败 · \(String(format: "%.1f", run.duration ?? 0))s"
        }
    }

    private func statusColor(_ status: TestStatus) -> Color {
        switch status {
        case .running: .secondary
        case .passed: .green
        case .failed: .red
        }
    }
}
