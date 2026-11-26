import SwiftUI

struct AttentionQueueView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false
    @State private var pendingGitAction: PendingGitAction?
    @State private var gitActions: [String: GitSyncAction] = [:]
    @State private var feedback: [String: AttentionFeedback] = [:]
    @State private var copiedItemID: String?
    @State private var now = Date()
    @State private var selectedKind: ProjectAttentionKind?

    var showsTabs = false
    private let collapsedLimit = 4

    private var allItems: [ProjectAttentionItem] {
        ProjectAttentionQueue.items(projects: store.projects, testRuns: actions.testRuns)
    }

    private var items: [ProjectAttentionItem] {
        allItems.filter {
            !store.isAttentionSuppressed(for: $0.project, kind: $0.kind, at: now)
        }
    }

    private var suppressedItems: [SuppressedAttentionItem] {
        allItems.compactMap { item in
            guard let preference = store.attentionPreference(for: item.project, kind: item.kind),
                  preference.suppresses(at: now)
            else { return nil }
            return SuppressedAttentionItem(item: item, preference: preference)
        }
    }

    private var filteredItems: [ProjectAttentionItem] {
        guard showsTabs, let selectedKind else { return items }
        return items.filter { $0.kind == selectedKind }
    }

    private var visibleItems: [ProjectAttentionItem] {
        expanded ? filteredItems : Array(filteredItems.prefix(collapsedLimit))
    }

    private var availableKinds: [(kind: ProjectAttentionKind, count: Int)] {
        ProjectAttentionKind.allCases.compactMap { kind in
            let count = items.filter { $0.kind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
    }

    private var projectCount: Int {
        Set(items.map(\.project.path)).count
    }

    var body: some View {
        if !items.isEmpty || !suppressedItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    FizzIcon(symbol: "exclamationmark.circle", size: 13)
                        .foregroundStyle(FizzTheme.accent)
                    Text("待处理")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(projectCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("个项目")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    Text("\(items.count) 项")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    if !suppressedItems.isEmpty {
                        suppressedMenu
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.55)

                if showsTabs && availableKinds.count > 1 {
                    categoryTabs
                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.45)
                }

                ForEach(visibleItems) { item in
                    AttentionRow(
                        item: item,
                        inlineAction: item.inlineAction,
                        isActing: isActing(item),
                        copied: copiedItemID == item.id,
                        feedback: feedback[item.id],
                        open: {
                            store.openProject(item.project, tab: item.kind.tab)
                        },
                        perform: { action in
                            perform(action, for: item)
                        }
                    )
                    .contextMenu {
                        Menu("稍后提醒") {
                            Button("1 小时后") {
                                snooze(item, until: Date().addingTimeInterval(60 * 60))
                            }
                            Button("明天 9:00") {
                                snooze(item, until: tomorrowMorning)
                            }
                        }
                        Divider()
                        Button("忽略此提醒", systemImage: "bell.slash") {
                            mute(item)
                        }
                    }

                    if item.id != visibleItems.last?.id {
                        Divider()
                            .padding(.leading, 50)
                            .opacity(0.38)
                    }
                }

                if items.isEmpty {
                    HStack(spacing: 6) {
                        FizzIcon(symbol: "checkmark.circle", size: 12)
                            .foregroundStyle(.green)
                        Text("没有待处理项")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                if filteredItems.count > collapsedLimit {
                    Button {
                        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(expanded ? "收起" : "还有 \(filteredItems.count - collapsedLimit) 项")
                            FizzIcon(symbol: expanded ? "chevron.up" : "chevron.down", size: 8)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.38)
                    }
                }
            }
        .fizzCard(radius: FizzRadius.panel)
            .alert(item: $pendingGitAction) { pending in
                Alert(
                    title: Text("\(pending.action.title) \(pending.item.project.displayName)？"),
                    message: Text(pending.action.confirmation),
                    primaryButton: .cancel(Text("取消")),
                    secondaryButton: .default(Text(pending.action.title)) {
                        Task { await performGit(pending) }
                    }
                )
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if Task.isCancelled { break }
                    now = Date()
                }
            }
            .onChange(of: items.count) {
                if let selectedKind, !availableKinds.contains(where: { $0.kind == selectedKind }) {
                    self.selectedKind = nil
                }
            }
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabButton(title: "全部", count: items.count, selected: selectedKind == nil) {
                    selectedKind = nil
                }
                ForEach(availableKinds, id: \.kind) { entry in
                    tabButton(
                        title: entry.kind.shortTitle,
                        count: entry.count,
                        selected: selectedKind == entry.kind
                    ) {
                        selectedKind = entry.kind
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func tabButton(
        title: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                selected ? FizzTheme.accent : FizzTheme.recessedFill,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var suppressedMenu: some View {
        Menu {
            Section("已静默") {
                ForEach(suppressedItems) { entry in
                    Button {
                        restore(entry)
                    } label: {
                        Label(
                            "\(entry.item.project.displayName) · \(entry.item.kind.shortTitle)",
                            systemImage: entry.preference.isSnoozed() ? "clock" : "bell.slash"
                        )
                    }
                }
            }

            Divider()

            Button("全部恢复", systemImage: "bell") {
                restoreAll()
            }
        } label: {
            Label("\(suppressedItems.count)", systemImage: "bell.slash")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(suppressedItems.count) 项已静默")
    }

    private var tomorrowMorning: Date {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        else { return now.addingTimeInterval(24 * 60 * 60) }
        return morning
    }

    private func isActing(_ item: ProjectAttentionItem) -> Bool {
        if item.kind == .testFailed, actions.testRuns[item.project.path]?.status == .running {
            return true
        }
        return gitActions[item.id] != nil
    }

    private func perform(_ action: AttentionInlineAction, for item: ProjectAttentionItem) {
        switch action {
        case .runTests:
            feedback[item.id] = nil
            actions.runTests(item.project, store: store)
        case .pull:
            pendingGitAction = PendingGitAction(item: item, action: .pull)
        case .push:
            pendingGitAction = PendingGitAction(item: item, action: .push)
        case .copyCleanup:
            let command = item.project.cleanup.removalCommand
            guard !command.isEmpty else { return }
            SystemActions.copy(command)
            copiedItemID = item.id
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copiedItemID == item.id {
                    copiedItemID = nil
                }
            }
        }
    }

    private func performGit(_ pending: PendingGitAction) async {
        let path = pending.item.project.path
        gitActions[pending.item.id] = pending.action
        feedback[pending.item.id] = nil

        let result = await GitSyncService.run(
            pending.action,
            in: URL(fileURLWithPath: path)
        )
        if result.succeeded {
            await store.refreshGit(for: path)
        }
        feedback[pending.item.id] = AttentionFeedback(
            message: result.message,
            failed: !result.succeeded
        )
        gitActions[pending.item.id] = nil
    }

    private func snooze(_ item: ProjectAttentionItem, until date: Date) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            store.snoozeAttention(for: item.project, kind: item.kind, until: date)
        }
    }

    private func mute(_ item: ProjectAttentionItem) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            store.muteAttention(for: item.project, kind: item.kind)
        }
    }

    private func restore(_ entry: SuppressedAttentionItem) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            store.restoreAttention(for: entry.item.project, kind: entry.item.kind)
        }
    }

    private func restoreAll() {
        let rules = suppressedItems.map {
            ($0.item.project.path, $0.item.kind.rawValue)
        }
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            store.restoreAttention(for: rules)
        }
    }
}

