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
                Text("发现本机项目")
                    .font(.system(size: 18, weight: .semibold))
                Text("先快速预览目录标记与工具痕迹，由你决定把哪些项目加入 FizzDeck。")
                    .font(.system(size: 12))
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
                    title: "建议开发目录（默认勾选）",
                    subtitle: "只读目录名、工程标记与本地工具证据，不执行 Git 与磁盘统计。",
                    items: scopes.filter { $0.category == .suggested || $0.category == .custom }
                )

                scopeSection(
                    title: "更多位置（按需勾选）",
                    subtitle: "勾选桌面/文稿/下载会触发系统文件访问权限；外置磁盘可能较慢。",
                    items: scopes.filter {
                        $0.category == .systemProtected || $0.category == .home || $0.category == .volume
                    }
                )

                Button {
                    addCustomScope()
                } label: {
                    Label("添加其他文件夹…", systemImage: "folder.badge.plus")
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
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(items) { scope in
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

                            FizzIcon(symbol: "folder.fill", size: 15)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(scope.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                if let detail = scope.detail {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text("深度 \(scope.maxDepth)")
                                .font(.caption2)
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
                        .accessibilityLabel("扫描目录 \(scope.title)")
                        .accessibilityValue(selectedScopeIDs.contains(scope.id) ? "已勾选" : "未勾选")
                        .accessibilityHint("双击切换是否扫描这个目录")
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
            Text("已发现 \(progress.discoveredCount) 个项目")
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
            Text("已扫描 \(progress.scannedFolders) 个目录")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if !progress.currentPath.isEmpty {
                Text(PathTools.displayPath(progress.currentPath))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在扫描")
                .accessibilityValue("已发现 \(progress.discoveredCount) 个项目，已扫描 \(progress.scannedFolders) 个目录")
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            switch stage {
            case .configure:
                Button("跳过，稍后添加") {
                    Task {
                        await store.completeFirstRun(selectedPaths: [], skipped: true)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint("保留空列表，可从总览再次打开扫描")

                Spacer()

                Text("已选 \(selectedScopes.count) 个目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("一键开始扫描", action: startScan)
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedScopes.isEmpty)
                    .accessibilityHint("扫描已勾选目录，不执行 Git 或磁盘统计")

            case .scanning:
                Spacer()
                Button("取消扫描") {
                    cancelScan()
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            case .report:
                Button("返回重选目录") {
                    stage = .configure
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
                .disabled(isAdding)

                Button("取消") {
                    stage = .configure
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isAdding)

                Spacer()

                Text("已选 \(selectedProjects.count) 个项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await commitSelection() }
                } label: {
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(selectedProjects.isEmpty ? "加入项目" : "加入 \(selectedProjects.count) 个项目")
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
                    selectedByDefault: true,
                    detail: "自定义目录（深度 4）"
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
