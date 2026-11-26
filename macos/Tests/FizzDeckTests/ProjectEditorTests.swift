import XCTest
@testable import FizzDeck

final class ProjectEditorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testFindsNestedWorkspace() throws {
        let nested = root.appendingPathComponent("apps/ios", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested.appendingPathComponent("App.xcworkspace", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            ProjectEditor.xcodeTarget(in: root)?.lastPathComponent,
            "App.xcworkspace"
        )
    }

    func testTopLevelProjectWinsOverNestedWorkspace() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("App.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("apps/ios/Nested.xcworkspace", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            ProjectEditor.xcodeTarget(in: root)?.lastPathComponent,
            "App.xcodeproj"
        )
    }

    func testSkipsGeneratedDirectories() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("node_modules/ignored/Ignored.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertNil(ProjectEditor.xcodeTarget(in: root))
    }

    func testTopLevelPackageIsFallback() throws {
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: root.appendingPathComponent("Package.swift").path,
                contents: Data()
            )
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("apps/ios/Nested.xcworkspace", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            ProjectEditor.xcodeTarget(in: root)?.lastPathComponent,
            "Package.swift"
        )
    }

    func testNestedPackageIsFallback() throws {
        let nested = root.appendingPathComponent("macos", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: nested.appendingPathComponent("Package.swift").path,
                contents: Data()
            )
        )

        XCTAssertEqual(
            ProjectEditor.xcodeTarget(in: root)?.lastPathComponent,
            "Package.swift"
        )
    }

    func testNestedWorkspaceWinsOverNestedPackage() throws {
        let packageDirectory = root.appendingPathComponent("macos", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: packageDirectory.appendingPathComponent("Package.swift").path,
                contents: Data()
            )
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("apps/ios/App.xcworkspace", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            ProjectEditor.xcodeTarget(in: root)?.lastPathComponent,
            "App.xcworkspace"
        )
    }

    func testIDEEditorsHaveDetectionMetadata() {
        for editor in [ProjectEditor.cursor, .trae, .windsurf] {
            XCTAssertFalse(editor.bundleIdentifiers.isEmpty, editor.rawValue)
        }
        XCTAssertEqual(ProjectEditor.trae.fallbackApplicationPaths, ["/Applications/Trae.app"])
        XCTAssertEqual(ProjectEditor.windsurf.fallbackApplicationPaths, ["/Applications/Windsurf.app"])
    }

    func testIDEEditorsTargetProjectDirectory() {
        for editor in [ProjectEditor.cursor, .trae, .windsurf] {
            XCTAssertEqual(editor.target(for: root.path)?.path, root.path)
        }
    }
}
