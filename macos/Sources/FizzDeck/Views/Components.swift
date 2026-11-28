import SwiftUI

enum FizzButtonProminence {
    case primary
    case secondary
}

struct FizzActionButton: View {
    let title: String
    var symbol: String? = nil
    var height: FizzControlHeight = .standard
    var prominence: FizzButtonProminence = .secondary
    var role: ButtonRole? = nil
    var keyboardNavigation = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    FizzIcon(.sm, symbol: symbol)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(FizzTypography.body(.medium))
                    .lineLimit(1)
            }
            .frame(height: height.glassLabelHeight)
        }
        .buttonBorderShape(.capsule)
        .modifier(FizzGlassButtonAppearance(prominence: prominence, role: role))
        .controlSize(height.glassControlSize)
        .frame(height: height.rawValue)
        .fizzKeyboardAction(keyboardNavigation, action: action)
    }
}

struct FizzIconButton: View {
    let title: String
    let symbol: String
    var height: FizzControlHeight = .standard
    var prominence: FizzButtonProminence = .secondary
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            FizzIcon(height == .standard ? .md : .sm, symbol: symbol)
                .frame(width: height.glassLabelHeight, height: height.glassLabelHeight)
        }
        .buttonBorderShape(.circle)
        .modifier(FizzGlassButtonAppearance(prominence: prominence, role: role))
        .controlSize(height.glassControlSize)
        .frame(width: height.rawValue, height: height.rawValue)
        .accessibilityLabel(title)
        .help(title)
    }
}

struct FizzMenuButton<Items: View>: View {
    let title: String
    var symbol = "ellipsis"
    var height: FizzControlHeight = .compact
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Label {
                Text(title)
            } icon: {
                FizzIcon(height == .standard ? .md : .sm, symbol: symbol)
            }
            .labelStyle(.iconOnly)
            .frame(width: height.rawValue, height: height.rawValue)
            .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(title)
        .help(title)
    }
}

private extension FizzControlHeight {
    var glassControlSize: ControlSize { self == .standard ? .regular : .small }

    // The native glass style adds 8pt or 6pt of vertical padding to the label.
    var glassLabelHeight: CGFloat { rawValue - (self == .standard ? 8 : 6) }
}

private struct FizzGlassButtonAppearance: ViewModifier {
    let prominence: FizzButtonProminence
    let role: ButtonRole?

    func body(content: Content) -> some View {
        if prominence == .primary && role != .destructive {
            content
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

struct FizzPageHeader<Period: View>: View {
    let title: String
    let subtitle: String
    private let primaryAction: FizzActionButton?
    private let period: Period

    init(
        title: String,
        subtitle: String,
        primaryAction: FizzActionButton? = nil,
        @ViewBuilder period: () -> Period
    ) {
        self.title = title
        self.subtitle = subtitle
        self.period = period()
        var primaryAction = primaryAction
        primaryAction?.height = .standard
        primaryAction?.prominence = .primary
        primaryAction?.keyboardNavigation = true
        self.primaryAction = primaryAction
    }

    init(title: String, subtitle: String, primaryAction: FizzActionButton? = nil) where Period == EmptyView {
        self.init(title: title, subtitle: subtitle, primaryAction: primaryAction) { EmptyView() }
    }

    var body: some View {
        HStack(spacing: FizzSpacing.grid) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FizzTypography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: FizzSpacing.row) {
                period
                primaryAction
            }
            .frame(height: FizzControlHeight.standard.rawValue)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct FizzSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: FizzSpacing.grid) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FizzTypography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FizzIconButton(title: FizzL10n.text("关闭", "Close"), symbol: "xmark", height: .compact, action: onClose)
        }
    }
}

struct FizzSheetFooter<Actions: View>: View {
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: FizzSpacing.row) {
            actions
        }
        .frame(maxWidth: .infinity, minHeight: FizzControlHeight.standard.rawValue, alignment: .trailing)
    }
}

struct FizzHeroMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    var change: Double? = nil
    var samples: [Double?] = []

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            Text(title)
                .font(FizzTypography.caption(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 16)

            HStack(alignment: .firstTextBaseline, spacing: FizzSpacing.row) {
                Text(value)
                    .font(FizzTypography.pageTitle)
                    .minimumScaleFactor(0.75)
                if let change, change.isFinite {
                    let rounded = (change * 100).rounded() / 100
                    let arrow = switch rounded {
                    case ..<0: "↓"
                    case 0: ""
                    default: "↑"
                    }
                    let percent = abs(rounded).formatted(.percent.precision(.fractionLength(0)))
                    Text("\(arrow)\(percent)")
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(FizzL10n.text("较上期 \(arrow)\(percent)", "\(arrow)\(percent) vs. last period"))
                }
            }
            .frame(height: 28)

            Text(subtitle)
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
                .frame(height: 16)

            FizzSparkline(samples: samples)
                .stroke(Color.secondary.opacity(0.72), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .padding(1)
                .frame(height: 20)
                .accessibilityHidden(true)
        }
        .lineLimit(1)
        .fizzSubcard()
        .accessibilityElement(children: .combine)
    }
}

