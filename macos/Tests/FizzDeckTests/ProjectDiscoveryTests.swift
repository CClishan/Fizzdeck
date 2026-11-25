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
