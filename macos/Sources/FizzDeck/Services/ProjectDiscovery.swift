import Foundation

enum DiscoveryScopeCategory: String, Codable, Sendable {
    case suggested
    case systemProtected
    case home
    case volume
    case custom
}

struct DiscoveryScope: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let path: String
    let maxDepth: Int
    let category: DiscoveryScopeCategory
    var selectedByDefault: Bool
    var detail: String?
}

struct DiscoveryProgress: Sendable {
    let discoveredCount: Int
    let scannedFolders: Int
    let currentPath: String
}

struct DiscoveryReport: Sendable {
    let projects: [DiscoveredProject]
    let permissionDeniedPaths: [String]
    let cancelled: Bool
    let reachedLimit: Bool
}

struct DiscoveredProject: Identifiable, Hashable, Sendable {
    let path: String
    let markers: [String]
    var kind: ProjectKind = .other
    var tools: [DetectedTool] = []
    var highConfidence: Bool = true

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var hasGit: Bool { markers.contains(".git") }

    init(
        path: String,
        markers: [String],
        kind: ProjectKind = .other,
        tools: [DetectedTool] = [],
        highConfidence: Bool = true
    ) {
        self.path = path
        self.markers = markers
        self.kind = kind
        self.tools = tools
        self.highConfidence = highConfidence
    }
}

enum ProjectDiscovery {
    private static let strongFileMarkers = [
        "package.json",
        "pnpm-workspace.yaml",
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "settings.gradle",
        "settings.gradle.kts",
        "Cargo.toml",
        "go.mod",
        "pyproject.toml",
        "requirements.txt",
        "Pipfile",
        "Gemfile",
        "composer.json",
        "mix.exs",
        "Package.swift",
        "pubspec.yaml",
        "project.config.json",
        "project.godot",
    ]

    private static let weakDocMarkers = [
        "CLAUDE.md",
        "AGENTS.md",
        "SKILL.md",
        "GEMINI.md",
    ]

    private static let fileMarkers = strongFileMarkers + weakDocMarkers

