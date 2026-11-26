import XCTest
@testable import FizzDeck

final class SizeScannerTests: XCTestCase {
    func testCleanupScannerReusesPrecomputedDirectoryBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckCleanupReuse-\(UUID().uuidString)")
        let nodeModules = root.appendingPathComponent("node_modules", isDirectory: true)
        let dist = root.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cleanup = await CleanupScanner.scan(
            root,
            precomputedDirectoryBytes: [
                "node_modules": 12_345,
                "dist": 6_789,
            ]
        )

        XCTAssertEqual(cleanup.reusableBytes, 19_134)
        XCTAssertEqual(cleanup.items.map(\.label), ["node_modules", "dist"])
    }
}
