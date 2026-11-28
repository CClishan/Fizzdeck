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
    @State private var localDate = Date()
    @State private var selectedKind: ProjectAttentionKind?

    var showsTabs = false
    var fillHeight = false
    var workbenchItems: [ProjectAttentionItem]?
    var workbenchDate: Date?
    private let collapsedLimit = 4
    private var now: Date { workbenchDate ?? localDate }

    private var effectiveCollapsedLimit: Int {
        copyMode == .plain ? 3 : collapsedLimit
    }

    private var allItems: [ProjectAttentionItem] {
        workbenchItems ?? ProjectAttentionQueue.items(
            projects: store.projects,
            testRuns: actions.testRuns,
            focusedPaths: nil,
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
                Text(FizzL10n.text("没有待处理项", "Nothing needs attention"))
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
                            open: { store.openAttentionItem(item) },
                            dismissExpiry: item.expiringMarks.isEmpty ? nil : { dismissExpiry(item) },
                            perform: { perform($0, for: item) }
                        )
                        .contextMenu {
                            if item.kind == .expiringMarks {
                                Button(FizzL10n.text("忽略本批提醒", "Dismiss these reminders"), systemImage: "bell.slash") { dismissExpiry(item) }
                            } else {
                                Menu(FizzL10n.text("稍后提醒", "Remind me later")) {
                                    Button(FizzL10n.text("1 小时后", "In an hour")) { snooze(item, until: Date().addingTimeInterval(60 * 60)) }
                                    Button(FizzL10n.text("明天 9:00", "Tomorrow at 9:00 AM")) { snooze(item, until: tomorrowMorning) }
                                }
                                Divider()
                                Button(FizzL10n.text("忽略此提醒", "Mute this reminder"), systemImage: "bell.slash") { mute(item) }
                            }
                        }

                        if item.id != rows.last?.id {
                            Divider().opacity(0.38)
                        }
                    }
                }
            }
        } accessory: {
            Text(FizzL10n.text("\(items.count) 项", SessionSummaryText.englishCount(items.count, "item")))
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
            if !suppressedItems.isEmpty { suppressedMenu }
            if filteredItems.count > effectiveCollapsedLimit {
                FizzIconButton(
                    title: expanded ? FizzL10n.text("收起", "Collapse") : FizzL10n.text("展开全部 \(filteredItems.count) 项", "Show all \(filteredItems.count)"),
                    symbol: expanded ? "chevron.up" : "chevron.down",
                    height: .compact
                ) {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) { expanded.toggle() }
                }
            }
        }
        .alert(item: $pendingGitAction) { pending in
            Alert(
                title: Text(FizzL10n.text("\(pending.action.title) \(pending.item.project.displayName)？", "\(pending.action.title) changes for \(pending.item.project.displayName)?")),
                message: Text(pending.action.confirmation),
                primaryButton: .cancel(Text(FizzL10n.text("取消", "Cancel"))),
                secondaryButton: .default(Text(pending.action.title)) {
                    Task { await performGit(pending) }
                }
            )
        }
        .task {
            guard workbenchDate == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                localDate = Date()
            }
        }
        .onChange(of: availableKinds.map(\.kind)) {
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
                    Text(kind?.shortTitle ?? FizzL10n.text("全部", "All"))
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
        FizzMenuButton(title: FizzL10n.text("已静默 \(suppressedItems.count) 项", "\(suppressedItems.count) muted"), symbol: "bell.slash") {
            Section(FizzL10n.text("已静默", "Muted")) {
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
            Button(FizzL10n.text("全部恢复", "Restore all"), systemImage: "bell", action: restoreAll)
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
        if let first = item.expiringMarks.first { return store.updatingMarkPins.contains(first.mark.id) }
        if item.kind == .testFailed, actions.testRuns[item.project.path]?.status == .running {
            return true
        }
        return gitActions[item.id] != nil
    }

    private func perform(_ action: AttentionInlineAction, for item: ProjectAttentionItem) {
        switch action {
        case .pinMark:
            guard let mark = item.expiringMarks.first?.mark else { return }
            feedback[item.id] = nil
            Task {
                if !(await store.setPinned(true, for: mark)) {
                    feedback[item.id] = .pinFailed
                }
            }
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
        feedback[pending.item.id] = result.succeeded ? .gitSuccess(pending.action) : .gitFailure(result.message)
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

    private func dismissExpiry(_ item: ProjectAttentionItem) {
        do {
            try store.dismissExpiryReminders(for: Set(item.expiringMarks.map(\.mark.id)))
            feedback[item.id] = nil
        } catch {
            feedback[item.id] = .dismissFailed
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
    let dismissExpiry: (() -> Void)?
    let perform: (AttentionInlineAction) -> Void

    @State private var hovering = false

    @ViewBuilder private var nameAndTag: some View {
        Text(item.project.displayName)
            .font(FizzTypography.cardTitle)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        Text(item.title)
            .font(FizzTypography.micro)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.kind.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: FizzRadius.inset))
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
            .help(item.kind == .expiringMarks ? FizzL10n.text("查看最早到期的标记，可在详情中永久保留", "Open the first mark to expire. Pin it in Progress to keep it.") : FizzL10n.text("打开 \(item.project.displayName) 的\(item.kind.tab.title(for: copyMode))；右键可稍后或忽略", "Open \(item.kind.tab.title(for: copyMode)) for \(item.project.displayName). Right-click to snooze or mute this reminder."))

            if isActing {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: FizzControlHeight.compact.rawValue, height: FizzControlHeight.compact.rawValue)
            } else if let inlineAction {
                if copyMode == .plain || inlineAction == .pinMark {
                    let title = inlineAction == .pinMark && item.expiringMarks.count > 1 ? FizzL10n.text("固定最早到期", "Pin earliest") : inlineAction.plainTitle
                    FizzActionButton(title: copied ? FizzL10n.text("已复制", "Copied") : title, height: .compact, keyboardNavigation: inlineAction == .pinMark) {
                        perform(inlineAction)
                    }
                } else {
                    FizzIconButton(title: inlineAction.title, symbol: copied ? "checkmark" : inlineAction.symbol, height: .compact) {
                        perform(inlineAction)
                    }
                }
            } else {
                FizzIconButton(title: FizzL10n.text("查看\(item.kind.tab.title(for: copyMode))", "View \(item.kind.tab.title(for: copyMode))"), symbol: "chevron.right", height: .compact, action: open)
            }
            if let dismissExpiry {
                FizzIconButton(title: FizzL10n.text("忽略本批提醒", "Dismiss these reminders"), symbol: "bell.slash", height: .compact, action: dismissExpiry)
            }
        }
        .padding(.vertical, FizzSpacing.row)
        .background(hovering ? FizzTheme.mutedFill : Color.clear, in: RoundedRectangle(cornerRadius: FizzRadius.inset))
        .onHover { hovering = $0 }
    }

}

private enum AttentionInlineAction {
    case pinMark
    case runTests
    case pull
    case push
    case copyCleanup

    var title: String {
        switch self {
        case .pinMark: FizzL10n.text("固定保留", "Pin mark")
        case .runTests: FizzL10n.text("运行测试", "Run tests")
        case .pull: FizzL10n.text("拉取远端", "Pull from remote")
        case .push: FizzL10n.text("推送提交", "Push commits")
        case .copyCleanup: FizzL10n.text("复制清理命令", "Copy cleanup commands")
        }
    }

    var plainTitle: String {
        switch self {
        case .pinMark: title
        case .runTests: FizzL10n.text("重新检查", "Check again")
        case .pull: FizzL10n.text("更新代码", "Update code")
        case .push: FizzL10n.text("上传版本", "Upload version")
        case .copyCleanup: FizzL10n.text("复制命令", "Copy command")
        }
    }

    var symbol: String {
        switch self {
        case .pinMark: "pin"
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

private enum AttentionFeedback {
    case pinFailed, dismissFailed, gitSuccess(GitSyncAction), gitFailure(String)

    var failed: Bool {
        if case .gitSuccess = self { return false }
        return true
    }

    var message: String {
        switch self {
        case .pinFailed: FizzL10n.text("未能固定标记，请刷新后重试", "Couldn’t pin the mark. Refresh and try again.")
        case .dismissFailed: FizzL10n.text("未能保存忽略状态", "Couldn’t save the dismissal.")
        case .gitSuccess(let action): action.successMessage
        case .gitFailure(let message): message
        }
    }
}

private extension ProjectAttentionItem {
    var inlineAction: AttentionInlineAction? {
        switch kind {
        case .expiringMarks: .pinMark
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
        case .expiringMarks: "clock"
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
        case .cleanup, .expiringMarks: Color.secondary
        }
    }

    var shortTitle: String {
        switch self {
        case .expiringMarks: FizzL10n.text("标记到期", "Expiring marks")
        case .doctorCritical: FizzL10n.text("体检阻塞", "Doctor issues")
        case .testFailed: FizzL10n.text("测试失败", "Tests failed")
        case .sessionError: FizzL10n.text("对话报错", "Conversation errors")
        case .dirty: FizzL10n.text("未提交", "Uncommitted")
        case .behind: FizzL10n.text("落后远端", "Behind remote")
        case .unpushed: FizzL10n.text("未推送", "Unpushed")
        case .cleanup: FizzL10n.text("可清理", "Reclaimable")
        }
    }
}
