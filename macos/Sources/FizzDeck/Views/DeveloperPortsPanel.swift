import SwiftUI

struct DeveloperPortsPanel: View {
    var body: some View {
        Panel(title: "开发监听端口", symbol: "network") { DeveloperPortList() }
    }
}

struct DeveloperPortList: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    var project: RepoProject? = nil
    var managedChanged: (Bool) -> Void = { _ in }

    @State private var rows: [DeveloperListener] = []
    @State private var scanError: String?
    @State private var refreshing = true
    @State private var revision = 0
    @State private var pending: DeveloperListener?
    @State private var stopping = false

    private struct Query: Equatable {
        let projects: [PreviewProject]
        let port: Int?
        let activity: [String]
        let revision: Int
    }

    var body: some View {
        let query = Query(
            projects: store.projects.compactMap { PreviewProject.from($0, actions: actions) },
            port: project?.run?.port, activity: actions.busy.keys.sorted(), revision: revision
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let scanError { Text(scanError).foregroundStyle(.orange) }
                else if refreshing { ProgressView().controlSize(.mini).accessibilityLabel("核对监听进程") }
                else if rows.isEmpty { Text(project == nil ? "未发现可见的开发端口监听" : "未发现监听").foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                if let project, rows.isEmpty, !refreshing, scanError == nil {
                    Button("启动") { Task { await actions.launch(project, store: store); revision += 1 } }
                        .disabled(actions.isBusy(project.path))
                }
                Button { revision += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新监听端口").accessibilityLabel("刷新监听端口").disabled(refreshing || stopping)
            }
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: ":\(row.conflict.port) · \(row.label)")
                            .font(.callout.weight(.medium))
                        Text(verbatim: "PID \(row.process.pid) · UID \(row.process.uid.map(String.init) ?? "未知")")
                        Text(verbatim: row.process.displayCommand)
                            .lineLimit(2).help(row.process.displayCommand)
                    }
                    .font(.caption.monospaced()).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if let owner = row.owner, row.conflict.occupants.count == 1, !row.process.previewHosts.isEmpty {
                        Button("预览") {
                            Task {
                                if isRegistered(owner), let url = await PortConflictService.previewURL(port: row.conflict.port, occupant: row.process, project: owner), isRegistered(owner) {
                                    SystemActions.openURL(url)
                                } else {
                                    show(.refused("监听进程已变化，无法打开受管预览"))
                                    revision += 1
                                }
                            }
                        }
                    }
                    Button("停止…") { pending = row }.disabled(!row.process.canStop)
                }
                .disabled(stopping || refreshing)
            }
        }
        .font(.caption).buttonStyle(.glass).controlSize(.small)
        .task(id: query) {
            refreshing = true
            let ports = query.port.map { Set([$0]) } ?? PortConflictService.commonPorts.union(query.projects.map(\.port))
            do {
                let result = try await DeveloperListener.scan(ports: ports, projects: query.projects)
                guard !Task.isCancelled else { return }
                rows = result
                scanError = nil
                managedChanged(result.contains { $0.owner?.path == project?.path && $0.owner != nil })
            } catch {
                guard !Task.isCancelled else { return }
                rows = []; scanError = error.localizedDescription; managedChanged(false)
            }
            refreshing = false
        }
        .alert(item: $pending) { row in
            Alert(
                title: Text("停止 :\(row.conflict.port) 的这个进程？"),
                message: Text("\(row.label)\n\(row.process.details)\n确认后仅发送 SIGTERM。"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("确认停止")) {
                    if let owner = row.owner, !isRegistered(owner) {
                        show(.refused("项目已变化，请刷新后重新确认"))
                        revision += 1
                        return
                    }
                    stopping = true
                    Task {
                        let result = await PortConflictService.terminateConfirmed(
                            row.conflict.confirmedByUser(), only: row.process, managedBy: row.owner
                        )
                        show(result); stopping = false; revision += 1
                    }
                }
            )
        }
    }

    private func isRegistered(_ project: PreviewProject) -> Bool {
        store.projects.contains { $0.path == project.path && PreviewProject.from($0, actions: actions) == project }
    }

    private func show(_ result: PortTerminationResult) {
        ToastCenter.shared.show(result.message, symbol: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle", tint: result.succeeded ? .green : .orange)
    }
}
