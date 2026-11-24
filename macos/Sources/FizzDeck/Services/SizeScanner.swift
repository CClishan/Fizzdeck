import Foundation

enum SizeScanner {
    static func scan(_ root: URL) async -> SizeInfo {
        let entries = FileTools.childEntries(of: root)
        var rows: [SizeRow] = []
        var rootFileBytes: Int64 = 0

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                rows.append(SizeRow(label: entry.lastPathComponent, bytes: 0, isDirectory: true))
            } else {
                let bytes = FileTools.fileSize(entry)
                rootFileBytes += bytes
            }
        }

        for index in rows.indices where rows[index].isDirectory {
            let url = root.appendingPathComponent(rows[index].label)
            let bytes = await directoryBytes(url)
            rows[index] = SizeRow(label: rows[index].label, bytes: bytes, isDirectory: true)
        }

        var breakdown = rows
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
            .map { $0 }
        if rootFileBytes > 0 {
            breakdown.append(SizeRow(label: "(根目录文件)", bytes: rootFileBytes, isDirectory: false))
        }
        breakdown = Array(breakdown.sorted { $0.bytes > $1.bytes }.prefix(10))

        return SizeInfo(
            totalBytes: rows.reduce(0) { $0 + $1.bytes } + rootFileBytes,
            breakdown: breakdown
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
}
