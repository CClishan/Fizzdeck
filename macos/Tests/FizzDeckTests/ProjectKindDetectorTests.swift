import XCTest
@testable import FizzDeck

final class ProjectKindDetectorTests: XCTestCase {
    func testDetectsAllSevenProjectKindsDeterministically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckKindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Web
        let web = try makeSubdir("web", in: root)
        try write(#"{"dependencies":{"next":"15.0.0","react":"19.0.0"}}"#, to: web.appendingPathComponent("package.json"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: web), .web)

        // Flutter vs pure Dart
        let flutter = try makeSubdir("flutter-app", in: root)
        try write("name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n", to: flutter.appendingPathComponent("pubspec.yaml"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: flutter), .flutter)

        let pureDart = try makeSubdir("dart-lib", in: root)
        try write("name: demo_cli\ndependencies:\n  args: ^2.0.0\n", to: pureDart.appendingPathComponent("pubspec.yaml"))
        XCTAssertNotEqual(ProjectKindDetector.detect(directory: pureDart), .flutter)

        // Mini program
        let wechat = try makeSubdir("wx-mini", in: root)
        try write("{}", to: wechat.appendingPathComponent("project.config.json"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: wechat), .miniProgram)

        let uniapp = try makeSubdir("uni-mini", in: root)
        try write("{}", to: uniapp.appendingPathComponent("manifest.json"))
        try write("{}", to: uniapp.appendingPathComponent("pages.json"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: uniapp), .miniProgram)

        // Mac App vs Swift CLI
        let macApp = try makeSubdir("mac-app", in: root)
        try write("import PackageDescription\n// SwiftUI\n", to: macApp.appendingPathComponent("Package.swift"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: macApp), .macApp)

        let swiftCLI = try makeSubdir("swift-cli", in: root)
        try write("let p = Package(platforms: [.macOS(.v15)], targets: [.executableTarget(name: \"tool\")])", to: swiftCLI.appendingPathComponent("Package.swift"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: swiftCLI), .cli)

        // Games (Unity, Godot, Unreal)
        let unity = try makeSubdir("unity-game", in: root)
        let settings = try makeSubdir("ProjectSettings", in: unity)
        try write("m_EditorVersion: 2023.2.1f1", to: settings.appendingPathComponent("ProjectVersion.txt"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: unity), .game)

        let godot = try makeSubdir("godot-game", in: root)
        try write("config_version=5", to: godot.appendingPathComponent("project.godot"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: godot), .game)

        let unreal = try makeSubdir("unreal-game", in: root)
        try write("{}", to: unreal.appendingPathComponent("MyGame.uproject"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: unreal), .game)

        // CLI variants
        let nodeCLI = try makeSubdir("node-cli", in: root)
        try write(#"{"name":"my-cli","bin":{"my-cli":"./index.js"}}"#, to: nodeCLI.appendingPathComponent("package.json"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: nodeCLI), .cli)

        let shebangCLI = try makeSubdir("shell-cli", in: root)
        let binDir = try makeSubdir("bin", in: shebangCLI)
        try write("#!/usr/bin/env bash\necho hi\n", to: binDir.appendingPathComponent("run"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: shebangCLI), .cli)

        // Other
        let plain = try makeSubdir("plain", in: root)
        try write("hello", to: plain.appendingPathComponent("README.md"))
        XCTAssertEqual(ProjectKindDetector.detect(directory: plain), .other)
    }

    private func makeSubdir(_ name: String, in parent: URL) throws -> URL {
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
