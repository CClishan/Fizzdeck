import Foundation
import XCTest
@testable import FizzDeck

final class RuntimeVersionCheckerTests: ChineseInterfaceTestCase {
    private func makeTempDirectory(name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-runtime-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ value: String, to name: String, in directory: URL) throws {
        try value.write(
            to: directory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    func testCommonRequirementFormatsMatchExpectedVersions() {
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("v20", version: "20.11.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("20.11.0", version: "20.11.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("20.11.0", version: "20.11.1"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches(">=20", version: "22.3.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches(">=20", version: "18.19.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("^20", version: "20.99.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("^20", version: "21.0.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("~20.11", version: "20.11.8"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("~20.11", version: "20.12.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("20.x", version: "20.4.1"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("20.x", version: "21.0.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("3.11", version: "3.11.9"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("3.11", version: "3.12.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches(">=18 <21", version: "20.1.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches(">=18 <21", version: "21.0.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("18 - 20", version: "20.99.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("18 - 20", version: "21.0.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("20.0 - 20.11", version: "20.11.9"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("20.0 - 20.11", version: "20.12.0"))
        XCTAssertTrue(RuntimeVersionChecker.requirementMatches("20.0.0 - 20.11.0", version: "20.11.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("20.0.0 - 20.11.0", version: "20.11.1"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("20.0.0 - 20.11.0", version: "20.15.0"))
        XCTAssertFalse(RuntimeVersionChecker.requirementMatches("not-a-version", version: "20.0.0"))
    }

    func testReadsVersionFilesPackageEnginesAndChecksInstalledRuntimes() async throws {
        let dir = try makeTempDirectory(name: "files")
        defer { try? FileManager.default.removeItem(at: dir) }

        try write("v20\n", to: ".nvmrc", in: dir)
        try write("3.11\n", to: ".python-version", in: dir)
        try write(
            #"{"engines":{"node":">=22"}}"#,
            to: "package.json",
            in: dir
        )

        let specs = RuntimeVersionChecker.requirements(in: dir)
        XCTAssertEqual(specs.map(\.runtime), [.node, .python])
        XCTAssertEqual(specs.first?.source, ".nvmrc")
        XCTAssertEqual(specs.last?.rawRequirement, "3.11")

        let mismatches = RuntimeVersionChecker.check(
            specs: specs,
            environment: RuntimeVersionEnvironment(node: "v22.4.1", python: "Python 3.12.2")
        )
        XCTAssertEqual(mismatches.count, 2)
        XCTAssertTrue(mismatches[0].title.contains("Node v20"))
        XCTAssertTrue(mismatches[0].title.contains("本机当前是 Node 22.4"))
        XCTAssertTrue(mismatches[1].title.contains("Python 3.11"))
        XCTAssertTrue(mismatches[1].fixCommand.contains("pyenv install 3.11"))

        let matching = RuntimeVersionChecker.check(
            specs: specs,
            environment: RuntimeVersionEnvironment(node: "v20.11.1", python: "3.11.8")
        )
        XCTAssertTrue(matching.isEmpty)
    }

    func testNodeVersionFileAndPackageEngineFallback() throws {
        let dir = try makeTempDirectory(name: "fallback")
        defer { try? FileManager.default.removeItem(at: dir) }

        try write("banana\n", to: ".nvmrc", in: dir)
        try write("20.11.0\n", to: ".node-version", in: dir)
        let spec = RuntimeVersionChecker.requirements(in: dir).first
        XCTAssertEqual(spec?.source, ".node-version")
        XCTAssertEqual(spec?.fixCommand, "fnm use")

        try FileManager.default.removeItem(at: dir.appendingPathComponent(".node-version"))
        try write(#"{"engines":{"node":"^20"}}"#, to: "package.json", in: dir)
        let engineSpec = RuntimeVersionChecker.requirements(in: dir).first
        XCTAssertEqual(engineSpec?.source, "package.json engines.node")
        XCTAssertEqual(engineSpec?.fixCommand, "nvm install 20 && nvm use 20")
    }

    func testMissingFilesAndInvalidFormatsAreIgnored() throws {
        let dir = try makeTempDirectory(name: "invalid")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(RuntimeVersionChecker.requirements(in: dir).isEmpty)

        try write("lts/*", to: ".nvmrc", in: dir)
        try write("not-a-version", to: ".python-version", in: dir)
        try write("{broken-json", to: "package.json", in: dir)
        XCTAssertTrue(RuntimeVersionChecker.requirements(in: dir).isEmpty)
    }

    func testFourAdditionalRuntimesUsePinsOrMinimumsWithoutEvaluatingManifests() async throws {
        let dir = try makeTempDirectory(name: "polyglot")
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("module example.dev/x\n\ngo 1.23.4\n", to: "go.mod", in: dir)
        try write("[package]\nrust-version = \"1.78\"\n", to: "Cargo.toml", in: dir)
        try write("ruby-3.3.2\n", to: ".ruby-version", in: dir)
        try write("// swift-tools-version: 6.0\nimport PackageDescription", to: "Package.swift", in: dir)
        var specs = RuntimeVersionChecker.requirements(in: dir)
        XCTAssertEqual(specs.map(\.rawRequirement), [">=1.23.4", ">=1.78", "3.3.2", ">=6.0"])
        let old = RuntimeVersionEnvironment(go: "go version go1.22.0 arm64", rust: "rustc 1.77.1", ruby: "ruby 3.4.0", swift: nil)
        let mismatches = await RuntimeVersionChecker.inspectProject(in: dir, environment: old)
        XCTAssertEqual(mismatches.map(\.runtime), [.go, .rust, .ruby, .swift]); XCTAssertNil(mismatches.last?.currentText)
        XCTAssertTrue(RuntimeVersionChecker.check(specs: specs, environment: .init(go: "1.24.1", rust: "1.81.0", ruby: "3.3.2", swift: "6.0.1")).isEmpty)
        try write("[toolchain]\nchannel = \"1.85.0\"", to: "rust-toolchain.toml", in: dir)
        try write("5.10\n", to: ".swift-version", in: dir)
        specs = RuntimeVersionChecker.requirements(in: dir)
        XCTAssertEqual(specs.first { $0.runtime == .rust }?.rawRequirement, "1.85.0")
        XCTAssertEqual(specs.first { $0.runtime == .swift }?.rawRequirement, "5.10")
        try write("3.3; unknown text", to: ".ruby-version", in: dir)
        try write("ruby File.read('version')", to: "Gemfile", in: dir)
        XCTAssertFalse(RuntimeVersionChecker.requirements(in: dir).contains { $0.runtime == .ruby })
    }
}
