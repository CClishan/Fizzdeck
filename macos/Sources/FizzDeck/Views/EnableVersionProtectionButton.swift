import SwiftUI

struct EnableVersionProtectionButton: View {
    let project: RepoProject
    @Environment(RepositoryStore.self) private var store
    @State private var working = false

    var body: some View {
        Button {
            working = true
            Task {
                defer { working = false }
                let result = await DoctorService.initGitRepository(in: URL(fileURLWithPath: project.path))
                if result.succeeded { store.reloadMarks() }
                ToastCenter.shared.show(result.message, symbol: result.succeeded ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                                        tint: result.succeeded ? .green : .orange)
                await store.refreshGit(for: project.path)
                await store.refreshDoctor(for: project, scope: .focused)
            }
        } label: {
            if working { ProgressView().controlSize(.small) }
            else { Label("开启版本保护", systemImage: "checkmark.shield") }
        }
        .disabled(working)
        .controlSize(.small)
    }
}
