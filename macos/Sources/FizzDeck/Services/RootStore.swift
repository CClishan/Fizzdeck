import Foundation

enum RootStore {
    static var hasSavedRootsFile: Bool {
        FileTools.exists(AppPaths.rootsFile)
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: AppPaths.rootsFile),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        let existing = values
            .map(PathTools.normalize)
            .filter { FileTools.isDirectory(URL(fileURLWithPath: $0)) }
        var seen = Set<String>()
        return existing.filter { seen.insert($0).inserted }
    }

    static func save(_ roots: [String]) throws {
        try FileTools.writeJSON(roots.map(PathTools.normalize), to: AppPaths.rootsFile)
    }
}

enum OnboardingStore {
    static var isNeeded: Bool {
        !RootStore.hasSavedRootsFile && !FileTools.exists(AppPaths.onboardingFile)
    }

    static func markCompleted(skipped: Bool) throws {
        let payload: [String: Any] = [
            "completed": true,
            "skipped": skipped,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        try FileTools.writeJSON(payload, to: AppPaths.onboardingFile)
    }
}

enum MetaStore {
    private static func readState(_ file: URL) throws -> [String: [String: Any]] {
        guard FileTools.exists(file) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: [String: Any]]
        else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }

    static func saveDoctorExemptions(_ kinds: Set<DoctorIssueKind>, for path: String, to file: URL = AppPaths.metaFile) throws {
        var object = try readState(file)
        let key = PathTools.normalize(path)
        var raw = object[key] ?? [:]
        let values = kinds.filter(\.canExempt).map(\.rawValue).sorted()
        raw["doctorExemptions"] = values.isEmpty ? nil : values
        object[key] = raw
        try FileTools.writeJSON(object, to: file)
    }

    static func load(from file: URL = AppPaths.metaFile) -> [String: ProjectMeta] {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [:] }

        var result: [String: ProjectMeta] = [:]
        for (path, raw) in object {
            var meta = ProjectMeta()
            meta.starred = raw["starred"] as? Bool ?? false
            meta.note = raw["note"] as? String ?? ""
            if let color = raw["color"] as? String {
                meta.color = TagColor(rawValue: color)
            }
            if let group = raw["group"] as? String {
                let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
                meta.group = trimmed.isEmpty ? nil : trimmed
            }
            meta.attention = parseAttention(raw["attention"])
            meta.customArtwork = raw["customArtwork"] as? String
            meta.doctorExemptions = Set((raw["doctorExemptions"] as? [String] ?? [])
                .compactMap(DoctorIssueKind.init(rawValue:)).filter(\.canExempt))
            result[PathTools.normalize(path)] = meta
        }
        return result
    }

    static func save(_ metadata: [String: ProjectMeta], to file: URL = AppPaths.metaFile) throws {
        // Preserve keys written by the web client or a newer version. Never replace malformed state.
        let existing = try readState(file)
        let object: [String: [String: Any]] = metadata.reduce(into: [:]) { result, entry in
            var raw = existing[entry.key] ?? [:]
            raw["starred"] = entry.value.starred
            raw["note"] = entry.value.note
            for key in ["color", "group", "attention", "customArtwork", "doctorExemptions"] { raw.removeValue(forKey: key) }
            raw["customArtwork"] = entry.value.customArtwork
            let exemptions = entry.value.doctorExemptions.filter(\.canExempt).map(\.rawValue).sorted()
            if !exemptions.isEmpty { raw["doctorExemptions"] = exemptions }
            if let color = entry.value.color {
                raw["color"] = color.rawValue
            }
            if let group = entry.value.group, !group.isEmpty {
                raw["group"] = group
            }
            if !entry.value.attention.isEmpty {
                raw["attention"] = entry.value.attention.reduce(into: [String: [String: Any]]()) { result, rule in
                    var value: [String: Any] = ["muted": rule.value.muted]
                    if let until = rule.value.snoozedUntil {
                        value["snoozedUntil"] = until.timeIntervalSince1970
                    }
                    result[rule.key] = value
                }
            }
            result[entry.key] = raw
        }
        try FileTools.writeJSON(object, to: file)
    }

    private static func parseAttention(_ raw: Any?) -> [String: AttentionPreference] {
        guard let values = raw as? [String: [String: Any]] else { return [:] }
        var result: [String: AttentionPreference] = [:]

        for (kind, value) in values {
            var preference = AttentionPreference()
            preference.muted = value["muted"] as? Bool ?? false
            if let until = value["snoozedUntil"] as? NSNumber {
                preference.snoozedUntil = Date(timeIntervalSince1970: until.doubleValue)
            }
            if preference.muted || preference.snoozedUntil != nil {
                result[kind] = preference
            }
        }
        return result
    }
}
