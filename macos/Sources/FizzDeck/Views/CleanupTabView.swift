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
                        title: "可回收",
                        value: project.sizeLoadState == .ready
                            ? Format.bytes(project.cleanup.reusableBytes)
                            : "",
                        detail: "只复制命令，不执行删除",
                        symbol: "trash.slash",
                        valuePlaceholder: project.sizeLoadState != .ready
                    )
                    GlassStatCard(
                        title: "命中目录",
                        value: "\(project.cleanup.items.count)",
                        detail: "依赖、缓存、构建产物、归档",
                        symbol: "folder.badge.minus"
                    )
                }

                if project.cleanup.items.isEmpty {
                    ContentUnavailableView(
                        "没有可清理项",
                        systemImage: "checkmark.seal",
                        description: Text("没有命中 node_modules、构建产物、缓存或归档规则。")
                    )
                    .frame(minHeight: 220)
                } else {
                    Panel(title: "可清理目录", symbol: "trash.slash") {
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
                    Panel(title: "体积构成", symbol: "chart.bar.doc.horizontal") {
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
            "将目录移到废纸篓？",
            isPresented: Binding(
                get: { confirmTrashItem != nil },
                set: { if !$0 { confirmTrashItem = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                confirmTrashItem = nil
            }
            Button("移到废纸篓", role: .destructive) {
                guard let item = confirmTrashItem else { return }
                confirmTrashItem = nil
                Task { await trashSingleItem(item) }
            }
        } message: {
            if let item = confirmTrashItem {
                Text("将把「\(item.label)」（\(Format.bytes(item.bytes))）移到系统废纸篓，随时可恢复或重新生成。")
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
                    Text(item.reason)
                    if !item.regen.isEmpty {
                        Text("·")
                        Text(item.regen)
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
                    Label("移到废纸篓", systemImage: "trash")
                        .font(FizzTypography.caption(.medium))
                } else {
                    FizzIcon(.sm, symbol: "doc.on.doc")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(copyMode == .plain ? "安全移到系统废纸篓" : "复制删除命令")
            .accessibilityLabel(copyMode == .plain ? "移到废纸篓" : "复制删除命令")
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
                "已移入废纸篓（\(Format.bytes(res.freedBytes))）",
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
                Text(row.isDirectory ? "▸ \(row.label)" : row.label)
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
