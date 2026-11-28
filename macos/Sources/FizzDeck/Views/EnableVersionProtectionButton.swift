import SwiftUI

struct EnableVersionProtectionButton: View {
    let project: RepoProject
    var prominence: FizzButtonProminence = .secondary
    @Environment(RepositoryStore.self) private var store
    @State private var working = false

    var body: some View {
        FizzActionButton(
            title: working ? "正在开启版本保护…" : "开启版本保护",
            symbol: "checkmark.shield",
            height: .compact,
            prominence: prominence
        ) {
            working = true
            Task {
                defer { working = false }
                let result = await DoctorService.initGitRepository(in: URL(fileURLWithPath: project.path))
                if result.succeeded { store.reloadMarks() }
                ToastCenter.shared.show(result.message, symbol: result.succeeded ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                                        tint: result.succeeded ? FizzTheme.statusSuccess : FizzTheme.statusWarning)
                await store.refreshGit(for: project.path)
                await store.refreshDoctor(for: project, scope: .focused)
            }
        }
        .disabled(working)
    }
}
