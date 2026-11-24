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
            result[entry.key] = raw
        }
        try FileTools.writeJSON(object, to: AppPaths.metaFile)
    }
}
