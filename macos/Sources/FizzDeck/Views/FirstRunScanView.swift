import SwiftUI

struct FirstRunScanView: View {
    @Environment(RepositoryStore.self) private var store

    private enum Stage {
        case configure
        case scanning
        case report(DiscoveryReport)
    }

    @State private var stage: Stage = .configure
    @State private var scopes: [DiscoveryScope] = []
    @State private var selectedScopeIDs: Set<String> = []
    @State private var progress = DiscoveryProgress(discoveredCount: 0, scannedFolders: 0, currentPath: "")
    @State private var selectedProjects: Set<String> = []
    @State private var scanTask: Task<Void, Never>?
    @State private var isAdding = false

    private var managedPaths: Set<String> {
        Set(store.projects.map(\.path))
    }

    private var selectedScopes: [DiscoveryScope] {
        scopes.filter { selectedScopeIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topHeader
            Divider()

            Group {
                switch stage {
                case .configure:
                    configureBody
                case .scanning:
                    scanningBody
                case let .report(report):
                    ScanReportView(
                        report: report,
                        managedPaths: managedPaths,
                        selected: $selectedProjects,
                        onRescan: startScan
                    )
                    .padding(FizzSpacing.page)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footerBar
        }
        .background(FizzBackground())
        .onAppear(perform: loadScopesIfNeeded)
        .onDisappear {
            scanTask?.cancel()
            scanTask = nil
        }
    }

    private var topHeader: some View {
        HStack(spacing: 12) {
            FizzLogo(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(FizzL10n.text("发现本机项目", "Find local projects"))
                    .font(FizzTypography.font(18, weight: .semibold))
                Text(FizzL10n.text("先快速预览目录标记与工具痕迹，由你决定把哪些项目加入 FizzDeck。", "Preview project markers and tool activity, then choose which projects to add to FizzDeck."))
                    .font(FizzTypography.font(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var configureBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                scopeSection(
                    title: FizzL10n.text("建议开发目录（默认勾选）", "Suggested folders (preselected)"),
                    subtitle: FizzL10n.text("只读目录名、工程标记与本地工具证据，不执行 Git 与磁盘统计。", "Checks folder names, project markers, and local tool activity. Skips Git commands and size calculations."),
                    items: scopes.filter { $0.category == .suggested || $0.category == .custom }
                )

                scopeSection(
                    title: FizzL10n.text("更多位置（按需勾选）", "Other locations (optional)"),
                    subtitle: FizzL10n.text("勾选桌面/文稿/下载会触发系统文件访问权限；外置磁盘可能较慢。", "macOS may ask for access to Desktop, Documents, or Downloads. External drives can take longer to scan."),
                    items: scopes.filter {
                        $0.category == .systemProtected || $0.category == .home || $0.category == .volume
                    }
                )

                Button {
                    addCustomScope()
                } label: {
                    Label(FizzL10n.text("添加其他文件夹…", "Add another folder…"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
            }
            .padding(FizzSpacing.page)
        }
    }

    @ViewBuilder
    private func scopeSection(title: String, subtitle: String, items: [DiscoveryScope]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FizzTypography.cardTitle)
                    Text(subtitle)
                        .font(FizzTypography.micro(.regular))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(items) { scope in
                        let title = scope.scanTitle
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { selectedScopeIDs.contains(scope.id) },
                                set: { isOn in
                                    if isOn {
                                        selectedScopeIDs.insert(scope.id)
                                    } else {
                                        selectedScopeIDs.remove(scope.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                            FizzIcon(.md, symbol: "folder.fill")
                                .foregroundStyle(Color.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(FizzTypography.body(.medium))
                                Text(scope.scanHint)
                                    .font(FizzTypography.micro)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(FizzL10n.text("深度 \(scope.maxDepth)", "Depth \(scope.maxDepth)"))
                                .font(FizzTypography.micro)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedScopeIDs.contains(scope.id) {
                                selectedScopeIDs.remove(scope.id)
                            } else {
                                selectedScopeIDs.insert(scope.id)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(FizzL10n.text("扫描目录 \(title)", "Scan \(title)"))
                        .accessibilityValue(selectedScopeIDs.contains(scope.id) ? FizzL10n.text("已勾选", "Checked") : FizzL10n.text("未勾选", "Unchecked"))
                        .accessibilityHint(FizzL10n.text("双击切换是否扫描这个目录", "Double-click to include or exclude this folder"))
                        .accessibilityAddTraits(selectedScopeIDs.contains(scope.id) ? .isSelected : [])
                        .accessibilityRemoveTraits(selectedScopeIDs.contains(scope.id) ? [] : .isSelected)

                        if scope.id != items.last?.id {
                            Divider()
                                .padding(.leading, 38)
                        }
                    }
                }
                .fizzCard(radius: FizzRadius.card)
            }
        }
    }

    private var scanningBody: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(FizzL10n.text("已发现 \(progress.discoveredCount) 个项目", "\(SessionSummaryText.englishCount(progress.discoveredCount, "project")) found"))
                .font(FizzTypography.font(18, weight: .semibold))
            Text(FizzL10n.text("已扫描 \(progress.scannedFolders) 个目录", "\(SessionSummaryText.englishCount(progress.scannedFolders, "folder")) scanned"))
                .font(FizzTypography.micro(.regular))
                .foregroundStyle(.secondary)
            if !progress.currentPath.isEmpty {
                Text(PathTools.displayPath(progress.currentPath))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(FizzL10n.text("正在扫描", "Scanning"))
                .accessibilityValue(FizzL10n.text("已发现 \(progress.discoveredCount) 个项目，已扫描 \(progress.scannedFolders) 个目录", "\(SessionSummaryText.englishCount(progress.discoveredCount, "project")) found, \(SessionSummaryText.englishCount(progress.scannedFolders, "folder")) scanned"))
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            switch stage {
            case .configure:
                Button(FizzL10n.text("跳过，稍后添加", "Skip for now")) {
                    Task {
                        await store.completeFirstRun(selectedPaths: [], skipped: true)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint(FizzL10n.text("保留空列表，可从总览再次打开扫描", "Start with an empty list. You can scan later from Workbench."))

                Spacer()

                Text(FizzL10n.text("已选 \(selectedScopes.count) 个目录", "\(SessionSummaryText.englishCount(selectedScopes.count, "folder")) selected"))
                    .font(FizzTypography.micro(.regular))
                    .foregroundStyle(.secondary)

                Button(FizzL10n.text("一键开始扫描", "Start scan"), action: startScan)
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedScopes.isEmpty)
                    .accessibilityHint(FizzL10n.text("扫描已勾选目录，不执行 Git 或磁盘统计", "Scan the selected folders without running Git or calculating sizes"))

            case .scanning:
                Spacer()
                Button(FizzL10n.text("取消扫描", "Cancel scan")) {
                    cancelScan()
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            case .report:
                Button(FizzL10n.text("返回重选目录", "Choose folders again")) {
                    stage = .configure
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
                .disabled(isAdding)

                Button(FizzL10n.text("取消", "Cancel")) {
                    stage = .configure
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isAdding)

                Spacer()

                Text(FizzL10n.text("已选 \(selectedProjects.count) 个项目", "\(SessionSummaryText.englishCount(selectedProjects.count, "project")) selected"))
                    .font(FizzTypography.micro(.regular))
                    .foregroundStyle(.secondary)

                Button {
                    Task { await commitSelection() }
                } label: {
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(selectedProjects.isEmpty ? FizzL10n.text("加入项目", "Add projects") : FizzL10n.text("加入 \(selectedProjects.count) 个项目", "Add \(SessionSummaryText.englishCount(selectedProjects.count, "project"))"))
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
                .disabled(selectedProjects.isEmpty || isAdding)
            }
        }
        .padding(.horizontal, FizzSpacing.page)
        .padding(.vertical, 14)
    }

    private func loadScopesIfNeeded() {
        guard scopes.isEmpty else { return }
        let loaded = ProjectDiscovery.suggestedScopes()
        scopes = loaded
        selectedScopeIDs = Set(loaded.filter(\.selectedByDefault).map(\.id))
    }

    private func addCustomScope() {
        guard let chosen = store.chooseFolderForScan() else { return }
        let path = PathTools.normalize(chosen.path)
        let id = "custom:\(path)"
        if !scopes.contains(where: { PathTools.canonical($0.path) == PathTools.canonical(path) }) {
            scopes.insert(
                DiscoveryScope(
                    id: id,
                    title: PathTools.displayPath(path),
                    path: path,
                    maxDepth: 4,
                    category: .custom,
                    selectedByDefault: true
                ),
                at: 0
            )
            selectedScopeIDs.insert(id)
        } else if let existing = scopes.first(where: { PathTools.canonical($0.path) == PathTools.canonical(path) }) {
            selectedScopeIDs.insert(existing.id)
        }
    }

    private func startScan() {
        scanTask?.cancel()
        progress = DiscoveryProgress(discoveredCount: 0, scannedFolders: 0, currentPath: "")
        stage = .scanning
        let targets = selectedScopes

        scanTask = Task {
            let report = await ProjectDiscovery.discoverStreaming(
                scopes: targets,
                limit: 300
            ) { update in
                await MainActor.run {
                    self.progress = update
                }
            }
            guard !Task.isCancelled, !report.cancelled else { return }
            await MainActor.run {
                self.selectedProjects = ProjectDiscovery.defaultSelection(
                    projects: report.projects,
                    excluding: managedPaths,
                    highConfidenceOnly: true
                )
                self.stage = .report(report)
            }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        stage = .configure
    }

    private func commitSelection() async {
        guard !isAdding, !selectedProjects.isEmpty else { return }
        isAdding = true
        await store.completeFirstRun(selectedPaths: selectedProjects.sorted(), skipped: false)
        isAdding = false
    }
}

private extension DiscoveryScope {
    // Scope discovery probes the filesystem once. Keep paths and selection when only the language changes.
    var scanTitle: String {
        switch category {
        case .home: return FizzL10n.text("主目录 (~)", "Home (~)")
        case .volume:
            let name = URL(fileURLWithPath: path).lastPathComponent
            return FizzL10n.text("卷：\(name)", "Volume: \(name)")
        default: return title
        }
    }

    var scanHint: String {
        switch category {
        case .suggested: FizzL10n.text("建议开发目录", "Suggested development folder")
        case .systemProtected: FizzL10n.text("系统受保护目录，勾选后可能请求文件权限", "macOS may ask for permission to read this folder.")
        case .home: FizzL10n.text("跳过 Library、系统和媒体目录", "Skips Library, system, and media folders")
        case .volume: FizzL10n.text("外置挂载卷", "External volume")
        case .custom: FizzL10n.text("自定义目录", "Custom folder")
        }
    }
}
