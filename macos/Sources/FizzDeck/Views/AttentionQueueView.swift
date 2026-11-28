import SwiftUI

struct AttentionQueueView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    @State private var expanded = false
    @State private var pendingGitAction: PendingGitAction?
    @State private var gitActions: [String: GitSyncAction] = [:]
    @State private var feedback: [String: AttentionFeedback] = [:]
    @State private var copiedItemID: String?
    @State private var now = Date()
    @State private var selectedKind: ProjectAttentionKind?

    var showsTabs = false
    var focusedOnly = false
    var fillHeight = false
    private let collapsedLimit = 4

    private var effectiveCollapsedLimit: Int {
        copyMode == .plain ? 3 : collapsedLimit
    }

    private var allItems: [ProjectAttentionItem] {
        let focusedPaths = focusedOnly
            ? ProjectFocusPolicy.partition(projects: store.projects).focusedPaths
            : nil
        return ProjectAttentionQueue.items(
            projects: store.projects,
            testRuns: actions.testRuns,
            focusedPaths: focusedPaths,
            copyMode: copyMode,
            doctorReports: store.doctorReports
        )
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
        expanded ? filteredItems : Array(filteredItems.prefix(effectiveCollapsedLimit))
    }

    private var availableKinds: [(kind: ProjectAttentionKind, count: Int)] {
        ProjectAttentionKind.allCases.compactMap { kind in
            let count = items.filter { $0.kind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
    }

    var body: some View {
        let rows = visibleItems
        Panel(title: FizzCopy.attentionTitle(copyMode), symbol: "exclamationmark.circle", fillHeight: fillHeight) {
            if showsTabs && copyMode == .pro && availableKinds.count > 1 {
                categoryTabs
            }
            if rows.isEmpty {
                Text("没有待处理项")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, FizzSpacing.row)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { item in
                        AttentionRow(
                            item: item,
                            inlineAction: item.inlineAction,
                            isActing: isActing(item),
                            copied: copiedItemID == item.id,
                            feedback: feedback[item.id],
                            copyMode: copyMode,
                            open: { store.openProject(item.project, tab: item.kind.tab) },
                            perform: { perform($0, for: item) }
                        )
                        .contextMenu {
                            Menu("稍后提醒") {
                                Button("1 小时后") { snooze(item, until: Date().addingTimeInterval(60 * 60)) }
                                Button("明天 9:00") { snooze(item, until: tomorrowMorning) }
                            }
                            Divider()
                            Button("忽略此提醒", systemImage: "bell.slash") { mute(item) }
                        }

                        if item.id != rows.last?.id {
                            Divider().opacity(0.38)
                        }
                    }
                }
            }
        } accessory: {
            Text("\(items.count) 项")
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
            if !suppressedItems.isEmpty { suppressedMenu }
            if filteredItems.count > effectiveCollapsedLimit {
                FizzIconButton(
                    title: expanded ? "收起" : "展开全部 \(filteredItems.count) 项",
                    symbol: expanded ? "chevron.up" : "chevron.down",
                    height: .compact
                ) {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) { expanded.toggle() }
                }
            }
        }
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

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            FizzSegmentedCapsule(
                items: [nil] + availableKinds.map(\.kind),
                selection: $selectedKind,
                height: .compact,
                horizontalPadding: 9
            ) { kind, _ in
                HStack(spacing: 4) {
                    Text(kind?.shortTitle ?? "全部")
                    Text("\(tabCount(for: kind))")
                        .foregroundStyle(.secondary)
                }
                .font(FizzTypography.caption(.medium))
            }
        }
    }

    private func tabCount(for kind: ProjectAttentionKind?) -> Int {
        guard let kind else { return items.count }
        return availableKinds.first { $0.kind == kind }?.count ?? 0
    }

    private var suppressedMenu: some View {
        FizzMenuButton(title: "已静默 \(suppressedItems.count) 项", symbol: "bell.slash") {
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
            Button("全部恢复", systemImage: "bell", action: restoreAll)
        }
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
            SystemActions.copy(command, microViz: .compact(state: .done))
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
    var copyMode: CopyMode = .plain
    let open: () -> Void
    let perform: (AttentionInlineAction) -> Void

    @State private var hovering = false

    @ViewBuilder private var nameAndTag: some View {
        Text(item.project.displayName)
            .font(FizzTypography.cardTitle)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        TagChip(text: item.title, tint: item.kind.tint, compact: true)
    }

    var body: some View {
        HStack(spacing: FizzSpacing.row) {
            Button(action: open) {
                HStack(spacing: FizzSpacing.row) {
                    FizzIcon(.sm, symbol: item.kind.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: FizzControlHeight.compact.rawValue)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) { nameAndTag }.fixedSize()
                            VStack(alignment: .leading, spacing: 2) { nameAndTag }
                        }
                        HStack(spacing: 4) {
                            if feedback?.failed == true { FizzStatusDot(tint: FizzTheme.statusDanger) }
                            Text(feedback?.message ?? item.detail)
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开 \(item.project.displayName) 的\(item.kind.destinationTitle)；右键可稍后或忽略")

            if isActing {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: FizzControlHeight.compact.rawValue, height: FizzControlHeight.compact.rawValue)
            } else if let inlineAction {
                if copyMode == .plain {
                    FizzActionButton(title: copied ? "已复制" : inlineAction.plainTitle, height: .compact) {
                        perform(inlineAction)
                    }
                } else {
                    FizzIconButton(title: inlineAction.title, symbol: copied ? "checkmark" : inlineAction.symbol, height: .compact) {
                        perform(inlineAction)
                    }
                }
            } else {
                FizzIconButton(title: "查看\(item.kind.destinationTitle)", symbol: "chevron.right", height: .compact, action: open)
            }
        }
        .padding(.vertical, FizzSpacing.row)
        .background(hovering ? FizzTheme.mutedFill : Color.clear, in: RoundedRectangle(cornerRadius: FizzRadius.inset))
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

    var plainTitle: String {
        switch self {
        case .runTests: "重新检查"
        case .pull: "更新代码"
        case .push: "上传版本"
        case .copyCleanup: "复制命令"
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
        case .doctorCritical:
            nil
        case .testFailed:
            project.test == nil ? nil : .runTests
        case .sessionError, .dirty:
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
        case .doctorCritical: "exclamationmark.shield.fill"
        case .testFailed: "xmark.octagon"
        case .sessionError: "exclamationmark.triangle"
        case .dirty: "square.and.pencil"
        case .behind: "arrow.down"
        case .unpushed: "arrow.up"
        case .cleanup: "trash.slash"
        }
    }

    var tint: Color {
        switch self {
        case .doctorCritical, .testFailed: FizzTheme.statusDanger
        case .sessionError, .dirty: FizzTheme.statusWarning
        case .behind: Color.secondary
        case .unpushed: Color.secondary
        case .cleanup: Color.secondary
        }
    }

    var destinationTitle: String {
        switch self {
        case .doctorCritical, .testFailed: "运行"
        case .sessionError, .cleanup: "进度"
        case .dirty, .behind, .unpushed: "版本"
        }
    }

    var shortTitle: String {
        switch self {
        case .doctorCritical: "体检阻塞"
        case .testFailed: "测试失败"
        case .sessionError: "对话报错"
        case .dirty: "未提交"
        case .behind: "落后远端"
        case .unpushed: "未推送"
        case .cleanup: "可清理"
        }
    }
}
