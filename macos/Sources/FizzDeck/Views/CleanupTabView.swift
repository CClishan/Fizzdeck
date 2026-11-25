import SwiftUI

struct CleanupTabView: View {
    let project: RepoProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 12)],
                        spacing: 12
                    ) {
                        GlassStatCard(
                            title: "可回收",
                            value: Format.bytes(project.cleanup.reusableBytes),
                            detail: "只复制命令，不执行删除",
                            symbol: "trash.slash",
                            tint: .orange
                        )
                        GlassStatCard(
                            title: "命中目录",
                            value: "\(project.cleanup.items.count)",
                            detail: "依赖、缓存、构建产物、归档",
                            symbol: "folder.badge.minus",
                            tint: .red
                        )
                    }
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
            .padding(24)
        }
    }

    private func cleanupRow(_ item: CleanupItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FizzIcon(symbol: kindSymbol(item.kind), size: 14)
                .foregroundStyle(kindColor(item.kind))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(Format.bytes(item.bytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    Text(item.reason)
                    if !item.regen.isEmpty {
                        Text("·")
                        Text(item.regen)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                SystemActions.copy(project.cleanup.removalCommand(for: item))
            } label: {
                FizzIcon(symbol: "doc.on.doc", size: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("复制删除命令")
            .accessibilityLabel("复制删除命令")
        }
        .padding(.vertical, 7)
    }

    private func sizeRow(_ row: SizeRow) -> some View {
        let ratio = project.size.totalBytes > 0
            ? Double(row.bytes) / Double(project.size.totalBytes)
            : 0
        return VStack(spacing: 4) {
            HStack {
                Text(row.isDirectory ? "▸ \(row.label)" : row.label)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(Format.bytes(row.bytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.55))
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

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "deps": .green
        case "build": .orange
        case "tmp": .red
        case "archive": .purple
        default: .secondary
        }
    }

}
