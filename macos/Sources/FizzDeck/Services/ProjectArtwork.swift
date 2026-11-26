import CryptoKit
import Foundation
import ImageIO

enum ProjectArtwork {
    enum ArtworkError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            "所选文件不是有效的图片格式。"
        }
    }

    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "gif", "tiff", "bmp"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]
    private static let excludedWords = ["logo", "icon", "favicon", "avatar", "badge", "sprite", "placeholder", "wordmark"]
    private static let skippedDirectories: Set<String> = [
        "node_modules", ".git", ".build", "build", "dist", "dist-production", "dist-staging",
        ".next", ".cache", ".playwright-cli", ".acanvas", "coverage", "output", "vendor",
    ]
    private static let roots: [(path: String, depth: Int)] = [
        ("", 1),
        (".github", 2),
        ("public", 3),
        ("static", 3),
        ("assets", 2),
        ("src/assets", 2),
        ("docs", 3),
    ]

    static func find(in directory: URL) -> String? {
        var candidates: [(url: URL, relativePath: String, score: Int)] = []

        for root in roots {
            let url = root.path.isEmpty ? directory : directory.appendingPathComponent(root.path)
            guard FileTools.isDirectory(url) else { continue }
            collect(
                url,
                relativePath: root.path,
                depth: 0,
                maxDepth: root.depth,
                into: &candidates
            )
        }

        let ranked = candidates
            .sorted { $0.score > $1.score }
            .prefix(16)

        for candidate in ranked where isUsable(candidate.url) {
            return candidate.url.path
        }
        return nil
    }

    static func resolvedPath(in directory: URL, customArtwork: String?) -> String? {
        if let customArtwork,
           !customArtwork.isEmpty,
           FileTools.exists(URL(fileURLWithPath: customArtwork)) {
            return customArtwork
        }
        return find(in: directory)
    }

    @discardableResult
    static func saveCustomArtwork(
        from sourceURL: URL,
        for projectPath: String,
        existingCustomPath: String? = nil,
        coversDir: URL = AppPaths.coversDir
    ) throws -> String {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else {
            throw ArtworkError.invalidImage
        }

        let data = try Data(contentsOf: sourceURL)
        try FileTools.manager.createDirectory(at: coversDir, withIntermediateDirectories: true)

        let digest = SHA256.hash(data: Data(PathTools.normalize(projectPath).utf8))
        let prefix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        let ext = sourceURL.pathExtension.lowercased()
        let fileExt = supportedExtensions.contains(ext) ? ext : "png"
        let destURL = coversDir.appendingPathComponent("\(prefix)-\(stamp).\(fileExt)")

        try data.write(to: destURL, options: .atomic)

        if let existingCustomPath, existingCustomPath != destURL.path {
            removeCustomArtwork(at: existingCustomPath, coversDir: coversDir)
        }
        return destURL.path
    }

    static func removeCustomArtwork(at path: String?, coversDir: URL = AppPaths.coversDir) {
        guard let path, !path.isEmpty else { return }
        let canonicalFile = PathTools.canonical(path)
        let canonicalCovers = PathTools.canonical(coversDir.path) + "/"
        guard canonicalFile.hasPrefix(canonicalCovers) else { return }
        try? FileTools.manager.removeItem(atPath: path)
    }

    private static func collect(
        _ directory: URL,
        relativePath: String,
        depth: Int,
        maxDepth: Int,
        into candidates: inout [(url: URL, relativePath: String, score: Int)]
    ) {
        guard depth < maxDepth else { return }

        for entry in FileTools.childEntries(of: directory) {
            let name = entry.lastPathComponent
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if values?.isDirectory == true {
                guard !name.hasPrefix("."), !skippedDirectories.contains(name) else { continue }
                collect(
                    entry,
                    relativePath: "\(relativePath)/\(name)",
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    into: &candidates
                )
                continue
            }

            guard values?.isRegularFile == true,
                  imageExtensions.contains(entry.pathExtension.lowercased()),
                  !name.hasPrefix("."),
                  !excludedWords.contains(where: { name.lowercased().contains($0) })
            else { continue }

            let path = "\(relativePath)/\(name)"
            let score = score(name: name, relativePath: path)
            guard score > 0 else { continue }
            candidates.append((entry, path, score))
        }
    }

    private static func score(name: String, relativePath: String) -> Int {
        let value = name.lowercased()
        var score = 0

        if value.contains("og-image") || value.contains("opengraph") || value == "og.png" || value == "og.jpg" {
            score += 90
        }
        if value.contains("cover") { score += 60 }
        if value.contains("home") { score += 45 }
        if value.contains("hero") { score += 40 }
        if value.contains("social") { score += 25 }
        if value.contains("showcase") { score += 18 }
        if value.contains("screenshot") { score += 15 }
        if value.contains("preview") { score += 10 }
        if value.contains("banner") { score += 8 }
        if relativePath.hasPrefix("public/") { score += 6 }
        if value.contains("-480") || value.contains("-960") { score -= 8 }
        return score
    }

    private static func isUsable(_ url: URL) -> Bool {
        guard FileTools.fileSize(url) >= 20_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width >= 640,
              height >= 300,
              width / height >= 1.2
        else { return false }
        return true
    }
}
