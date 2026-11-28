import SwiftUI

struct CleanupTabView: View {
    @Environment(RepositoryStore.self) private var store
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let project: RepoProject

    @State private var confirmTrashItem: CleanupItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: FizzSpacing.grid)],
                    spacing: FizzSpacing.grid
                ) {
                    GlassStatCard(
                        title: FizzL10n.text("可回收", "Reclaimable"),
                        value: project.sizeLoadState == .ready
                            ? Format.bytes(project.cleanup.reusableBytes)
                            : "",
                        detail: FizzL10n.text("只复制命令，不执行删除", "Copies the command without deleting anything"),
                        symbol: "trash.slash",
                        valuePlaceholder: project.sizeLoadState != .ready
                    )
                    GlassStatCard(
                        title: FizzL10n.text("命中目录", "Folders found"),
                        value: "\(project.cleanup.items.count)",
                        detail: FizzL10n.text("依赖、缓存、构建产物、归档", "Dependencies, caches, builds and archives"),
                        symbol: "folder.badge.minus"
                    )
                }

                if project.cleanup.items.isEmpty {
                    ContentUnavailableView(
                        FizzL10n.text("没有可清理项", "Nothing to clean up"),
                        systemImage: "checkmark.seal",
                        description: Text(FizzL10n.text("没有命中 node_modules、构建产物、缓存或归档规则。", "No node_modules, build output, caches or archives matched the cleanup rules."))
                    )
                    .frame(minHeight: 220)
                } else {
                    Panel(title: FizzL10n.text("可清理目录", "Folders to clean up"), symbol: "trash.slash") {
                        VStack(spacing: 0) {
                            ForEach(project.cleanup.items) { item in
                                cleanupRow(item)
                                if item != project.cleanup.items.last {
                                    Divider()
                                        .opacity(0.25)
                                }
                            }
                        }
                    }
                }

                if !project.size.breakdown.isEmpty {
                    Panel(title: FizzL10n.text("体积构成", "Space by folder"), symbol: "chart.bar.doc.horizontal") {
                        VStack(spacing: 10) {
                            ForEach(project.size.breakdown) { row in
                                sizeRow(row)
                            }
                        }
                    }
                }
            }
            .padding(FizzSpacing.page)
        }
        .fizzTracksScrollPastTop()
        .alert(
            FizzL10n.text("将目录移到废纸篓？", "Move this folder to the Trash?"),
            isPresented: Binding(
                get: { confirmTrashItem != nil },
                set: { if !$0 { confirmTrashItem = nil } }
            )
        ) {
            Button(FizzL10n.text("取消", "Cancel"), role: .cancel) {
                confirmTrashItem = nil
            }
            Button(FizzL10n.text("移到废纸篓", "Move to Trash"), role: .destructive) {
                guard let item = confirmTrashItem else { return }
                confirmTrashItem = nil
                Task { await trashSingleItem(item) }
            }
        } message: {
            if let item = confirmTrashItem {
                Text(FizzL10n.text("将把「\(item.label)」（\(Format.bytes(item.bytes))）移到系统废纸篓，随时可恢复或重新生成。", "Move “\(item.label)” (\(Format.bytes(item.bytes))) to the Trash. You can put it back or regenerate it later."))
            }
        }
    }

    private func cleanupRow(_ item: CleanupItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FizzIcon(.md, symbol: kindSymbol(item.kind))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(FizzTypography.font(12, weight: .semibold))
                    Text(Format.bytes(item.bytes))
                        .font(FizzTypography.micro(.regular))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    Text(item.displayReason)
                    if !item.displayRegen.isEmpty {
                        Text("·")
                        Text(item.displayRegen)
                    }
                }
                .font(FizzTypography.micro)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                if copyMode == .plain {
                    confirmTrashItem = item
                } else {
                    SystemActions.copy(
                        project.cleanup.removalCommand(for: item),
                        microViz: .compact(state: .done)
                    )
                }
            } label: {
                if copyMode == .plain {
                    Label(FizzL10n.text("移到废纸篓", "Move to Trash"), systemImage: "trash")
                        .font(FizzTypography.caption(.medium))
                } else {
                    FizzIcon(.sm, symbol: "doc.on.doc")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(copyMode == .plain ? FizzL10n.text("安全移到系统废纸篓", "Move safely to the Trash") : FizzL10n.text("复制删除命令", "Copy deletion command"))
            .accessibilityLabel(copyMode == .plain ? FizzL10n.text("移到废纸篓", "Move to Trash") : FizzL10n.text("复制删除命令", "Copy deletion command"))
        }
        .padding(.vertical, 7)
    }

    private func trashSingleItem(_ item: CleanupItem) async {
        let dir = URL(fileURLWithPath: project.path)
        let res = DoctorService.trashCleanupItems([item], in: dir)
        if let err = res.error {
            ToastCenter.shared.show(err, symbol: "exclamationmark.triangle.fill", tint: FizzTheme.statusWarning)
        } else {
            ToastCenter.shared.show(
                FizzL10n.text("已移入废纸篓（\(Format.bytes(res.freedBytes))）", "Moved to Trash (\(Format.bytes(res.freedBytes)))"),
                symbol: "trash.fill",
                tint: FizzTheme.statusSuccess,
                subtitle: item.label
            )
            await store.rescanProjects([project])
        }
    }

    private func sizeRow(_ row: SizeRow) -> some View {
        let ratio = project.size.totalBytes > 0
            ? Double(row.bytes) / Double(project.size.totalBytes)
            : 0
        return VStack(spacing: 4) {
            HStack {
                Text(row.isDirectory ? "▸ \(row.displayLabel)" : row.displayLabel)
                    .font(FizzTypography.caption)
                    .lineLimit(1)
                Spacer()
                Text(Format.bytes(row.bytes))
                    .font(FizzTypography.micro(.regular))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))
                    Capsule()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: max(2, proxy.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
    }

    private func kindSymbol(_ kind: String) -> String {
        switch kind {
        case "deps": "shippingbox"
        case "build": "hammer"
        case "tmp": "clock.badge.exclamationmark"
        case "archive": "archivebox"
        default: "folder"
        }
    }


}
