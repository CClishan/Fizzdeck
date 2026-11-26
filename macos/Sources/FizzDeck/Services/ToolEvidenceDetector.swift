import Foundation
import SwiftUI

enum DetectedTool: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case codex
    case claude
    case grok
    case cursor
    case trae
    case windsurf
    case gemini
    case deepseek
    case agy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .trae: "Trae"
        case .windsurf: "Windsurf"
        case .gemini: "Gemini CLI"
        case .deepseek: "DeepSeek Harness"
        case .agy: "Antigravity (AGY)"
        }
    }

    var shortTitle: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .agy: "AGY"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .codex: "terminal"
        case .claude: "sparkles"
        case .grok: "bolt.horizontal"
        case .cursor: "cursorarrow.rays"
        case .trae: "wand.and.stars"
        case .windsurf: "wind"
        case .gemini: "diamond"
        case .deepseek: "cpu"
        case .agy: "sparkles.rectangle.stack"
        }
    }

    var tint: Color {
        switch self {
        case .codex: .blue
        case .claude: .purple
        case .grok: .orange
        case .cursor: .teal
        case .trae: .green
        case .windsurf: .cyan
        case .gemini: .indigo
        case .deepseek: .mint
        case .agy: .pink
        }
    }

    var supportsResume: Bool {
        switch self {
        case .codex, .claude, .grok, .gemini: true
        case .cursor, .trae, .windsurf, .deepseek, .agy: false
        }
    }
}

struct ToolEvidenceIndex: Sendable {
    var toolCwds: [DetectedTool: Set<String>]

    static let empty = ToolEvidenceIndex(toolCwds: [:])

    static func build(
        homeDirectory: URL = AppPaths.home,
        sessionCwdMap: [String: Set<String>]? = nil
    ) -> ToolEvidenceIndex {
        var map: [DetectedTool: Set<String>] = [:]

        let resolvedSessions = sessionCwdMap ?? SessionIndex.buildLightweightCwdMap(homeDirectory: homeDirectory)
        for (name, tool) in [
            ("codex", DetectedTool.codex),
            ("claude", .claude),
            ("grok", .grok),
            ("gemini", .gemini),
            ("deepseek", .deepseek),
            ("agy", .agy),
        ] {
            if let cwds = resolvedSessions[name] {
                map[tool, default: []].formUnion(cwds)
            }
        }

        let appSupport = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let editorMappings: [(DetectedTool, String)] = [
            (.cursor, "Cursor/User/workspaceStorage"),
            (.trae, "Trae/User/workspaceStorage"),
            (.windsurf, "Windsurf/User/workspaceStorage"),
        ]
        for (tool, relativePath) in editorMappings {
            let cwds = collectVSCodeWorkspaceCwds(in: appSupport.appendingPathComponent(relativePath, isDirectory: true))
            if !cwds.isEmpty {
                map[tool, default: []].formUnion(cwds)
            }
        }

        return ToolEvidenceIndex(toolCwds: map)
    }

    private static func collectVSCodeWorkspaceCwds(in storageRoot: URL) -> Set<String> {
        guard FileTools.isDirectory(storageRoot) else { return [] }
        var result = Set<String>()
        for workspaceDir in FileTools.childDirectories(of: storageRoot).prefix(300) {
            let workspaceFile = workspaceDir.appendingPathComponent("workspace.json")
            guard let json = FileTools.json(workspaceFile),
                  let folderString = json["folder"] as? String,
                  let url = URL(string: folderString),
                  url.isFileURL
            else { continue }
            result.insert(PathTools.canonical(url.path))
        }
        return result
    }
}

enum ToolEvidenceDetector {
    static func detect(
        directory: URL,
        entryNames: Set<String>? = nil,
        index: ToolEvidenceIndex = .empty
    ) -> [DetectedTool] {
        let names = entryNames ?? Set(FileTools.childEntries(of: directory).map(\.lastPathComponent))
        let lowercased = Set(names.map { $0.lowercased() })
        let normalized = PathTools.normalize(directory.path)
        let canonical = PathTools.canonical(directory.path)

        var found: [DetectedTool] = []
        func add(_ tool: DetectedTool) {
            if !found.contains(tool) { found.append(tool) }
        }
        func has(_ name: String) -> Bool {
            names.contains(name) || lowercased.contains(name.lowercased())
        }

        for tool in DetectedTool.allCases {
            if let cwds = index.toolCwds[tool],
               cwds.contains(canonical) || cwds.contains(normalized) {
                add(tool)
            }
        }

        if has("AGENTS.md") || has(".codex") { add(.codex) }
        if has("CLAUDE.md") || has(".claude") { add(.claude) }
        if has(".grok") || has("GROK.md") { add(.grok) }
        if has(".cursor") || has(".cursorrules") || has(".cursorignore") { add(.cursor) }
        if has(".trae") { add(.trae) }
        if has(".windsurf") || has(".windsurfrules") { add(.windsurf) }
        if has(".gemini") || has("GEMINI.md") { add(.gemini) }
        if has(".dsh") { add(.deepseek) }
        if has(".antigravity") { add(.agy) }

        return DetectedTool.allCases.filter { found.contains($0) }
    }
}
