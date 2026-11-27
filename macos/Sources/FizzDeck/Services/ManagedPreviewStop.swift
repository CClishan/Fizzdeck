import AppKit

/// Project shortcuts have no selected PID. Only the recorded launch may supply one.
@MainActor
enum ManagedPreviewStop {
    enum Outcome: Equatable {
        case cancelled
        case portFree(String)
        case reviewInDoctor(String)
    }

    static func request(
        project: PreviewProject, launch: Process?, isCurrent: () -> Bool,
        confirm: (PreviewProject, PortOccupant) async -> Bool
    ) async -> Outcome {
        guard let conflict = await PortConflictService.inspect(port: project.port) else {
            return .portFree("端口 \(project.port) 没有监听进程")
        }
        if let note = conflict.note { return .reviewInDoctor(note) }
        guard isCurrent(), let launch, launch.isRunning, let root = ListenerIdentity.read(launch.processIdentifier) else {
            return .reviewInDoctor("无法将 :\(project.port) 的监听归属到本项目的启动进程")
        }
        let owned = conflict.occupants.filter { $0.canStop && project.owns(listener: $0.pid, launchedBy: root.pid) }
        guard owned.count == 1, let target = owned.first else {
            return .reviewInDoctor(owned.isEmpty ? "未找到属于本项目的监听 PID" : "本项目有多个监听 PID")
        }
        guard await confirm(project, target) else { return .cancelled }
        // The second socket snapshot can suspend. Check the store and the exact launch again at the signal boundary.
        let result = await PortConflictService.terminateConfirmed(conflict.confirmedByUser(), only: target) {
            isCurrent() && launch.isRunning && ListenerIdentity.read(root.pid) == root
                && project.owns(listener: target.pid, launchedBy: root.pid)
        }
        return result.portReleased ? .portFree(result.message) : .reviewInDoctor(result.message)
    }

    static func confirm(_ project: PreviewProject, _ target: PortOccupant) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "停止「\(project.title)」的开发服务？"
        alert.informativeText = "端口 :\(project.port)\n\(target.details)\n仅向此 PID 发送 SIGTERM。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "停止 PID \(target.pid)").hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.mainWindow, window.isVisible, !window.isMiniaturized {
            guard window.attachedSheet == nil else { return false }
            return await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
        }
        return alert.runModal() == .alertSecondButtonReturn
    }
}
