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
                FizzIcon(symbol: symbol, size: 13)
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
        .fizzCard(radius: FizzRadius.card)
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
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            HStack(spacing: 7) {
                FizzIcon(symbol: symbol, size: 13)
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
        .padding(FizzSpacing.panel)
        .fizzCard(radius: FizzRadius.panel)
    }
}

struct RunningPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 7
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(Color.green.opacity(0.32))
                    .frame(width: size, height: size)
                    .scaleEffect(pulsing ? 2.2 : 1.0)
                    .opacity(pulsing ? 0 : 0.65)
                    .animation(
                        .easeOut(duration: 2.4).repeatForever(autoreverses: false),
                        value: pulsing
                    )
            }

            Circle()
                .fill(.green)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .onAppear {
            if !reduceMotion {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
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
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

struct PortStatusBadge: View {
    let state: PortState
    /// When running, show `:port` instead of the generic label.
    var port: Int? = nil

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)

            Text(displayLabel)
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.10), in: Capsule())
        .fixedSize()
        .help(state.badgeLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.badgeLabel)
    }

    private var displayLabel: String {
        Self.displayLabel(for: state, port: port)
    }

    static func displayLabel(for state: PortState, port: Int?) -> String {
        if state == .running, let port { return ":\(port)" }
        return state.badgeLabel
    }

    private var tint: Color {
        switch state.badgeTone {
        case .running: .green
        case .neutral: .secondary
        case .muted: .secondary.opacity(0.5)
        }
    }
}

enum PortStatusTone: Equatable {
    case running
    case neutral
    case muted
}

extension PortState {
    var badgeTone: PortStatusTone {
        switch self {
        case .running: .running
        case .stopped: .neutral
        case .noPreview: .muted
        }
    }

    var badgeLabel: String {
        switch self {
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
            Label("在终端中打开", systemImage: "terminal")
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

struct ProjectGroupingMenu: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject

    var body: some View {
        Menu("移动到分组") {
            Button("恢复自动分类", systemImage: "arrow.uturn.backward") {
                store.setGroup(nil, for: project)
            }

            Divider()

            ForEach(store.knownGroups, id: \.self) { group in
                Button {
                    store.setGroup(group, for: project)
                } label: {
                    Label(
                        group,
                        systemImage: project.group == group ? "checkmark" : "circle.fill"
                    )
                }
            }

            Divider()

            Button("新建分组…", systemImage: "plus") {
                guard let name = SystemActions.promptForGroupName() else { return }
                store.setGroup(name, for: project)
            }
        }
    }
}
