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
                    title: FizzL10n.text("提交测试", "Project tests"),
                    symbol: "checkmark.shield",
                    content: {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.test?.command ?? FizzL10n.text("未识别测试命令", "No test command found"))
                                    .font(FizzTypography.font(12))
                                    .textSelection(.enabled)
                                if let test = project.test {
                                    Text(FizzL10n.text("来自 \(test.label)", "From \(test.label)"))
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
                                    Label(FizzL10n.text("还没有测试输出", "No test output yet"), systemImage: "terminal")
                                } description: {
                                    Text(project.test == nil ? FizzL10n.text("这个项目没有 test / check / typecheck 脚本。", "This project has no test, check or typecheck script.") : FizzL10n.text("底栏「运行测试」会在项目目录执行命令，并实时回显输出。", "Use “Run tests” in the bottom bar to run the command in the project folder and see live output."))
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
            FizzL10n.text("运行中", "Running")
        case .passed:
            FizzL10n.text("通过 · \(String(format: "%.1f", run.duration ?? 0))s", "Passed · \(String(format: "%.1f", run.duration ?? 0))s")
        case .failed:
            FizzL10n.text("失败 · \(String(format: "%.1f", run.duration ?? 0))s", "Failed · \(String(format: "%.1f", run.duration ?? 0))s")
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
