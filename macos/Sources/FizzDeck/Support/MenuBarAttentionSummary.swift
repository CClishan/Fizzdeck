import Foundation

enum MenuBarAttentionSummary {
    static func count(
        items: [ProjectAttentionItem],
        doctorReports: [String: DoctorProjectReport] = [:],
        focusedPaths: Set<String>? = nil
    ) -> Int {
        var keys = Set(items.map(\.id))

        for (path, report) in doctorReports {
            if let focusedPaths, !focusedPaths.contains(path) {
                continue
            }
            guard report.issues.contains(where: { $0.severity == .critical }) else {
                continue
            }
            keys.insert("\(path):\(ProjectAttentionKind.doctorCritical.rawValue)")
        }
        return keys.count
    }
}

enum MenuBarSnapshotMarkPolicy {
    static func latestCandidate(
        in marks: [SessionMark],
        now: Date = Date()
    ) -> SessionMark? {
        marks
            .filter {
                $0.kind == .gitSnapshot
                    && !($0.snapshotSHA ?? "").isEmpty
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first { mark in
                switch SessionMarkExpiryPolicy.state(
                    for: mark,
                    now: now,
                    available: true
                ) {
                case .expired, .unavailable:
                    false
                case .stable, .expiring:
                    true
                }
            }
    }
}
