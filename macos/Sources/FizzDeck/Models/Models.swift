import Foundation

enum MetricLoadState: String, Codable, Sendable, Hashable {
    case pending
    case loading
    case ready
}

struct RepoProject: Identifiable, Codable, Sendable {
    let path: String
    let name: String
    let displayName: String
    var group: String
    var kind: ProjectKind = .other
    var detectedTools: [DetectedTool] = []
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
    var customArtwork: String? = nil
    var test: TestCommand?
    var starred: Bool
    var color: TagColor?
    var note: String
    var port: PortState
    var gitLoadState: MetricLoadState = .ready
    var sizeLoadState: MetricLoadState = .ready
    var sessionLoadState: MetricLoadState = .ready

    var id: String { path }

    init(
        path: String,
        name: String,
        displayName: String,
        group: String,
        kind: ProjectKind = .other,
        detectedTools: [DetectedTool] = [],
        recent: Date?,
        branch: String?,
        lastCommit: Commit?,
        dirtyCount: Int,
        changes: ChangeStats,
        ahead: Int,
        behind: Int,
        weekly: [String: Int],
        stacks: [StackGroup],
        size: SizeInfo,
        cleanup: CleanupInfo,
        run: RunConfig?,
        sessions: SessionSummary,
        intro: ProjectIntro,
        artwork: String?,
        customArtwork: String? = nil,
        test: TestCommand?,
        starred: Bool,
        color: TagColor?,
        note: String,
        port: PortState,
        gitLoadState: MetricLoadState = .ready,
        sizeLoadState: MetricLoadState = .ready,
        sessionLoadState: MetricLoadState = .ready
    ) {
        self.path = path
        self.name = name
        self.displayName = displayName
        self.group = group
        self.kind = kind
        self.detectedTools = detectedTools
        self.recent = recent
        self.branch = branch
        self.lastCommit = lastCommit
        self.dirtyCount = dirtyCount
        self.changes = changes
        self.ahead = ahead
        self.behind = behind
        self.weekly = weekly
        self.stacks = stacks
        self.size = size
        self.cleanup = cleanup
        self.run = run
        self.sessions = sessions
        self.intro = intro
        self.artwork = artwork
        self.customArtwork = customArtwork
        self.test = test
        self.starred = starred
        self.color = color
        self.note = note
        self.port = port
        self.gitLoadState = gitLoadState
        self.sizeLoadState = sizeLoadState
        self.sessionLoadState = sessionLoadState
    }

    var allTools: [String] {
        var result: [String] = []
        for tool in sessions.detected where !result.contains(tool) {
            result.append(tool)
        }
        for tool in detectedTools.map(\.rawValue) where !result.contains(tool) {
            result.append(tool)
        }
        return result
    }
}

struct Commit: Identifiable, Codable, Sendable, Hashable {
    let hash: String
    let date: Date?
    let subject: String
    let author: String

    var id: String { hash }
}

struct ChangeStats: Codable, Sendable, Hashable {
    var tracked: Int
    var untracked: Int
    var total: Int

    static let zero = ChangeStats(tracked: 0, untracked: 0, total: 0)
}

struct StackGroup: Identifiable, Codable, Sendable, Hashable {
    let key: String
    let label: String
    let items: [String]

    var id: String { key }
}

struct SizeRow: Identifiable, Codable, Sendable, Hashable {
    let label: String
    let bytes: Int64
    let isDirectory: Bool

    var id: String { label }
}

struct SizeInfo: Codable, Sendable, Hashable {
    var totalBytes: Int64
    var breakdown: [SizeRow]

    static let empty = SizeInfo(totalBytes: 0, breakdown: [])
}

struct CleanupItem: Identifiable, Codable, Sendable, Hashable {
    let label: String
    let path: String
    let bytes: Int64
    let reason: String
    let regen: String
    let kind: String

    var id: String { path }
}

struct CleanupInfo: Codable, Sendable, Hashable {
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

struct RunConfig: Codable, Sendable, Hashable {
    let command: String
    let port: Int
    let previewURL: String?
}

struct TestCommand: Codable, Sendable, Hashable {
    let label: String
    let command: String
}

struct ProjectIntro: Codable, Sendable, Hashable {
    let text: String
    let source: String?

    static let empty = ProjectIntro(text: "", source: nil)
}

struct TokenUsage: Codable, Sendable, Hashable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var cacheWriteInputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningOutputTokens: Int = 0
    var totalTokens: Int = 0

    static let zero = TokenUsage()

    var isEmpty: Bool { totalTokens <= 0 }
}

struct ToolSession: Identifiable, Codable, Sendable, Hashable {
    let tool: String
    let sessionCount: Int
    let lastSessionAt: Date?
    let lastSessionID: String?
    let lastUserMessage: String?

    var id: String { tool }
}

struct SessionSummary: Codable, Sendable, Hashable {
    var detected: [String]
    var lastSessionAt: Date?
    var lastUserMessage: String?
    var lastSessionID: String?
    var lastTool: String?
    var sessionCount: Int
    var byTool: [ToolSession]
    var recentSessions: [SessionRecord]

    var totalTokens: Int {
        recentSessions.compactMap { $0.usage?.totalTokens }.reduce(0, +)
    }

    var totalCostUSD: Double? {
        let costs = recentSessions.compactMap(\.costUSD)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    var costIsEstimate: Bool {
        recentSessions.contains { $0.costUSD != nil && $0.costIsEstimate == true }
    }

    var modelNames: [String] {
        var seen = Set<String>()
        return recentSessions.compactMap(\.model).filter { seen.insert($0).inserted }
    }

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

enum PortState: String, Codable, Sendable {
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
    var customArtwork: String? = nil
    var attention: [String: AttentionPreference] = [:]
    var doctorExemptions: Set<DoctorIssueKind> = []
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

enum ProjectTab: String, CaseIterable, Identifiable, Sendable {
    case progress
    case run
    case version
    case info

    var id: String { rawValue }

    var title: String { title(for: .plain) }

    func title(for mode: CopyMode) -> String {
        switch self {
        case .progress: FizzCopy.tabTitle(.progress, mode: mode)
        case .run: FizzCopy.tabTitle(.run, mode: mode)
        case .version: FizzCopy.tabTitle(.version, mode: mode)
        case .info: FizzCopy.tabTitle(.info, mode: mode)
        }
    }

    var symbol: String {
        switch self {
        case .progress: "clock.arrow.circlepath"
        case .run: "play.circle"
        case .version: "arrow.triangle.branch"
        case .info: "info.circle"
        }
    }

    static func fromRoutingValue(_ raw: String) -> ProjectTab? {
        switch raw {
        case "progress", "overview", "sessions", "cleanup": .progress
        case "run", "tests": .run
        case "version", "git": .version
        case "info", "docs": .info
        default: nil
        }
    }
}
