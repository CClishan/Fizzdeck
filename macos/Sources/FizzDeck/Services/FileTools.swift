import Foundation

enum FileTools {
    nonisolated(unsafe) static let manager = FileManager.default

    static func exists(_ path: String) -> Bool {
        manager.fileExists(atPath: path)
    }

    static func exists(_ url: URL) -> Bool {
        manager.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return manager.fileExists(atPath: url.path, isDirectory: &value) && value.boolValue
    }

    static func readText(_ url: URL, maxBytes: Int = 512 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func readFileIfExists(_ url: URL, maxBytes: Int = 512 * 1024) -> String {
        exists(url) ? readText(url, maxBytes: maxBytes) : ""
    }

    static func head(_ url: URL, bytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: bytes)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func tail(_ url: URL, bytes: Int) -> String {
        guard let attributes = try? manager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return "" }
        defer { try? handle.close() }
        let total = size.int64Value
        if total > Int64(bytes) {
            try? handle.seek(toOffset: UInt64(total - Int64(bytes)))
        }
        let data = (try? handle.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func scanLinesFromEnd(
        in url: URL,
        chunkBytes: Int = 128 * 1024,
        maxBytes: Int = 8 * 1024 * 1024,
        _ body: (String) -> Bool
    ) -> Bool {
        guard chunkBytes > 0,
              maxBytes > 0,
              let attributes = try? manager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }

        var end = size.int64Value
        var remaining = Int64(maxBytes)
        var prefix = Data()

        while end > 0, remaining > 0 {
            let count = min(Int64(chunkBytes), end, remaining)
            let start = end - count
            do {
                try handle.seek(toOffset: UInt64(start))
            } catch {
                return false
            }
            guard var data = try? handle.read(upToCount: Int(count)), !data.isEmpty else {
                return false
            }
            if !prefix.isEmpty {
                data.append(prefix)
                prefix.removeAll(keepingCapacity: false)
            }

            var lineEnd = data.endIndex
            while lineEnd > data.startIndex,
                  let newline = data[data.startIndex..<lineEnd].lastIndex(of: 0x0A) {
                let lineStart = data.index(after: newline)
                if lineStart < lineEnd,
                   let line = String(data: data[lineStart..<lineEnd], encoding: .utf8),
                   body(line) {
                    return true
                }
                lineEnd = newline
            }
            if lineEnd > data.startIndex {
                prefix = Data(data[data.startIndex..<lineEnd])
            }

            end = start
            remaining -= count
        }

        if !prefix.isEmpty,
           let line = String(data: prefix, encoding: .utf8),
           body(line) {
            return true
        }
        return false
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    static func childDirectories(of url: URL) -> [URL] {
        guard let contents = try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }
        return contents.compactMap { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
            return child
        }
    }

    enum DirectoryReadResult {
        case entries([URL])
        case permissionDenied
        case unreadable
    }

    static func readChildEntries(of url: URL) -> DirectoryReadResult {
        do {
            let entries = try manager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
            return .entries(entries)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                return .permissionDenied
            }
            if error.domain == NSPOSIXErrorDomain && (error.code == Int(EPERM) || error.code == Int(EACCES)) {
                return .permissionDenied
            }
            return .unreadable
        }
    }

    static func childEntries(of url: URL) -> [URL] {
        switch readChildEntries(of: url) {
        case let .entries(entries): entries
        case .permissionDenied, .unreadable: []
        }
    }
}
