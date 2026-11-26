import Foundation
import XCTest
@testable import FizzDeck

final class ProjectScriptTests: XCTestCase {
    func testDetectsPackageMakeAndJustScripts() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try """
        {
          "scripts": {
            "dev": "vite",
            "build": "vite build",
            "lint": "eslint ."
          }
        }
        """.write(
            to: directory.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        .PHONY: build test
        VERSION := 1.0

        build:
        	echo build

        test: build
        	echo test
        """.write(
            to: directory.appendingPathComponent("Makefile"),
            atomically: true,
            encoding: .utf8
        )
        try """
        set shell := ["bash", "-c"]

        check:
        	echo check
        """
        .write(
            to: directory.appendingPathComponent("justfile"),
            atomically: true,
            encoding: .utf8
        )

        let scripts = RunDetector.scripts(directory)
        let ids = Set(scripts.map(\.id))

        XCTAssertTrue(ids.contains("npm:build"))
        XCTAssertTrue(ids.contains("npm:lint"))
        XCTAssertFalse(ids.contains("npm:dev"))
        XCTAssertTrue(ids.contains("make:build"))
        XCTAssertTrue(ids.contains("make:test"))
        XCTAssertFalse(ids.contains("make:VERSION"))
        XCTAssertTrue(ids.contains("just:check"))
        XCTAssertFalse(ids.contains("just:set"))
        XCTAssertEqual(
            scripts.first(where: { $0.id == "npm:build" })?.command,
            "npm run 'build'"
        )
        XCTAssertEqual(
            scripts.first(where: { $0.id == "make:test" })?.command,
            "make 'test'"
        )
    }

    func testMakeAndJustParsersIgnoreVariablesAndInternalTargets() {
        let make = """
        NAME := value
        _private:
        	echo private
        public: _private
        	echo public
        """
        XCTAssertEqual(RunDetector.makeTargets(in: make), ["public"])

        let just = """
        set dotenv-load
        _helper:
        	echo helper
        check:
        	echo check
        """
        XCTAssertEqual(RunDetector.justRecipes(in: just), ["check"])
    }

    func testPreferencesRoundTripDeduplicatesAndSanitizesPaths() throws {
        let directory = temporaryDirectory()
        let file = directory.appendingPathComponent("script-preferences.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let project = directory.appendingPathComponent("project/").path
        let saved = ProjectScriptPreferences.setPinned(
            ["npm:build", "npm:lint", "npm:build", "  "],
            for: project,
            file: file
        )
        XCTAssertEqual(saved.pinnedIDs(for: project), ["npm:build", "npm:lint"])
        XCTAssertEqual(ProjectScriptPreferences.load(file: file).pinnedIDs(for: project), ["npm:build", "npm:lint"])

        let cleared = ProjectScriptPreferences.setPinned([], for: project, file: file)
        XCTAssertTrue(cleared.pinnedIDs(for: project).isEmpty)
    }

    func testPreferencesKeepAllUniquePinnedScripts() {
        let ids = (0..<20).map { "npm:script-\($0)" }
        let directory = temporaryDirectory()
        let file = directory.appendingPathComponent("script-preferences.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let saved = ProjectScriptPreferences.setPinned(ids, for: "/tmp/project", file: file)

        XCTAssertEqual(saved.pinnedIDs(for: "/tmp/project").count, 20)
    }

    func testMissingOrMalformedPreferencesFallBackToEmpty() throws {
        let directory = temporaryDirectory()
        let file = directory.appendingPathComponent("script-preferences.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(ProjectScriptPreferences.load(file: file).pinned.isEmpty)

        try "{not-json".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(ProjectScriptPreferences.load(file: file).pinned.isEmpty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{not-json")
    }

    func testPreferenceWriteDoesNotTouchLegacyStateJSON() throws {
        let directory = temporaryDirectory()
        let stateFile = directory.appendingPathComponent("state.json")
        let preferenceFile = directory.appendingPathComponent("script-preferences.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacy = #"{"projects":{"/tmp/legacy":{"starred":true,"note":"old"}}}"#
        try legacy.write(to: stateFile, atomically: true, encoding: .utf8)

        _ = ProjectScriptPreferences.setPinned(
            ["npm:build"],
            for: "/tmp/legacy",
            file: preferenceFile
        )

        XCTAssertEqual(try String(contentsOf: stateFile, encoding: .utf8), legacy)
        XCTAssertEqual(
            ProjectScriptPreferences.load(file: preferenceFile).pinnedIDs(for: "/tmp/legacy"),
            ["npm:build"]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckScriptTests-\(UUID().uuidString)")
    }
}
