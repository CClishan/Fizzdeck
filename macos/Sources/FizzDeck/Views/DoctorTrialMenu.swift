import SwiftUI

struct DoctorTrialMenu: View {
    let project: RepoProject
    @State private var open = false

    var body: some View {
        let run = ProjectTrialService.shared.runs[project.path]
        FizzActionButton(title: run.map { "\($0.choice.kind.rawValue) · \($0.summary)" } ?? "试跑一下", height: .compact) {
            open = true
        }
        .popover(isPresented: $open) {
            TrialControls(project: project)
                .id(project.path)
                .padding(FizzSpacing.panel)
                .frame(width: 380)
        }
    }
}

struct ProjectTrialPanel: View {
    let project: RepoProject
    var body: some View {
        Panel(title: "项目试跑", symbol: "checkmark.shield") {
            TrialControls(project: project).id(project.path)
        }
    }
}

private struct TrialControls: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject
    private let trials = ProjectTrialService.shared
    @State private var choices: [TrialCommand]?

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            let run = trials.runs[project.path]
            if let choices {
                if choices.isEmpty {
                    Text("未识别到 build、typecheck 或 test 命令")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                }
                ForEach(choices) { choice in
                    HStack(spacing: FizzSpacing.row) {
                        Text(verbatim: choice.command)
                            .font(FizzTypography.mono)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        FizzActionButton(title: "试跑 \(choice.kind.rawValue)", height: .compact) {
                            trials.start(choice, for: project, store: store)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(run?.status == .running || actions.testRun(for: project.path)?.status == .running
                                  || actions.scriptRuns.values.contains { $0.projectPath == project.path && $0.status == .running && $0.script.command == choice.command })
                    }
                }
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("识别试跑命令")
            }
            if let run {
                Divider()
                HStack(spacing: FizzSpacing.row) {
                    Text("\(run.choice.kind.rawValue) · \(run.summary)")
                        .font(FizzTypography.body(.medium))
                    Spacer()
                    FizzActionButton(title: "完整日志", height: .compact) { SystemActions.open(run.logURL.path) }
                        .disabled(!FileTools.exists(run.logURL))
                    if run.status == .running {
                        FizzActionButton(title: "停止", height: .compact) { trials.stop(project.path) }
                            .disabled(run.stopRequested)
                    }
                }
                if let error = run.error { Text(error).font(FizzTypography.caption).fizzStatus(FizzTheme.statusWarning) }
                TrialLog(run: run).id(run.id)
            }
        }
        .task(id: project.path) {
            let dir = URL(fileURLWithPath: project.path)
            let found = await Task.detached(priority: .utility) { TrialCommand.available(in: dir) }.value
            if !Task.isCancelled { choices = found }
        }
    }
}

private struct TrialLog: View {
    let run: TrialRun
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(verbatim: text.isEmpty ? "等待日志输出…" : text)
                .font(FizzTypography.monoSmall).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 130)
        .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control))
        .task(id: run.status) {
            let path = run.logURL.path
            repeat {
                let tail = await Task.detached(priority: .utility) { LogTailReader.read(path: path) }.value
                guard !Task.isCancelled else { return }
                text = tail
                guard run.status == .running else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            } while !Task.isCancelled
        }
    }
}
