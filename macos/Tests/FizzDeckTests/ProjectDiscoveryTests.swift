import XCTest
@testable import FizzDeck

final class ProjectDiscoveryTests: XCTestCase {
    func testDiscoversNestedProjectsByMarkers() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try createFile("AGENTS.md", in: root)
        let packageProject = try makeDirectory("alpha", in: root)
        try createFile("package.json", in: packageProject)
        let claudeProject = try makeDirectory("beta", in: root)
        try createFile("Claude.md", in: claudeProject)
        let nested = try makeDirectory("nested", in: root)
        let goProject = try makeDirectory("gamma", in: nested)
        try createFile("go.mod", in: goProject)

        let found = ProjectDiscovery.discover(in: root, maxDepth: 3)

        XCTAssertEqual(
            found.map(\.path),
            [
                root.path,
                packageProject.path,
                claudeProject.path,
                goProject.path,
            ]
        )
        XCTAssertEqual(found.first?.markers, ["AGENTS.md"])
        XCTAssertEqual(found[2].markers, ["CLAUDE.md"])
    }

    func testSkipsGeneratedAndHiddenDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try createFile("package.json", in: root)
        let nodeModules = try makeDirectory("node_modules", in: root)
        let installed = try makeDirectory("installed", in: nodeModules)
        try createFile("package.json", in: installed)
        let build = try makeDirectory("build", in: root)
        try createFile("package.json", in: build)
        let hidden = try makeDirectory(".cache", in: root)
        let cached = try makeDirectory("project", in: hidden)
        try createFile("package.json", in: cached)

        let found = ProjectDiscovery.discover(in: root, maxDepth: 4)

        XCTAssertEqual(found.map(\.path), [root.path])
    }

    func testRespectsDepthLimit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let levelOne = try makeDirectory("one", in: root)
        let levelTwo = try makeDirectory("two", in: levelOne)
        try createFile("package.json", in: levelTwo)

        XCTAssertTrue(ProjectDiscovery.discover(in: root, maxDepth: 1).isEmpty)
        XCTAssertEqual(
            ProjectDiscovery.discover(in: root, maxDepth: 2).map(\.path),
            [levelTwo.path]
        )
    }

    func testDefaultSelectionPrefersTopLevelProjects() {
        let projects = [
            DiscoveredProject(path: "/work", markers: ["package.json"]),
            DiscoveredProject(path: "/work/packages/a", markers: ["package.json"]),
            DiscoveredProject(path: "/work/packages/b", markers: ["package.json"]),
        ]

        XCTAssertEqual(
            ProjectDiscovery.defaultSelection(projects: projects, excluding: []),
            ["/work"]
        )
        XCTAssertEqual(
            ProjectDiscovery.defaultSelection(projects: projects, excluding: ["/work"]),
            ["/work/packages/a", "/work/packages/b"]
        )
    }

    func testSelectionAvoidsParentChildOverlap() {
        var selection: Set<String> = []

        selection = ProjectDiscovery.selecting("/work", in: selection)
        selection = ProjectDiscovery.selecting("/work/packages/a", in: selection)
        XCTAssertEqual(selection, ["/work/packages/a"])

        selection = ProjectDiscovery.selecting("/work/packages/b", in: selection)
        XCTAssertEqual(selection, ["/work/packages/a", "/work/packages/b"])

        selection = ProjectDiscovery.selecting("/work/packages/a/nested", in: selection)
        XCTAssertEqual(selection, ["/work/packages/a/nested", "/work/packages/b"])

        selection = ProjectDiscovery.toggling("/work", in: selection)
        XCTAssertEqual(selection, ["/work"])
    }

    func testSuggestedScopesRespectsDefaultsAndFindsWorkspaceFolders() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        _ = try makeDirectory("Projects", in: home)
        _ = try makeDirectory("custom-workspace", in: home)
        _ = try makeDirectory("Documents", in: home)
        _ = try makeDirectory("Desktop", in: home)

        let scopes = ProjectDiscovery.suggestedScopes(
            homeDirectory: home,
            volumesRoot: home.appendingPathComponent("missing-volumes")
        )

        let defaultPaths = Set(scopes.filter(\.selectedByDefault).map(\.path))
        XCTAssertTrue(defaultPaths.contains(PathTools.normalize(home.appendingPathComponent("Projects").path)))
        XCTAssertTrue(defaultPaths.contains(PathTools.normalize(home.appendingPathComponent("custom-workspace").path)))
        XCTAssertFalse(defaultPaths.contains(PathTools.normalize(home.appendingPathComponent("Documents").path)))
        XCTAssertFalse(defaultPaths.contains(PathTools.normalize(home.appendingPathComponent("Desktop").path)))
    }

    func testDefaultSelectionExcludesWeakDocOnlyProjects() {
        let projects = [
            DiscoveredProject(path: "/work/strong", markers: ["package.json"], highConfidence: true),
            DiscoveredProject(path: "/work/weak", markers: ["AGENTS.md"], highConfidence: false),
        ]

        let selected = ProjectDiscovery.defaultSelection(
            projects: projects,
            excluding: [],
            highConfidenceOnly: true
        )
        XCTAssertEqual(selected, ["/work/strong"])
    }

    func testStreamingDiscoveryCapsAt300WithinBudget() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for i in 0..<320 {
            let dir = try makeDirectory(String(format: "proj-%03d", i), in: root)
            try createFile("package.json", in: dir)
        }

        let scope = DiscoveryScope(
            id: "test",
            title: "Test",
            path: root.path,
            maxDepth: 4,
            category: .suggested,
            selectedByDefault: true,
            detail: nil
        )
        let started = Date()
        let report = await ProjectDiscovery.discoverStreaming(
            scopes: [scope],
            limit: 300,
            evidenceIndex: .empty
        ) { _ in }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(report.projects.count, 300)
        XCTAssertTrue(report.reachedLimit)
        XCTAssertFalse(report.cancelled)
        XCTAssertLessThan(elapsed, 3.0)
    }

    func testStreamingDiscoveryReportsPermissionDeniedDirectories() async throws {
        let root = try makeTemporaryDirectory()
        let locked = try makeDirectory("locked", in: root)
        try createFile("package.json", in: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }

        let scope = DiscoveryScope(
            id: "test-perm",
            title: "Test",
            path: root.path,
            maxDepth: 2,
            category: .suggested,
            selectedByDefault: true,
            detail: nil
        )
        let report = await ProjectDiscovery.discoverStreaming(
            scopes: [scope],
            limit: 50,
            evidenceIndex: .empty
        ) { _ in }

        XCTAssertTrue(report.permissionDeniedPaths.contains(PathTools.normalize(locked.path)))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckDiscoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDirectory(_ name: String, in directory: URL) throws -> URL {
        let child = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        return child
    }

    private func createFile(_ name: String, in directory: URL) throws {
        try "test".write(
            to: directory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
