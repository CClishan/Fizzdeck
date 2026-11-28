import Foundation

enum SessionMarkExpiryState: Equatable, Sendable {
    case stable
    case expiring(daysRemaining: Int)
    case expired
    case unavailable
}

struct ExpiringSessionMark: Equatable, Sendable {
    let mark: SessionMark
    let daysRemaining: Int
    let projectPath: String
}

struct SessionMarkAvailabilityCheck: Equatable {
    let marks: [SessionMark]
    let scannedAt: Date?

    struct Results {
        var scannedAt: Date?
        var byID: [String: Bool] = [:]

        func confirmed(_ candidates: [ExpiringSessionMark]) -> [ExpiringSessionMark] {
            candidates.filter { byID[$0.mark.id] == true }
        }
    }

    func run(reusing previous: Results = Results()) async -> Results {
        var results = Results(scannedAt: scannedAt)
        for mark in marks where mark.kind == .gitSnapshot {
            guard !Task.isCancelled else { break }
            if scannedAt == previous.scannedAt, let known = previous.byID[mark.id] {
                results.byID[mark.id] = known
            } else {
                results.byID[mark.id] = await SessionMarkService.isAvailable(mark, in: URL(fileURLWithPath: mark.projectPath))
            }
        }
        return results
    }
}

enum SessionMarkExpiryPolicy {
    static let retentionDays = 14

    static func state(
        for mark: SessionMark,
        now: Date = Date(),
        available: Bool = true
    ) -> SessionMarkExpiryState {
        guard mark.kind == .gitSnapshot else { return .stable }
        guard available, let sha = mark.snapshotSHA, !sha.isEmpty else { return .unavailable }
        guard !mark.pinned else { return .stable }

        let expiresAt = mark.createdAt.addingTimeInterval(
            Double(retentionDays) * 24 * 60 * 60
        )
        let remaining = expiresAt.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }

        guard remaining <= 4 * 86_400 else { return .stable }
        return .expiring(daysRemaining: Int(ceil(remaining / 86_400)))
    }

    static func attentionCandidates(in marks: [SessionMark], focusedPaths: Set<String>, now: Date) -> [ExpiringSessionMark] {
        guard !marks.isEmpty, !focusedPaths.isEmpty else { return [] }
        let paths = Dictionary(focusedPaths.map { (PathTools.normalize($0), $0) }, uniquingKeysWith: min)
        return marks.compactMap { mark -> ExpiringSessionMark? in
            guard mark.expiryReminderDismissed != true, case let .expiring(days) = state(for: mark, now: now),
                  let projectPath = paths[PathTools.normalize(mark.projectPath)] else { return nil }
            // A clean automatic start mark has no unsaved work to protect. Named checkpoints still matter.
            let label = mark.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !mark.changedFilesAtMark.isEmpty || (!label.isEmpty && label != SessionMarkService.conversationStartLabel) else { return nil }
            return ExpiringSessionMark(mark: mark, daysRemaining: days, projectPath: projectPath)
        }.sorted { ($0.mark.createdAt, $0.mark.id) < ($1.mark.createdAt, $1.mark.id) }
    }
}
