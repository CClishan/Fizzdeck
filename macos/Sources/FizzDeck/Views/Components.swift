import SwiftUI

struct TagChip: View {
    let text: String
    var tint: Color = .secondary
    var compact = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

struct GlassStatCard: View {
    let title: String
    let value: String
    let detail: String?
    let symbol: String
    var tint: Color = .accentColor
    var statusColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))

            HStack(spacing: 6) {
                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fizzCard(radius: 15)
    }
}

struct Panel<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    let content: Content
    let accessory: Accessory

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.symbol = symbol
        self.content = content()
        self.accessory = EmptyView()
    }

    init(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 12)
                accessory
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .fizzCard(radius: 16)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var mono = false
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(tint)
                .font(mono ? .system(.caption, design: .monospaced) : .callout)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}

struct CopyButton: View {
    let title: String
    let value: String
    var symbol = "doc.on.doc"

    var body: some View {
        Button {
            SystemActions.copy(value)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct StatusDot: View {
    let state: PortState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .help(label)
    }

    private var color: Color {
        switch state {
        case .running: .green
        case .stopped: .orange
        case .noPreview: .secondary.opacity(0.5)
        }
    }

    private var label: String {
        switch state {
        case .running: "端口运行中"
        case .stopped: "端口未启动"
        case .noPreview: "无预览端口"
        }
    }
}

struct ProjectQuickActions: View {
    let project: RepoProject

    private var editors: [ProjectEditor] {
        ProjectEditor.available(for: project.path)
    }

    var body: some View {
        Button {
            SystemActions.reveal(project.path)
        } label: {
            Label("在 Finder 中显示", systemImage: "folder")
        }

        Button {
            SystemActions.openTerminal(project.path)
        } label: {
            Label("在 Terminal 中打开", systemImage: "terminal")
        }

        if !editors.isEmpty {
            Menu {
                ForEach(editors) { editor in
                    Button(editor.title) {
                        SystemActions.open(project.path, in: editor)
                    }
                }
            } label: {
                Label("在编辑器中打开", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }

        Divider()

        Button {
            SystemActions.copy(project.path)
        } label: {
            Label("复制路径", systemImage: "doc.on.doc")
        }
    }
}
