import SwiftUI

struct DeveloperPortsPanel: View {
    var body: some View {
        DeveloperPortList()
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
        Group {
            if let project {
                VStack(alignment: .leading, spacing: FizzSpacing.row) {
                    HStack(spacing: FizzSpacing.row) {
                        scanStatus
                        Spacer(minLength: 4)
                        refreshButton
                        if rows.isEmpty, !refreshing, scanError == nil {
                            FizzActionButton(title: "启动", height: .compact) {
                                Task { await actions.launch(project, store: store); revision += 1 }
                            }
                            .disabled(actions.isBusy(project.path))
                        }
                    }
                    listenerRows
                }
            } else {
                Panel(title: "开发监听端口", symbol: "network") {
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        scanStatus
                        listenerRows
                    }
                } accessory: {
                    refreshButton
                }
            }
        }
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

    @ViewBuilder
    private var scanStatus: some View {
        if let scanError {
            Text(scanError)
                .font(FizzTypography.caption)
                .fizzStatus(FizzTheme.statusWarning)
        } else if refreshing {
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("核对监听进程")
        } else if rows.isEmpty {
            Text(project == nil ? "未发现可见的开发端口监听" : "未发现监听")
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshButton: some View {
        FizzIconButton(title: "刷新监听端口", symbol: "arrow.clockwise", height: .compact) {
            revision += 1
        }
        .disabled(refreshing || stopping)
    }

    @ViewBuilder
    private var listenerRows: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    listenerRow(row)
                    if row.id != rows.last?.id {
                        Divider().opacity(0.25)
                    }
                }
            }
        }
    }

    private func listenerRow(_ row: DeveloperListener) -> some View {
        HStack(spacing: FizzSpacing.grid) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: ":\(row.conflict.port) · \(row.label)")
                    .font(FizzTypography.body(.medium))
                Text(verbatim: "PID \(row.process.pid) · UID \(row.process.uid.map(String.init) ?? "未知")")
                Text(verbatim: row.process.displayCommand)
                    .lineLimit(2)
                    .help(row.process.displayCommand)
            }
            .font(FizzTypography.monoSmall)
            .textSelection(.enabled)

            Spacer(minLength: FizzSpacing.row)

            HStack(spacing: 6) {
                if let owner = row.owner, row.conflict.occupants.count == 1, !row.process.previewHosts.isEmpty {
                    FizzActionButton(title: "预览", height: .compact) {
                        Task {
                            guard isRegistered(owner),
                                  let url = await PortConflictService.previewURL(
                                      port: row.conflict.port, occupant: row.process, project: owner
                                  ), isRegistered(owner) else {
                                show(.refused("监听进程已变化，无法打开受管预览"))
                                revision += 1
                                return
                            }
                            SystemActions.openURL(url)
                        }
                    }
                }
                FizzActionButton(title: "停止…", height: .compact, role: .destructive) { pending = row }
                    .disabled(!row.process.canStop)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, FizzSpacing.row)
        .disabled(stopping || refreshing)
    }

    private func isRegistered(_ project: PreviewProject) -> Bool {
        store.projects.contains { $0.path == project.path && PreviewProject.from($0, actions: actions) == project }
    }

    private func show(_ result: PortTerminationResult) {
        ToastCenter.shared.show(result.message, symbol: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle", tint: result.succeeded ? FizzTheme.statusSuccess : FizzTheme.statusWarning)
    }
}