    private static let generatedDirectories: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData",
        "build", "dist", "out", "target", "coverage",
        "vendor", "venv", ".venv", "__pycache__", "bin", "obj",
        "Library", "Applications", "System", "private", "Trash",
    ]

    private static let homeOnlySkippedDirectories: Set<String> = [
        "Downloads", "Desktop", "Documents", "Public",
        "Pictures", "Movies", "Music", "Trash",
    ]

    static func suggestedScopes(
        homeDirectory: URL = AppPaths.home,
        volumesRoot: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
    ) -> [DiscoveryScope] {
        var scopes: [DiscoveryScope] = []
        var seenCanonical = Set<String>()

        func appendScope(
            url: URL,
            title: String? = nil,
            maxDepth: Int,
            category: DiscoveryScopeCategory,
            selectedByDefault: Bool,
            detail: String? = nil
        ) {
            guard FileTools.isDirectory(url) else { return }
            let normalized = PathTools.normalize(url.path)
            let canonical = PathTools.canonical(url.path)
            guard seenCanonical.insert(canonical).inserted else { return }
            scopes.append(DiscoveryScope(
                id: "\(category.rawValue):\(normalized)",
                title: title ?? PathTools.displayPath(normalized),
                path: normalized,
                maxDepth: maxDepth,
                category: category,
                selectedByDefault: selectedByDefault,
                detail: detail
            ))
        }

        let commonNames = [
            "Projects", "Workspace", "Workspaces", "Code", "Dev", "Developer", "Repos", "Sites",
        ]
        for name in commonNames {
            appendScope(
                url: homeDirectory.appendingPathComponent(name, isDirectory: true),
                maxDepth: 4,
                category: .suggested,
                selectedByDefault: true,
                detail: "常见开发目录（深度 4）"
            )
        }

        for child in FileTools.childDirectories(of: homeDirectory)
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = child.lastPathComponent
            let lower = name.lowercased()
            guard !name.hasPrefix("."),
                  lower == "workspace" || lower.hasSuffix("-workspace") || lower.hasSuffix("_workspace")
            else { continue }
            appendScope(
                url: child,
                maxDepth: 4,
                category: .suggested,
                selectedByDefault: true,
                detail: "工作区目录（深度 4）"
            )
        }

        for name in ["Documents", "Desktop", "Downloads"] {
            appendScope(
                url: homeDirectory.appendingPathComponent(name, isDirectory: true),
                maxDepth: 4,
                category: .systemProtected,
                selectedByDefault: false,
                detail: "系统受保护目录，勾选后可能请求文件权限"
            )
        }

        appendScope(
            url: homeDirectory,
            title: "主目录 (~)",
            maxDepth: 3,
            category: .home,
            selectedByDefault: false,
            detail: "浅扫主目录 3 层（跳过 Library / 系统 / 媒体目录）"
        )

        if FileTools.isDirectory(volumesRoot) {
            for volume in FileTools.childEntries(of: volumesRoot)
                .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let name = volume.lastPathComponent
                guard !name.hasPrefix("."),
                      !name.localizedCaseInsensitiveContains("Time Machine")
                else { continue }
                let values = try? volume.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .volumeIsRootFileSystemKey,
                    .volumeIsReadOnlyKey,
                ])
                guard values?.isDirectory == true,
                      values?.isSymbolicLink != true,
                      values?.volumeIsRootFileSystem != true,
                      values?.volumeIsReadOnly != true
                else { continue }
                appendScope(
                    url: volume,
                    title: "卷：\(name)",
                    maxDepth: 3,
                    category: .volume,
                    selectedByDefault: false,
                    detail: "外置挂载卷（深度 3）"
                )
            }
        }

        return scopes
    }

    static func discover(
        in folder: URL,
        maxDepth: Int = 3,
        limit: Int = 200,
        evidenceIndex: ToolEvidenceIndex = .empty
    ) -> [DiscoveredProject] {
        guard FileTools.isDirectory(folder) else { return [] }

        var results: [DiscoveredProject] = []
        var seen = Set<String>()
        var denied = Set<String>()
        var scannedFolders = 0
        let basePath = PathTools.normalize(folder.path)
        let isHome = PathTools.canonical(basePath) == PathTools.canonical(AppPaths.home.path)

        walk(
            URL(fileURLWithPath: basePath, isDirectory: true),
            depth: 0,
            maxDepth: max(0, min(maxDepth, 10)),
            limit: max(1, limit),
            skipHomeFolders: isHome,
            evidenceIndex: evidenceIndex,
            results: &results,
            seen: &seen,
            denied: &denied,
            scannedFolders: &scannedFolders,
            shouldCancel: { false },
            onDiscover: nil
        )

        let baseDepth = URL(fileURLWithPath: basePath).pathComponents.count
        return results.sorted {
            let leftDepth = URL(fileURLWithPath: $0.path).pathComponents.count - baseDepth
            let rightDepth = URL(fileURLWithPath: $1.path).pathComponents.count - baseDepth
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func discoverStreaming(
        scopes: [DiscoveryScope],
        limit: Int = 300,
        evidenceIndex: ToolEvidenceIndex? = nil,
        onProgress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async -> DiscoveryReport {
        let work = Task.detached(priority: .userInitiated) {
            let index = evidenceIndex ?? ToolEvidenceIndex.build()
            var results: [DiscoveredProject] = []
            var seen = Set<String>()
            var denied = Set<String>()
            var scannedFolders = 0
            let cappedLimit = max(1, limit)
            var lastReportAt = Date.distantPast

            for scope in scopes {
                if Task.isCancelled || results.count >= cappedLimit { break }
                let folder = URL(fileURLWithPath: scope.path, isDirectory: true)
                guard FileTools.isDirectory(folder) else { continue }

                walk(
                    folder,
                    depth: 0,
                    maxDepth: max(0, min(scope.maxDepth, 10)),
                    limit: cappedLimit,
                    skipHomeFolders: scope.category == .home,
                    evidenceIndex: index,
                    results: &results,
                    seen: &seen,
                    denied: &denied,
                    scannedFolders: &scannedFolders,
                    shouldCancel: { Task.isCancelled },
                    onDiscover: { currentPath, count, folders in
                        let now = Date()
                        if now.timeIntervalSince(lastReportAt) >= 0.06 {
                            lastReportAt = now
                            let progress = DiscoveryProgress(
                                discoveredCount: count,
                                scannedFolders: folders,
                                currentPath: currentPath
                            )
                            Task { await onProgress(progress) }
                        }
                    }
                )
            }

            let sorted = results.sorted {
                if $0.highConfidence != $1.highConfidence {
                    return $0.highConfidence && !$1.highConfidence
                }
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            await onProgress(DiscoveryProgress(
                discoveredCount: sorted.count,
                scannedFolders: scannedFolders,
                currentPath: ""
            ))
            return DiscoveryReport(
                projects: sorted,
                permissionDeniedPaths: denied.sorted(),
                cancelled: Task.isCancelled,
                reachedLimit: sorted.count >= cappedLimit
            )
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    static func defaultSelection(
        projects: [DiscoveredProject],
        excluding managedPaths: Set<String>,
        highConfidenceOnly: Bool = true
    ) -> Set<String> {
        let available = projects.filter {
            !managedPaths.contains($0.path) && (!highConfidenceOnly || $0.highConfidence)
        }
        let paths = Set(available.map(\.path))
        return Set(available.compactMap { project in
            let hasSelectedParent = paths.contains { candidate in
                candidate != project.path && isDescendant(project.path, of: candidate)
            }
            return hasSelectedParent ? nil : project.path
        })
    }

    static func toggling(_ path: String, in selection: Set<String>) -> Set<String> {
        if selection.contains(path) {
            return selection.subtracting([path])
        }
        return selecting(path, in: selection)
    }

    static func selecting(_ path: String, in selection: Set<String>) -> Set<String> {
        guard !selection.contains(path) else { return selection }
        let nonOverlapping = selection.filter { existing in
            !isDescendant(existing, of: path) && !isDescendant(path, of: existing)
        }
        return nonOverlapping.union([path])
    }

    private static func isDescendant(_ path: String, of parent: String) -> Bool {
        path != parent && path.hasPrefix(parent + "/")
    }

    private static func walk(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        limit: Int,
        skipHomeFolders: Bool,
        evidenceIndex: ToolEvidenceIndex,
        results: inout [DiscoveredProject],
        seen: inout Set<String>,
        denied: inout Set<String>,
        scannedFolders: inout Int,
        shouldCancel: () -> Bool,
        onDiscover: ((String, Int, Int) -> Void)?
    ) {
        guard !shouldCancel(), results.count < limit else { return }
        scannedFolders += 1
        let currentFolderCount = scannedFolders

        let entries: [URL]
        switch FileTools.readChildEntries(of: directory) {
        case let .entries(list):
            entries = list
        case .permissionDenied:
            denied.insert(PathTools.normalize(directory.path))
            return
        case .unreadable:
            return
        }

        let names = Set(entries.map(\.lastPathComponent))
        let markers = detectMarkers(in: directory, names: names)

        if !markers.isEmpty {
            let path = PathTools.normalize(directory.path)
            if seen.insert(path).inserted {
                let kind = ProjectKindDetector.detect(directory: directory, entryNames: names)
                let tools = ToolEvidenceDetector.detect(
                    directory: directory,
                    entryNames: names,
                    index: evidenceIndex
                )
                let highConfidence = hasStrongMarker(markers)
                results.append(DiscoveredProject(
                    path: path,
                    markers: markers,
                    kind: kind,
                    tools: tools,
                    highConfidence: highConfidence
                ))
                onDiscover?(path, results.count, currentFolderCount)
            }
        } else {
            onDiscover?(directory.path, results.count, currentFolderCount)
        }

        guard depth < maxDepth else { return }
        for child in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !shouldCancel(), results.count < limit else { return }
            let name = child.lastPathComponent
            guard !shouldSkip(directory: name, depth: depth, skipHomeFolders: skipHomeFolders) else { continue }
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { continue }
            walk(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                limit: limit,
                skipHomeFolders: skipHomeFolders,
                evidenceIndex: evidenceIndex,
                results: &results,
                seen: &seen,
                denied: &denied,
                scannedFolders: &scannedFolders,
                shouldCancel: shouldCancel,
                onDiscover: onDiscover
            )
        }
    }

    private static func detectMarkers(in directory: URL, names: Set<String>) -> [String] {
        let lowercased = Set(names.map { $0.lowercased() })
        var markers = fileMarkers.filter { lowercased.contains($0.lowercased()) }

        if names.contains(".git") {
            markers.insert(".git", at: 0)
        }
        if names.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            markers.append(".xcodeproj")
        } else if names.contains(where: { $0.hasSuffix(".xcworkspace") }) {
            markers.append(".xcworkspace")
        }
        if names.contains(where: { $0.lowercased().hasSuffix(".uproject") }) {
            markers.append(".uproject")
        }
        if names.contains("ProjectSettings"),
           FileTools.exists(directory.appendingPathComponent("ProjectSettings/ProjectVersion.txt")) {
            markers.append("ProjectSettings/ProjectVersion.txt")
        }
        return markers
    }

    private static func hasStrongMarker(_ markers: [String]) -> Bool {
        let weakSet = Set(weakDocMarkers.map { $0.lowercased() })
        return markers.contains { !weakSet.contains($0.lowercased()) }
    }

    private static func shouldSkip(directory name: String, depth: Int, skipHomeFolders: Bool) -> Bool {
        if name.hasPrefix(".") { return true }
        if generatedDirectories.contains(name) { return true }
        if skipHomeFolders && depth == 0 && homeOnlySkippedDirectories.contains(name) { return true }
        return name.hasPrefix("dist-")
    }
}
