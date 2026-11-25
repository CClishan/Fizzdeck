import Foundation

struct DiscoveredProject: Identifiable, Hashable, Sendable {
    let path: String
    let markers: [String]

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var hasGit: Bool { markers.contains(".git") }
}

enum ProjectDiscovery {
    private static let fileMarkers = [
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
        "CLAUDE.md",
        "AGENTS.md",
        "SKILL.md",
    ]

    private static let generatedDirectories: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData",
        "build", "dist", "out", "target", "coverage",
        "vendor", "venv", "__pycache__", "bin", "obj",
        "Library", "Applications", "System", "private",
        "Downloads", "Desktop", "Documents", "Public",
        "Pictures", "Movies", "Music", "Trash",
    ]

    static func discover(in folder: URL, maxDepth: Int = 3, limit: Int = 200) -> [DiscoveredProject] {
        guard FileTools.isDirectory(folder) else { return [] }

        var results: [DiscoveredProject] = []
        var seen = Set<String>()
        let basePath = PathTools.normalize(folder.path)
        walk(
            URL(fileURLWithPath: basePath, isDirectory: true),
            depth: 0,
            maxDepth: max(0, min(maxDepth, 10)),
            limit: max(1, limit),
            results: &results,
            seen: &seen
        )

        let baseDepth = URL(fileURLWithPath: basePath).pathComponents.count
        return results.sorted {
            let leftDepth = URL(fileURLWithPath: $0.path).pathComponents.count - baseDepth
            let rightDepth = URL(fileURLWithPath: $1.path).pathComponents.count - baseDepth
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func defaultSelection(
        projects: [DiscoveredProject],
        excluding managedPaths: Set<String>
    ) -> Set<String> {
        let available = projects.filter { !managedPaths.contains($0.path) }
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
        results: inout [DiscoveredProject],
        seen: inout Set<String>
    ) {
        guard results.count < limit else { return }
        let entries = FileTools.childEntries(of: directory)
        let names = Set(entries.map(\.lastPathComponent))
        let markers = detectMarkers(names: names)

        if !markers.isEmpty {
            let path = PathTools.normalize(directory.path)
            if seen.insert(path).inserted {
                results.append(DiscoveredProject(path: path, markers: markers))
            }
        }

        guard depth < maxDepth else { return }
        for child in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard results.count < limit else { return }
            let name = child.lastPathComponent
            guard !shouldSkip(directory: name) else { continue }
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { continue }
            walk(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                limit: limit,
                results: &results,
                seen: &seen
            )
        }
    }

    private static func detectMarkers(names: Set<String>) -> [String] {
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
        return markers
    }

    private static func shouldSkip(directory name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if generatedDirectories.contains(name) { return true }
        return name.hasPrefix("dist-")
    }
}
