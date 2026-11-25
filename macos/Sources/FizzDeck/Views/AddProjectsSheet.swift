import SwiftUI

struct AddProjectsSheet: View {
    @Environment(RepositoryStore.self) private var store
    @AppStorage("fizzdeck.scanDepth") private var depth = 3

    @State private var folder: URL?
    @State private var candidates: [DiscoveredProject] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = false
    @State private var isAdding = false

    private var managedPaths: Set<String> {
        Set(store.projects.map(\.path))
    }

    private var availablePaths: Set<String> {
        Set(candidates.map(\.path).filter { !managedPaths.contains($0) })
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
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 0) {
                    folderPane
                        .frame(width: 302)

                    Divider()

                    scanPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 856, height: 576)
                .glassEffect(
                    .regular.tint(.white.opacity(0.22)),
                    in: .rect(cornerRadius: 28, style: .continuous)
                )
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 36, y: 18)
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
                Text("文件夹")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                Button(action: close) {
                    FizzIcon(symbol: "xmark", size: 11)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()

            HStack {
                Text("已加入")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(roots.count)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

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
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            Divider()

            HStack(spacing: 10) {
                Button(action: chooseFolder) {
                    Label {
                        Text("添加文件夹…")
                    } icon: {
                        FizzIcon(symbol: "plus", size: 11)
                    }
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(isAdding)
                .accessibilityLabel("添加文件夹")

                Spacer()

                Button("恢复默认") {
                    depth = 3
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .disabled(depth == 3)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)

            Divider()

            HStack(spacing: 8) {
                Text("文件夹层级")
                    .font(.system(size: 12))

                Spacer()

                Text("\(depth)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)

                Stepper("", value: $depth, in: 1...10)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(isAdding)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .help("扫描层级越深，查找范围越大")
        }
    }

    private var emptyFolders: some View {
        VStack(spacing: 7) {
            FizzIcon(symbol: "folder.badge.plus", size: 22)
                .foregroundStyle(.tertiary)
            Text("还没有加入文件夹")
                .font(.system(size: 12, weight: .medium))
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
            HStack(spacing: 10) {
                FizzIcon(symbol: "folder.fill", size: 18)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: path))
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    Text(PathTools.displayPath(path))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selectedRoot {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FizzTheme.selectedFill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                scanContent(folder)
                Divider()
                footer
            }
        } else {
            ContentUnavailableView {
                Label("选择要扫描的文件夹", systemImage: "folder.badge.plus")
            } description: {
                Text("从左侧添加父文件夹，按 .git、package.json、CLAUDE.md 等特征找出项目。")
            } actions: {
                Button("添加文件夹…", action: chooseFolder)
                    .buttonStyle(.glassProminent)
                    .disabled(isAdding)
            }
        }
    }

    private func scanHeader(_ folder: URL) -> some View {
        HStack(spacing: 10) {
            FizzIcon(symbol: "folder.fill", size: 18)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                Text(PathTools.displayPath(folder.path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("发现 \(candidates.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: chooseFolder) {
                FizzIcon(symbol: "folder.badge.plus", size: 14)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(isLoading || isAdding)
            .help("更换扫描文件夹")
            .accessibilityLabel("更换扫描文件夹")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    @ViewBuilder
    private func scanContent(_ folder: URL) -> some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在查找项目…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            ContentUnavailableView {
                Label("没有发现项目", systemImage: "folder.badge.questionmark")
            } description: {
                Text("没有匹配到项目特征。可以调整左侧层级，或只添加当前文件夹。")
            } actions: {
                Button("只添加当前文件夹") {
                    Task { await add(paths: [folder.path]) }
                }
                .disabled(isAdding)
            }
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

        return HStack(spacing: 11) {
            FizzIcon(symbol: "folder.fill", size: 18)
                .foregroundStyle(managed ? .green : (isSelected ? FizzTheme.accent : .blue))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(candidate.name)
                        .font(.system(size: 12.5, weight: .semibold))

                    if candidate.hasGit {
                        TagChip(text: "git", tint: .green, compact: true)
                    }
                }

                Text(PathTools.displayPath(candidate.path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !candidate.markers.isEmpty {
                    Text(candidate.markers.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if managed {
                Label {
                    Text("已加入")
                } icon: {
                    FizzIcon(symbol: "checkmark.circle.fill", size: 11)
                }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Toggle("", isOn: selectionBinding(candidate.path))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
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
        HStack(spacing: 10) {
            if !isLoading && !availablePaths.isEmpty {
                Button("全选") {
                    selected = ProjectDiscovery.defaultSelection(
                        projects: candidates,
                        excluding: managedPaths
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("清空") {
                    selected.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("已选 \(selected.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("取消", action: close)
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            Button {
                Task { await add(paths: selectedPaths) }
            } label: {
                if isAdding {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 92)
                } else {
                    Text(selected.isEmpty ? "添加项目" : "添加 \(selected.count) 个项目")
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty || isLoading || isAdding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            ProjectDiscovery.discover(in: currentFolder, maxDepth: requestedDepth)
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
