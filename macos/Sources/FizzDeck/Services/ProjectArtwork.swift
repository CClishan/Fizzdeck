import Foundation
import ImageIO

enum ProjectArtwork {
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