struct FizzSparkline: Shape {
    let samples: [Double?]

    func path(in rect: CGRect) -> Path {
        let known = samples.compactMap { $0 }
        guard samples.count > 1, !rect.isEmpty, known.allSatisfy(\.isFinite),
              let low = known.min(), let high = known.max() else {
            return Path()
        }

        let span = high - low
        guard span.isFinite else { return Path() }
        let step = rect.width / CGFloat(samples.count - 1)
        return Path { path in
            for (index, sample) in samples.enumerated() {
                guard let sample else { continue }
                let fraction = span == 0 ? 0.5 : CGFloat((sample - low) / span)
                let point = CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - fraction * rect.height)
                if index > 0, samples[index - 1] != nil {
                    path.addLine(to: point)
                } else if index < samples.count - 1, samples[index + 1] != nil {
                    path.move(to: point)
                } else {
                    path.move(to: CGPoint(x: max(rect.minX, point.x - 0.5), y: point.y))
                    path.addLine(to: CGPoint(x: min(rect.maxX, point.x + 0.5), y: point.y))
                }
            }
        }
    }
}

extension View {
    func fizzStatus(_ tint: Color) -> some View {
        HStack(spacing: 5) {
            FizzStatusDot(tint: tint)
            self.foregroundStyle(.primary)
        }
    }

    func fizzSubcard() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(FizzSpacing.card)
            .fizzCard(radius: FizzRadius.card)
    }
}

struct TagChip: View {
    let text: String
    var tint: Color = .secondary
    var compact = false