private struct AttentionRow: View {
    let item: ProjectAttentionItem
    let inlineAction: AttentionInlineAction?
    let isActing: Bool
    let copied: Bool
    let feedback: AttentionFeedback?
    let open: () -> Void
    let perform: (AttentionInlineAction) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 9) {
                    FizzIcon(symbol: item.kind.symbol, size: 13)
                        .foregroundStyle(item.kind.tint)
                        .frame(width: 24, height: 27)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(item.project.displayName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                            Text(item.title)
                                .font(.system(size: 11.5))
                                .foregroundStyle(item.kind.tint)
                                .lineLimit(1)
                        }

                        Text(feedback?.message ?? item.detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(feedback?.failed == true ? Color.red : Color.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开 \(item.project.displayName) 的\(item.kind.destinationTitle)；右键可稍后或忽略")

            if let inlineAction {
                Button {
                    perform(inlineAction)
                } label: {
                    Group {
                        if isActing {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            FizzIcon(
                                symbol: copied ? "checkmark" : inlineAction.symbol,
                                size: 11
                            )
                                .foregroundStyle(copied ? Color.green : item.kind.tint)
                        }
                    }
                    .frame(width: 25, height: 25)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isActing)
                .help(inlineAction.title)
                .accessibilityLabel(inlineAction.title)
            }

            FizzIcon(symbol: "chevron.right", size: 8)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(FizzTheme.mutedFill.opacity(0.8))
                    .padding(.horizontal, 5)
            }
        }
        .onHover { hovering = $0 }
    }
}

private enum AttentionInlineAction {
    case runTests
    case pull
    case push
    case copyCleanup

    var title: String {
        switch self {
        case .runTests: "运行测试"
        case .pull: "拉取远端"
        case .push: "推送提交"
        case .copyCleanup: "复制清理命令"
        }
    }

    var symbol: String {
        switch self {
        case .runTests: "play.fill"
        case .pull: "arrow.down"
        case .push: "arrow.up"
        case .copyCleanup: "doc.on.doc"
        }
    }
}

private struct PendingGitAction: Identifiable {
    let item: ProjectAttentionItem
    let action: GitSyncAction

    var id: String {
        "\(item.id):\(action.rawValue)"
    }
}

private struct SuppressedAttentionItem: Identifiable {
    let item: ProjectAttentionItem
    let preference: AttentionPreference

    var id: String { item.id }
}

private struct AttentionFeedback {
    let message: String
    let failed: Bool
}

private extension ProjectAttentionItem {
    var inlineAction: AttentionInlineAction? {
        switch kind {
        case .testFailed:
            project.test == nil ? nil : .runTests
        case .dirty:
            nil
        case .behind:
            .pull
        case .unpushed:
            .push
        case .cleanup:
            project.cleanup.items.isEmpty ? nil : .copyCleanup
        }
    }
}

private extension ProjectAttentionKind {
    var symbol: String {
        switch self {
        case .testFailed: "xmark.octagon"
        case .dirty: "square.and.pencil"
        case .behind: "arrow.down"
        case .unpushed: "arrow.up"
        case .cleanup: "trash.slash"
        }
    }

    var tint: Color {
        switch self {
        case .testFailed: .red
        case .dirty: .orange
        case .behind: .blue
        case .unpushed: .purple
        case .cleanup: .teal
        }
    }

    var destinationTitle: String {
        switch self {
        case .testFailed: "测试"
        case .dirty, .behind, .unpushed: "改动"
        case .cleanup: "清理"
        }
    }

    var shortTitle: String {
        switch self {
        case .testFailed: "测试失败"
        case .dirty: "未提交"
        case .behind: "落后远端"
        case .unpushed: "未推送"
        case .cleanup: "可清理"
        }
    }
}
