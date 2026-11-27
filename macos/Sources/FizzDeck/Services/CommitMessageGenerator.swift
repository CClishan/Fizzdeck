import Foundation

enum CommitMessageGenerator {
    static func ruleBased(
        project: RepoProject,
        changedFiles: [String],
        copyMode: CopyMode = .plain,
        now: Date = Date()
    ) -> String {
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        if let latest = project.sessions.recentSessions
            .filter({ $0.kind == .conversation && $0.modified >= twoHoursAgo })
            .max(by: { $0.modified < $1.modified }),
           let rawIntent = latest.primaryIntent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawIntent.isEmpty {
            let firstLine = rawIntent
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !firstLine.isEmpty {
                let redacted = SecretRedactor.redact(firstLine).text
                let trimmed = String(redacted.prefix(48))
                return "更新：\(trimmed)"
            }
        }

        if !changedFiles.isEmpty {
            let names = changedFiles
                .prefix(3)
                .map { URL(fileURLWithPath: $0).lastPathComponent }
            let suffix = changedFiles.count > 3 ? " 等" : ""
            let raw = "更新 \(changedFiles.count) 个文件：\(names.joined(separator: ", "))\(suffix)"
            return SecretRedactor.redact(raw).text
        }

        return copyMode == .plain ? "保存当前进度" : "chore: save working changes"
    }
}
