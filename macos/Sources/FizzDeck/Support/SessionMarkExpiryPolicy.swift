import Foundation

enum SessionMarkExpiryState: Equatable, Sendable {
    case stable
    case expiring(daysRemaining: Int)
    case expired
    case unavailable
}

enum SessionMarkExpiryPolicy {
    static let retentionDays = 14

    static func state(
        for mark: SessionMark,
        now: Date = Date(),
        available: Bool = true
    ) -> SessionMarkExpiryState {
        guard mark.kind == .gitSnapshot else { return .stable }
        guard available else { return .unavailable }
        guard !mark.pinned else { return .stable }

        let expiresAt = mark.createdAt.addingTimeInterval(
            Double(retentionDays) * 24 * 60 * 60
        )
        let remaining = expiresAt.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }

        let days = Int(ceil(remaining / (24 * 60 * 60)))
        guard (1...4).contains(days) else { return .stable }
        return .expiring(daysRemaining: days)
    }
}
