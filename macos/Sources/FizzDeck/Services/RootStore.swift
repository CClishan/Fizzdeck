import Foundation

enum RootStore {
    static func load() -> [String] {
        if let data = try? Data(contentsOf: AppPaths.rootsFile),
           let values = try? JSONSerialization.jsonObject(with: data) as? [String] {
            let existing = values
                .map(PathTools.normalize)
                .filter { FileTools.isDirectory(URL(fileURLWithPath: $0)) }
            var seen = Set<String>()
            return existing.filter { seen.insert($0).inserted }
        }
        return AppPaths.defaultRoots
            .map(\.path)
            .filter { FileTools.isDirectory(URL(fileURLWithPath: $0)) }
    }

    static func save(_ roots: [String]) throws {
        try FileTools.writeJSON(roots.map(PathTools.normalize), to: AppPaths.rootsFile)
    }
}

enum MetaStore {
    static func load() -> [String: ProjectMeta] {
        guard let data = try? Data(contentsOf: AppPaths.metaFile),
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
            meta.attention = parseAttention(raw["attention"])
            result[PathTools.normalize(path)] = meta
        }
        return result
    }

    static func save(_ metadata: [String: ProjectMeta]) throws {
        let object: [String: [String: Any]] = metadata.reduce(into: [:]) { result, entry in
            var raw: [String: Any] = [
                "starred": entry.value.starred,
                "note": entry.value.note,
            ]
            if let color = entry.value.color {
                raw["color"] = color.rawValue
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
        try FileTools.writeJSON(object, to: AppPaths.metaFile)
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
