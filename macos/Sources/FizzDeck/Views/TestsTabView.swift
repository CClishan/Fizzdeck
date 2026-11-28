import SwiftUI

struct TestsTabView: View {
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject

    private var runState: TestRunState? {
        actions.testRun(for: project.path)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Panel(
                    title: "提交测试",
                    symbol: "checkmark.shield",
                    content: {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.test?.command ?? "未识别测试命令")
                                    .font(FizzTypography.font(12))
                                    .textSelection(.enabled)
                                if let test = project.test {
                                    Text("来自 \(test.label)")
                                        .font(FizzTypography.micro(.regular))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let output = runState?.output, !output.isEmpty {
                                ScrollView {
                                    Text(output)
                                        .font(FizzTypography.caption)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                }
                                .frame(minHeight: 220, maxHeight: 460)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                                        .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
                                }
                            } else {
                                ContentUnavailableView {
                                    Label("还没有测试输出", systemImage: "terminal")
                                } description: {
                                    Text(project.test == nil ? "这个项目没有 test / check / typecheck 脚本。" : "底栏「运行测试」会在项目目录执行命令，并实时回显输出。")
                                }
                                .frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }
                    },
                    accessory: {
                        statusBadge
                    }
                )
            }
            .padding(24)
        }
        .fizzTracksScrollPastTop()
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let run = runState {
            TagChip(text: statusText(run), tint: statusColor(run.status))
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
        case .passed: FizzTheme.statusSuccess
        case .failed: FizzTheme.statusDanger
        }
    }
}
