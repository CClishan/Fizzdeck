import Foundation

enum SizeScanner {
    static func scan(_ root: URL) async -> SizeInfo {
        await scanWithDirectoryMap(root).size
    }

    static func scanWithDirectoryMap(_ root: URL) async -> (size: SizeInfo, directoryBytes: [String: Int64]) {
        let entries = FileTools.childEntries(of: root)
        var directoryNames: [String] = []
        var rootFileBytes: Int64 = 0

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                directoryNames.append(entry.lastPathComponent)
            } else {
                rootFileBytes += FileTools.fileSize(entry)
            }
        }

        let directoryBytes = await measureDirectories(in: root, names: directoryNames, maxConcurrent: 4)
        let rows = directoryNames.map { name in
            SizeRow(label: name, bytes: directoryBytes[name] ?? 0, isDirectory: true)
        }

        var breakdown = rows
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        if rootFileBytes > 0 {
            breakdown.append(SizeRow(label: "(根目录文件)", bytes: rootFileBytes, isDirectory: false))
        }
        breakdown = Array(breakdown.sorted { $0.bytes > $1.bytes }.prefix(10))

        let total = rows.reduce(0) { $0 + $1.bytes } + rootFileBytes
        return (
            SizeInfo(totalBytes: total, breakdown: breakdown),
            directoryBytes
        )
    }

    static func directoryBytes(_ url: URL) async -> Int64 {
        guard let result = await Shell.run("du", ["-sk", url.path], timeout: 30), result.succeeded else {
            return 0
        }
        let field = result.text
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
            .first
            .flatMap { Int64($0) } ?? 0
        return field * 1024
    }

    private static func measureDirectories(
        in root: URL,
        names: [String],
        maxConcurrent: Int
    ) async -> [String: Int64] {
        guard !names.isEmpty else { return [:] }
        return await withTaskGroup(of: (String, Int64).self, returning: [String: Int64].self) { group in
            var index = 0
            let limit = max(1, maxConcurrent)
            while index < min(limit, names.count) {
                let name = names[index]
                let url = root.appendingPathComponent(name, isDirectory: true)
                group.addTask {
                    (name, await directoryBytes(url))
                }
                index += 1
            }

            var collected: [String: Int64] = [:]
            while let (name, bytes) = await group.next() {
                collected[name] = bytes
                if index < names.count {
                    let nextName = names[index]
                    let url = root.appendingPathComponent(nextName, isDirectory: true)
                    group.addTask {
                        (nextName, await directoryBytes(url))
                    }
                    index += 1
                }
            }
            return collected
        }
    }
}
