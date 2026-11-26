import XCTest
@testable import FizzDeck

final class ProjectBadgeIconTests: XCTestCase {
    private func resolve(_ items: String..., kind: ProjectKind = .web) -> ProjectBadgeKind {
        ProjectBadgeKind.resolve(
            stacks: [StackGroup(key: "test", label: "测试", items: items)],
            kind: kind
        )
    }

    func testFrameworksWinOverBuildTools() {
        XCTAssertEqual(resolve("Next.js", "React", "Vite"), .next)
        XCTAssertEqual(resolve("Nuxt", "Vue", "Vite"), .nuxt)
        XCTAssertEqual(resolve("SvelteKit", "Svelte", "Vite"), .svelte)
        XCTAssertEqual(resolve("Astro", "Vite"), .astro)
        XCTAssertEqual(resolve("Vue", "Vite"), .vue)
        XCTAssertEqual(resolve("React", "Vite"), .react)
    }

    func testViteStandalone() {
        XCTAssertEqual(resolve("Vite"), .vite)
    }

    func testSwiftUIStackAndMacAppFallback() {
        XCTAssertEqual(resolve("SwiftUI", kind: .other), .swift)
        XCTAssertEqual(resolve(kind: .macApp), .swift)
    }

    func testFlutterFromStackAndKind() {
        XCTAssertEqual(resolve("Flutter", kind: .other), .flutter)
        XCTAssertEqual(resolve(kind: .flutter), .flutter)
    }

    func testGameFromEngineStackAndKind() {
        XCTAssertEqual(resolve("Unity", kind: .other), .game)
        XCTAssertEqual(resolve("Godot", kind: .other), .game)
        XCTAssertEqual(resolve("Unreal", kind: .other), .game)
        XCTAssertEqual(resolve(kind: .game), .game)
    }

    func testLanguageStacks() {
        XCTAssertEqual(resolve("Go", "Go Module"), .go)
        XCTAssertEqual(resolve("Rust", "Cargo"), .rust)
        XCTAssertEqual(resolve("Python"), .python)
    }

    func testInfrastructureStacks() {
        XCTAssertEqual(resolve("Docker"), .docker)
        XCTAssertEqual(resolve("Cloudflare", "D1", "R2", "KV"), .cloudflare)
    }

    func testCLIAndKindFallbacks() {
        XCTAssertEqual(resolve(kind: .cli), .cli)
        XCTAssertEqual(resolve("TS", kind: .web), .web)
        XCTAssertEqual(resolve(kind: .miniProgram), .miniProgram)
        XCTAssertEqual(resolve(kind: .other), .other)
    }

    func testEveryKindHasGlyph() {
        for kind in ProjectBadgeKind.allCases {
            XCTAssertTrue(
                kind.badgeText != nil || kind.symbol != nil,
                "\(kind.rawValue) needs a text or symbol glyph"
            )
        }
    }
}
