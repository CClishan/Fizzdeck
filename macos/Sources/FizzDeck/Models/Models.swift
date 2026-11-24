import Foundation

struct RepoProject: Identifiable, Sendable {
    let path: String
    let name: String
    let displayName: String
    var group: String
    var recent: Date?
    var branch: String?
    var lastCommit: Commit?
    var dirtyCount: Int
    var changes: ChangeStats
    var ahead: Int
    var behind: Int
    var weekly: [String: Int]
    var stacks: [StackGroup]
    var size: SizeInfo
    var cleanup: CleanupInfo
    var run: RunConfig?
    var sessions: SessionSummary
    var intro: ProjectIntro
    var artwork: String?
    var test: TestCommand?
    var starred: Bool
    var color: TagColor?
    var note: String
    var port: PortState

    var id: String { path }
}

struct Commit: Identifiable, Sendable, Hashable {
    let hash: String
    let date: Date?
    let subject: String
    let author: String

    var id: String { hash }
}

struct ChangeStats: Sendable, Hashable {
    var tracked: Int
    var untracked: Int
    var total: Int

    static let zero = ChangeStats(tracked: 0, untracked: 0, total: 0)
}

struct StackGroup: Identifiable, Sendable, Hashable {
    let key: String
    let label: String
    let items: [String]

    var id: String { key }
}

struct SizeRow: Identifiable, Sendable, Hashable {
    let label: String
    let bytes: Int64
    let isDirectory: Bool

    var id: String { label }
}

struct SizeInfo: Sendable, Hashable {
    var totalBytes: Int64
    var breakdown: [SizeRow]

    static let empty = SizeInfo(totalBytes: 0, breakdown: [])
}

struct CleanupItem: Identifiable, Sendable, Hashable {
    let label: String
    let path: String
    let bytes: Int64
    let reason: String
    let regen: String
    let kind: String

    var id: String { path }
}

struct CleanupInfo: Sendable, Hashable {
    var reusableBytes: Int64
    var items: [CleanupItem]

    static let empty = CleanupInfo(reusableBytes: 0, items: [])

    var removalCommand: String {
        items.map(removalCommand(for:)).joined(separator: "\n")
    }

    func removalCommand(for item: CleanupItem) -> String {
        "rm -rf \(Self.shellQuote(item.path))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct RunConfig: Sendable, Hashable {
    let command: String
    let port: Int
    let previewURL: String?
}

struct TestCommand: Sendable, Hashable {
    let label: String
    let command: String
}

struct ProjectIntro: Sendable, Hashable {
    let text: String
    let source: String?

    static let empty = ProjectIntro(text: "", source: nil)
}

struct ToolSession: Identifiable, Sendable, Hashable {
    let tool: String
    let sessionCount: Int
    let lastSessionAt: Date?
    let lastSessionID: String?
    let lastUserMessage: String?

    var id: String { tool }
}

struct SessionSummary: Sendable, Hashable {
    var detected: [String]
    var lastSessionAt: Date?
    var lastUserMessage: String?
    var lastSessionID: String?
    var lastTool: String?
    var sessionCount: Int
    var byTool: [ToolSession]
    var recentSessions: [SessionRecord]

    static let empty = SessionSummary(
        detected: [],
        lastSessionAt: nil,
        lastUserMessage: nil,
        lastSessionID: nil,
        lastTool: nil,
        sessionCount: 0,
        byTool: [],
        recentSessions: []
    )
}

enum PortState: String, Sendable {
    case running
    case stopped
    case noPreview
}

enum TagColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case red
    case amber
    case green
    case blue
    case violet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: "红"
        case .amber: "琥珀"
        case .green: "绿"
        case .blue: "蓝"
        case .violet: "紫"
        }
    }
}

struct ProjectMeta: Codable, Sendable {
    var starred = false
    var color: TagColor?
    var group: String?
    var note = ""
    var attention: [String: AttentionPreference] = [:]
}

struct AttentionPreference: Codable, Hashable, Sendable {
    var muted = false
    var snoozedUntil: Date?
}

struct DocFile: Identifiable, Sendable, Hashable {
    let file: String
    let title: String
    let bytes: Int64
    let modified: Date?
    let lines: Int

    var id: String { file }
}

struct GitFileChange: Identifiable, Sendable, Hashable {
    let code: String
    let path: String
    let untracked: Bool

    var id: String { "\(code)-\(path)" }
}

struct BranchInfo: Identifiable, Sendable, Hashable {
    let name: String
    let date: String
    let upstream: String?

    var id: String { name }
}

struct GitDetail: Sendable {
    var branches: [BranchInfo]
    var files: [GitFileChange]
    var remote: String?
    var ahead: Int
    var behind: Int
    var stashCount: Int
    var lastTag: String?
    var changedCount: Int
}

struct ProjectDetail: Sendable {
    var git: GitDetail?
    var commits: [Commit]
    var docs: [DocFile]

    static let empty = ProjectDetail(git: nil, commits: [], docs: [])
}

struct GitSummary: Sendable {
    var branch: String
    var lastCommit: Commit?
    var changes: ChangeStats
    var ahead: Int
    var behind: Int
}

struct ScanOutput: Sendable {
    var projects: [RepoProject]
    var roots: [String]
    var scannedAt: Date
    var duration: TimeInterval
}

enum ProjectTab: String, CaseIterable, Identifiable {
    case overview
    case git
    case docs
    case sessions
    case tests
    case cleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .git: "改动"
        case .docs: "文档"
        case .sessions: "会话"
        case .tests: "测试"
        case .cleanup: "清理"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .git: "arrow.triangle.branch"
        case .docs: "doc.text"
        case .sessions: "bubble.left.and.bubble.right"
        case .tests: "checkmark.shield"
        case .cleanup: "trash.slash"
        }
    }
}
