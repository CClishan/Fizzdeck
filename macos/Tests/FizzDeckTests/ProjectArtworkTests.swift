import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FizzDeck

final class ProjectArtworkTests: XCTestCase {
    func testSaveResolveReplaceAndRemoveCustomArtwork() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-artwork-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repoDir = root.appendingPathComponent("repo", isDirectory: true)
        let coversDir = root.appendingPathComponent("covers", isDirectory: true)
        let externalFile = root.appendingPathComponent("outside.png")
        let img1 = root.appendingPathComponent("sample1.png")
        let img2 = root.appendingPathComponent("sample2.png")
        let badFile = root.appendingPathComponent("not-an-image.png")

        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try writeSamplePNG(to: img1)
        try writeSamplePNG(to: img2)
        try writeSamplePNG(to: externalFile)
        try Data("not an image".utf8).write(to: badFile)

        XCTAssertThrowsError(
            try ProjectArtwork.saveCustomArtwork(
                from: badFile,
                for: repoDir.path,
                coversDir: coversDir
            )
        )

        let firstSaved = try ProjectArtwork.saveCustomArtwork(
            from: img1,
            for: repoDir.path,
            coversDir: coversDir
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSaved))
        XCTAssertEqual(
            ProjectArtwork.resolvedPath(in: repoDir, customArtwork: firstSaved),
            firstSaved
        )

        Thread.sleep(forTimeInterval: 0.01)
        let secondSaved = try ProjectArtwork.saveCustomArtwork(
            from: img2,
            for: repoDir.path,
            existingCustomPath: firstSaved,
            coversDir: coversDir
        )
        XCTAssertNotEqual(firstSaved, secondSaved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstSaved))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSaved))

        // Removing an external file outside coversDir must be refused
        ProjectArtwork.removeCustomArtwork(at: externalFile.path, coversDir: coversDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalFile.path))

        ProjectArtwork.removeCustomArtwork(at: secondSaved, coversDir: coversDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondSaved))
        XCTAssertNil(ProjectArtwork.resolvedPath(in: repoDir, customArtwork: secondSaved))
    }

    private func writeSamplePNG(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 32,
            height: 18,
            bitsPerComponent: 8,
            bytesPerRow: 32 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
            let cgImage = ctx.makeImage(),
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            XCTFail("Failed to allocate PNG fixture")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