    var body: some View {
        Text(text)
            .font(compact ? FizzTypography.micro : FizzTypography.caption(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(tint.opacity(0.11), in: Capsule())
            .lineLimit(1)
    }
}

struct GlassStatCard: View {
    let title: String
    let value: String
    let detail: String?
    let symbol: String
    var tint: Color = .secondary
    var statusColor: Color?
    var valuePlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                FizzIcon(.sm, symbol: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(FizzTypography.caption(.medium))

            HStack(spacing: 6) {
                if valuePlaceholder {
                    FizzShimmerPlaceholder(width: 94, height: 20)
                } else {
                    if let statusColor {
                        FizzStatusDot(tint: statusColor)
                    }
                    Text(value)
                        .font(FizzTypography.pageTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if let detail {
                Text(detail)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .fizzSubcard()
    }
}

struct Panel<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    let fillHeight: Bool
    let content: Content
    let accessory: Accessory

    init(title: String, symbol: String, fillHeight: Bool = false, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.symbol = symbol
        self.fillHeight = fillHeight
        self.content = content()
        self.accessory = EmptyView()
    }

    init(
        title: String,
        symbol: String,
        fillHeight: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.symbol = symbol
        self.fillHeight = fillHeight
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            HStack(spacing: 7) {
                FizzIcon(.md, symbol: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
                    .font(FizzTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                accessory
            }
            .frame(minHeight: FizzControlHeight.compact.rawValue)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .padding(FizzSpacing.panel)
        .fizzCard(radius: FizzRadius.panel)
    }
}

struct ProjectAccentDot: View {
    let path: String

    var body: some View {
        Circle()
            .fill(ProjectAccentColor.color(for: path))
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

struct FizzStatusDot: View {
    let tint: Color

    var body: some View {
        Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
    }
}

struct RunningPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(FizzTheme.statusSuccess.opacity(0.32))
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulsing ? 2.2 : 1.0)
                    .opacity(pulsing ? 0 : 0.65)
                    .animation(
                        .easeOut(duration: 2.4).repeatForever(autoreverses: false),
                        value: pulsing
                    )
            }

            FizzStatusDot(tint: FizzTheme.statusSuccess)
        }
        .frame(width: 6, height: 6)
        .onAppear {
            if !reduceMotion {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

enum FizzScrollMetrics {
    static let topThreshold: CGFloat = 8

    static func isPastTop(_ offset: CGFloat, threshold: CGFloat = topThreshold) -> Bool {
        offset > threshold
    }
}

struct FizzScrollPastTopKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct FizzScrollPastTopModifier: ViewModifier {
    @State private var pastTop = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                FizzScrollMetrics.isPastTop(geometry.contentOffset.y)
            } action: { _, newValue in
                pastTop = newValue
            }
            .preference(key: FizzScrollPastTopKey.self, value: pastTop)
    }
}

struct FizzScrollTopHairline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let visible: Bool

    var body: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .opacity(visible ? 1 : 0)
            .animation(
                FizzMotion.resolved(reduceMotion, FizzMotion.quick),
                value: visible
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func fizzTracksScrollPastTop() -> some View {
        modifier(FizzScrollPastTopModifier())
    }

    @ViewBuilder func fizzKeyboardAction(_ enabled: Bool = true, action: @escaping () -> Void) -> some View {
        if enabled { modifier(FizzKeyboardAction(action: action)) } else { self }
    }
}

private struct FizzKeyboardAction: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled, interactions: .edit)
            .onKeyPress(keys: [.space, .return], phases: .down) { key in
                guard isEnabled, key.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return .ignored }
                action()
                return .handled
            }
    }
}

struct FizzSegmentedCapsule<Item: Hashable, Label: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let items: [Item]
    @Binding var selection: Item
    var height: FizzControlHeight
    var horizontalPadding: CGFloat
    var keyboardNavigation: Bool
    let label: (Item, Bool) -> Label

    @Namespace private var namespace
    private let inset: CGFloat = 2

    init(
        items: [Item],
        selection: Binding<Item>,
        height: FizzControlHeight = .standard,
        horizontalPadding: CGFloat = 8,
        keyboardNavigation: Bool = false,
        @ViewBuilder label: @escaping (Item, Bool) -> Label
    ) {
        self.items = items
        self._selection = selection
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.keyboardNavigation = keyboardNavigation
        self.label = label
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item

                let select = {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                        selection = item
                    }
                }
                Button(action: select) {
                    label(item, selected)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, horizontalPadding)
                        .frame(height: height.rawValue - 2 * inset)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fizzKeyboardAction(keyboardNavigation, action: select)
                .background {
                    if selected {
                        Capsule()
                            .fill(FizzTheme.elevatedFill)
                            .fizzAdaptiveShadow(.subtle)
                            .matchedGeometryEffect(
                                id: "fizz-segmented-selection",
                                in: namespace
                            )
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityRemoveTraits(selected ? [] : .isSelected)
            }
        }
        .padding(inset)
        .background(FizzTheme.recessedFill, in: Capsule())
        .fixedSize()
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
                .font(FizzTypography.font(mono ? 10 : 12))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(FizzTypography.font(12))
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
            FizzStatusDot(tint: tint)

            Text(displayLabel)
                .font(FizzTypography.font(9.5, weight: .medium))
        }
        .foregroundStyle(.primary)
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
        case .running: FizzTheme.statusSuccess
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
        case .running: FizzL10n.text("端口运行中", "Port active")
        case .stopped: FizzL10n.text("端口未启动", "Port inactive")
        case .noPreview: FizzL10n.text("无预览端口", "No preview port")
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
            Label(FizzL10n.text("在 Finder 中显示", "Show in Finder"), systemImage: "folder")
        }

        Button {
            SystemActions.openTerminal(project.path)
        } label: {
            Label(FizzL10n.text("在终端中打开", "Open in Terminal"), systemImage: "terminal")
        }

        if !editors.isEmpty {
            Menu {
                ForEach(editors) { editor in
                    Button(editor.title) {
                        SystemActions.open(project.path, in: editor)
                    }
                }
            } label: {
                Label(FizzL10n.text("在编辑器中打开", "Open in Editor"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }

        Divider()

        Button {
            SystemActions.copy(project.path)
        } label: {
            Label(FizzL10n.text("复制路径", "Copy Path"), systemImage: "doc.on.doc")
        }
    }
}

struct ProjectGroupingMenu: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject

    var body: some View {
        Menu(FizzL10n.text("移动到分组", "Move to Group")) {
            Button(FizzL10n.text("恢复自动分类", "Restore Automatic Group"), systemImage: "arrow.uturn.backward") {
                store.setGroup(nil, for: project)
            }

            Divider()

            ForEach(store.knownGroups, id: \.self) { group in
                Button {
                    store.setGroup(group, for: project)
                } label: {
                    Label(
                        ProjectGrouping.title(for: group),
                        systemImage: project.group == group ? "checkmark" : "circle.fill"
                    )
                }
            }

            Divider()

            Button(FizzL10n.text("新建分组…", "New Group…"), systemImage: "plus") {
                guard let name = SystemActions.promptForGroupName() else { return }
                store.setGroup(name, for: project)
            }
        }
    }
}
