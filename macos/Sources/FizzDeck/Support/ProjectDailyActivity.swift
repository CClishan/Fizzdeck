import Foundation

struct SessionCostTotal: Equatable, Sendable {
    private(set) var subtotal = 0.0
    private(set) var priced = 0
    private(set) var unpriced = 0

    mutating func add(_ session: SessionRecord, countZeroAsUnpriced: Bool = false) {
        let cost = session.costUSD ?? PricingCatalog.estimate(model: session.model, usage: session.usage)
        if let cost, cost.isFinite, cost >= 0, !countZeroAsUnpriced || cost > 0 {
            subtotal += cost
            priced += 1
        } else {
            unpriced += 1
        }
    }

    mutating func add(_ other: Self) {
        subtotal += other.subtotal
        priced += other.priced
        unpriced += other.unpriced
    }

    var amount: Double? { priced > 0 ? subtotal : nil }

    var amountLabel: String {
        guard let amount else { return unpriced > 0 ? FizzL10n.text("未计价", "Unpriced") : FizzL10n.text("无会话", "No sessions") }
        return Format.cost(amount, estimated: amount > 0) ?? "—"
    }

    var isPartial: Bool { priced > 0 && unpriced > 0 }

    var description: String {
        isPartial ? FizzL10n.text("\(amountLabel)（另有 \(unpriced) 次未计价）", "\(amountLabel) (\(unpriced) unpriced)") : amountLabel
    }
}

struct ProjectActivityDay: Identifiable, Equatable {
    let date: Date
    let commits: Int?
    var cost = SessionCostTotal()
    var id: Date { date }

    static func series(
        sessions: [SessionRecord], commits: [String: Int]?, days: Int,
        now: Date = Date(), calendar: Calendar = .current
    ) -> [Self] {
        let today = calendar.startOfDay(for: now)
        guard days > 0, let start = calendar.date(byAdding: .day, value: 1 - days, to: today) else { return [] }
        var costs: [Date: SessionCostTotal] = [:]
        for session in sessions where session.kind == .conversation && (start...now).contains(session.modified) {
            costs[calendar.startOfDay(for: session.modified), default: SessionCostTotal()].add(session)
        }
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = WorkbenchMetrics.dayKey(date, calendar: calendar)
            return Self(date: date, commits: commits.map { $0[key, default: 0] }, cost: costs[date] ?? SessionCostTotal())
        }
    }
}
