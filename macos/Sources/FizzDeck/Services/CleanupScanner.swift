import Foundation

private struct CleanupRule {
    let pattern: String
    let reason: String
    let regen: String
    let kind: String
}

enum CleanupScanner {
    private static let rules = [
        CleanupRule(pattern: #"^node_modules$"#, reason: "依赖，可重装", regen: "npm ci", kind: "deps"),
        CleanupRule(pattern: #"^(\.next|\.open-next|\.svelte-kit|\.astro|\.tanstack|\.output)$"#, reason: "框架缓存，可重建", regen: "构建时自动生成", kind: "build"),
        CleanupRule(pattern: #"^(dist|dist-[a-z]+|build)$"#, reason: "构建产物，可重建", regen: "npm run build", kind: "build"),
        CleanupRule(pattern: #"^(tmp|\.tmp)$"#, reason: "临时产物", regen: "", kind: "tmp"),
        CleanupRule(pattern: #"^(output|artifacts|releases|reports)$"#, reason: "历史归档，确认后再删", regen: "", kind: "archive"),
    ]

    static func scan(
        _ root: URL,
        precomputedDirectoryBytes: [String: Int64]? = nil
    ) async -> CleanupInfo {
        var items: [CleanupItem] = []
        for directory in FileTools.childDirectories(of: root) {
            let name = directory.lastPathComponent
            guard let rule = rules.first(where: { name.range(of: $0.pattern, options: .regularExpression) != nil }) else {
                continue
            }
            let bytes: Int64
            if let precomputed = precomputedDirectoryBytes?[name] {
                bytes = precomputed
            } else {
                bytes = await SizeScanner.directoryBytes(directory)
            }
            guard bytes > 0 else { continue }
            items.append(CleanupItem(
                label: name,
                path: directory.path,
                bytes: bytes,
                reason: rule.reason,
                regen: rule.regen,
                kind: rule.kind
            ))
        }
        items.sort { $0.bytes > $1.bytes }
        return CleanupInfo(reusableBytes: items.reduce(0) { $0 + $1.bytes }, items: items)
    }
}
