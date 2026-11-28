import SwiftUI

struct AddProjectsSheet: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("fizzdeck.scanDepth") private var depth = 3

    @State private var folder: URL?
    @State private var candidates: [DiscoveredProject] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = false
    @State private var isAdding = false

    private var managedPaths: Set<String> {
        Set(store.projects.map(\.path))
    }

    private var hasAvailableCandidates: Bool {
        let managed = managedPaths
        return candidates.contains { !managed.contains($0.path) }
    }

    private var selectedPaths: [String] {
        selected.sorted()
    }

    private var roots: [String] {
        store.roots.sorted {
            PathTools.displayPath($0).localizedStandardCompare(PathTools.displayPath($1))
                == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            GlassEffectContainer(spacing: FizzSpacing.panel) {
                VStack(spacing: 0) {
                    FizzSheetHeader(title: "添加项目", onClose: close)
                        .padding(.horizontal, FizzSpacing.page)
                        .padding(.vertical, FizzSpacing.panel)

                    Divider()

                    HStack(spacing: 0) {
                        folderPane
                            .frame(width: 302)

                        Divider()

                        scanPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider()

                    footer
                        .padding(.horizontal, FizzSpacing.page)
                        .padding(.vertical, FizzSpacing.grid)
                }
                .frame(width: 856, height: 576)
                .background(
                    FizzTheme.elevatedFill.opacity(colorScheme == .dark ? 0.97 : 0.94),
                    in: .rect(cornerRadius: FizzRadius.frame, style: .continuous)
                )
                .glassEffect(
                    .regular.tint(FizzTheme.elevatedFill.opacity(colorScheme == .dark ? 0.18 : 0.14)),
                    in: .rect(cornerRadius: FizzRadius.frame, style: .continuous)
                )
                .clipShape(.rect(cornerRadius: FizzRadius.frame, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FizzRadius.frame, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : FizzTheme.stroke,
                            lineWidth: 1
                        )
                }
                .fizzAdaptiveShadow(.floating)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .onExitCommand(perform: close)
        .onAppear {
            depth = min(max(depth, 1), 10)
        }
        .onChange(of: depth) {
            guard folder != nil else { return }
            Task { await scan() }
        }
        .onDisappear {
            store.dismissFolderManager()
        }
    }

    private var folderPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已加入的文件夹")
                    .font(FizzTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("\(roots.count)")
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, FizzSpacing.panel)
            .padding(.vertical, FizzSpacing.grid)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if roots.isEmpty {
                        emptyFolders
                    } else {
                        ForEach(roots, id: \.self) { path in
                            existingFolderRow(path)
                        }
                    }
                }
                .padding(.horizontal, FizzSpacing.row)
                .padding(.bottom, FizzSpacing.row)
            }
            .scrollIndicators(.hidden)

            Divider()

            HStack(spacing: FizzSpacing.row) {
                Text("文件夹层级")
                    .font(FizzTypography.body)

                Spacer()

                Text("\(depth)")
                    .font(FizzTypography.mono)
                    .foregroundStyle(.secondary)

                Stepper("文件夹层级", value: $depth, in: 1...10)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(isAdding)

                FizzIconButton(title: "恢复默认层级", symbol: "arrow.uturn.backward", height: .compact) {
                    depth = 3
                }
                .disabled(depth == 3)
            }
            .padding(.horizontal, FizzSpacing.panel)
            .padding(.vertical, FizzSpacing.row)
            .help("扫描层级越深，查找范围越大")
        }
    }

    private var emptyFolders: some View {
        VStack(spacing: FizzSpacing.row) {
            FizzIcon(.lg, symbol: "folder.badge.plus")
                .foregroundStyle(.tertiary)
            Text("还没有加入文件夹")
                .font(FizzTypography.body(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private func existingFolderRow(_ path: String) -> some View {
        let selectedRoot = store.selectedPath == path

        return Button {
            openRoot(path)
        } label: {
            HStack(spacing: FizzSpacing.row) {
                FizzIcon(.md, symbol: "folder.fill")
                    .foregroundStyle(Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: path))
                        .font(FizzTypography.body(.medium))
                        .lineLimit(1)

                    Text(PathTools.displayPath(path))
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(FizzSpacing.row)
            .background {
                if selectedRoot {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 \(displayName(for: path))")
    }

    @ViewBuilder
    private var scanPane: some View {
        if let folder {
            VStack(spacing: 0) {
                scanHeader(folder)
                Divider()
                scanContent
            }
        } else {
            ContentUnavailableView(
                "选择要扫描的文件夹",
                systemImage: "folder.badge.plus",
                description: Text("选择父文件夹后，按 .git、package.json、CLAUDE.md 等特征找出项目。")
            )
        }
    }

    private func scanHeader(_ folder: URL) -> some View {
        HStack(spacing: FizzSpacing.grid) {
            FizzIcon(.md, symbol: "folder.fill")
                .foregroundStyle(Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.lastPathComponent)
                    .font(FizzTypography.cardTitle)
                Text(PathTools.displayPath(folder.path))
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("发现 \(candidates.count) 个")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }

            FizzActionButton(title: "更换文件夹…", symbol: "folder.badge.plus", height: .compact, action: chooseFolder)
                .disabled(isAdding)
        }
        .padding(.horizontal, FizzSpacing.panel)
        .padding(.vertical, FizzSpacing.grid)
    }

    @ViewBuilder
    private var scanContent: some View {
        if isLoading {
            VStack(spacing: FizzSpacing.row) {
                ProgressView()
                    .controlSize(.small)
                Text("正在查找项目…")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            ContentUnavailableView(
                "没有发现项目",
                systemImage: "folder.badge.questionmark",
                description: Text("没有匹配到项目特征。可以调整左侧层级，或只添加当前文件夹。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: DiscoveredProject) -> some View {
        let managed = managedPaths.contains(candidate.path)
        let isSelected = selected.contains(candidate.path)

        return HStack(spacing: FizzSpacing.grid) {
            FizzIcon(.md, symbol: "folder.fill")
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(candidate.name)
                        .font(FizzTypography.cardTitle)

                    TagChip(text: candidate.kind.title, compact: true)

                    if candidate.hasGit {
                        TagChip(text: "git", compact: true)
                    }

                    ForEach(candidate.tools.prefix(3)) { tool in
                        TagChip(text: tool.shortTitle, compact: true)
                    }
                }

                Text(PathTools.displayPath(candidate.path))
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !candidate.markers.isEmpty {
                    Text(candidate.markers.joined(separator: " · "))
                        .font(FizzTypography.micro)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: FizzSpacing.grid)

            if managed {
                Label {
                    Text("已加入")
                } icon: {
                    FizzIcon(.sm, symbol: "checkmark.circle.fill")
                }
                    .font(FizzTypography.caption(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Toggle("选择 \(candidate.name)", isOn: selectionBinding(candidate.path))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: FizzControlHeight.compact.rawValue, height: FizzControlHeight.compact.rawValue)
            }
        }
        .padding(.horizontal, FizzSpacing.panel)
        .padding(.vertical, FizzSpacing.row)
        .background {
            if isSelected {
                FizzTheme.selectedFill.opacity(0.65)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !managed else { return }
            toggle(candidate.path)
        }
    }

    private var footer: some View {
        FizzSheetFooter {
            if folder != nil {
                if isAdding {
                    ProgressView().controlSize(.small)
                }

                Text("已选 \(selected.count) 个")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)

                if !isLoading && hasAvailableCandidates {
                    FizzMenuButton(title: "批量选择", height: .standard) {
                        Button("全选") {
                            selected = ProjectDiscovery.defaultSelection(projects: candidates, excluding: managedPaths)
                        }
                        Button("清空") { selected.removeAll() }
                    }
                }
            }

            Spacer(minLength: FizzSpacing.row)

            FizzActionButton(title: "取消", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)

            if let folder, !isLoading, candidates.isEmpty {
                FizzActionButton(title: isAdding ? "正在添加…" : "只添加当前文件夹", prominence: .primary) {
                    Task { await add(paths: [folder.path]) }
                }
                .disabled(isAdding)
            } else if folder != nil {
                FizzActionButton(title: addSelectedTitle, prominence: .primary) {
                    Task { await add(paths: selectedPaths) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || isLoading || isAdding)
            } else {
                FizzActionButton(title: "添加文件夹…", symbol: "plus", prominence: .primary, action: chooseFolder)
            }
        }
    }

    private var addSelectedTitle: String {
        if isAdding { return "正在添加…" }
        return selected.isEmpty ? "添加项目" : "添加 \(selected.count) 个项目"
    }

    private func displayName(for path: String) -> String {
        store.projects.first(where: { $0.path == path })?.displayName
            ?? URL(fileURLWithPath: path).lastPathComponent
    }

    private func openRoot(_ path: String) {
        if let project = store.projects.first(where: { $0.path == path }) {
            store.openProject(project)
        } else {
            store.selectedPath = path
            store.requestedTab = nil
        }
        close()
    }

    private func selectionBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(path) },
            set: { isSelected in
                if isSelected {
                    selected = ProjectDiscovery.selecting(path, in: selected)
                } else {
                    selected.remove(path)
                }
            }
        )
    }

    private func toggle(_ path: String) {
        selected = ProjectDiscovery.toggling(path, in: selected)
    }

    private func chooseFolder() {
        guard !isAdding, let chosen = store.chooseFolderForScan() else { return }
        folder = chosen
        candidates = []
        selected.removeAll()
        isLoading = true
        Task { await scan() }
    }

    private func scan() async {
        guard let currentFolder = folder else {
            candidates = []
            selected.removeAll()
            isLoading = false
            return
        }

        isLoading = true
        let requestedDepth = depth
        let found = await Task.detached(priority: .userInitiated) {
            let evidence = ToolEvidenceIndex.build()
            return ProjectDiscovery.discover(
                in: currentFolder,
                maxDepth: requestedDepth,
                evidenceIndex: evidence
            )
        }.value
        guard !Task.isCancelled,
              folder?.path == currentFolder.path,
              depth == requestedDepth
        else { return }

        candidates = found
        selected = ProjectDiscovery.defaultSelection(
            projects: found,
            excluding: Set(store.projects.map(\.path))
        )
        isLoading = false
    }

    private func add(paths: [String]) async {
        guard !isAdding, !paths.isEmpty else { return }
        isAdding = true
        await store.addProjects(paths: paths)
        close()
    }

    private func close() {
        store.dismissFolderManager()
    }
}
