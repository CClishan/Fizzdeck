import Darwin
import Foundation

enum VersionProtectionService {
    static func enable(in directory: URL, marksFile: URL, tmpDir: URL) async -> (succeeded: Bool, message: String) {
        let projectRoot = PathTools.canonical(directory.path)
        guard projectRoot != "/", ![tmpDir, marksFile].contains(where: {
            let path = PathTools.canonical($0.path)
            return path == projectRoot || path.hasPrefix(projectRoot + "/")
        }) else { return (false, "请选择不包含 FizzDeck 本地状态的项目目录。") }
        guard FileTools.isDirectory(directory), await outsideRepository(directory) else {
            return (false, "此目录已属于 Git 仓库，或无法检查目录状态。")
        }
        do {
            let ignore = directory.appendingPathComponent(".gitignore")
            let original = try readIgnore(ignore)
            let names = try FileTools.manager.contentsOfDirectory(atPath: directory.path)
            let rules = ProtectionFiles.ignoreRules(rootEntries: names)
            let bytes = original ?? Data()
            // Git strips a UTF-8 BOM only at byte zero; moving it would change the first user pattern.
            let bom = Data([0xef, 0xbb, 0xbf])
            let prefixBytes = bytes.starts(with: bom) ? bom : Data()
            let userRules = bytes.dropFirst(prefixBytes.count)
            let originalLines = Set(String(decoding: userRules, as: UTF8.self).components(separatedBy: .newlines))
            let missing = rules.filter { !originalLines.contains($0) }
            // Prepend defaults. Existing comments, negations, line endings and last-match precedence survive.
            let prefix = missing.isEmpty ? "" : missing.joined(separator: "\n") + "\n"
            let merged = prefixBytes + Data(prefix.utf8) + userRules

            // Prepare on the destination volume; publish .git with an exclusive rename only after the mark exists.
            let staging = try FileTools.manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                   appropriateFor: directory, create: true)
            defer { try? FileTools.manager.removeItem(at: staging) }
            guard !PathTools.canonical(staging.path).hasPrefix(PathTools.canonical(directory.path) + "/"),
                  await Shell.run("git", ["init", "--quiet", "--template=", staging.path], cwd: staging)?.succeeded == true
            else { return (false, "无法准备本地 Git 仓库。") }
            let git = staging.appendingPathComponent(".git")
            let info = git.appendingPathComponent("info")
            try FileTools.manager.createDirectory(at: info, withIntermediateDirectories: true)
            let defaults = Data((rules.joined(separator: "\n") + "\n").utf8)
            let exclude = info.appendingPathComponent("exclude")
            try defaults.write(to: exclude) // Lower priority than the original project's .gitignore.
            let generated = ProtectionFiles.generatedDirectories.map { $0 + "/\n" }.joined()
            try Data(generated.utf8).write(to: staging.appendingPathComponent(ProtectionFiles.marker))

            guard let mark = await SessionMarkService.protectionBaseline(for: directory, stagedGit: git, gitignore: merged, tmpDir: tmpDir) else {
                return (false, "无法安全建立基线。请检查读取权限或缩小目录范围。")
            }
            try FileTools.manager.removeItem(at: exclude)
            guard !Task.isCancelled, await outsideRepository(directory) else { return (false, "目录状态已变化，请刷新后重试。") }
            try await publish(mark, git: git, directory: directory, original: original, merged: merged, marksFile: marksFile)
            return (true, "已开启版本保护，第一条可还原基线已固定。")
        } catch {
            return (false, "未开启版本保护：\(error.localizedDescription)")
        }
    }

    private static func outsideRepository(_ directory: URL) async -> Bool {
        var url = directory.resolvingSymlinksInPath().standardizedFileURL
        while url.path != "/" {
            if (try? FileTools.manager.attributesOfItem(atPath: url.appendingPathComponent(".git").path)) != nil { return false }
            url.deleteLastPathComponent()
        }
        // Also detects bare repositories and their subdirectories.
        let result = await Shell.run("git", ["rev-parse", "--git-dir"], cwd: directory, extraEnvironment: ["LC_ALL": "C"])
        return result?.status == 128 && result?.text.contains("not a git repository") == true
    }

    private static func readIgnore(_ file: URL) throws -> Data? {
        do {
            let attrs = try FileTools.manager.attributesOfItem(atPath: file.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadUnsupportedScheme) }
            guard let bytes = attrs[.size] as? NSNumber, bytes.int64Value <= SessionMarkService.maxFileBytes else { throw CocoaError(.fileReadTooLarge) }
            return try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile { return nil }
    }

    @MainActor
    private static func publish(_ mark: SessionMark, git: URL, directory: URL, original: Data?, merged: Data, marksFile: URL) throws {
        let ignore = directory.appendingPathComponent(".gitignore")
        let destination = directory.appendingPathComponent(".git")
        guard !GitService.hasGit(directory), try readIgnore(ignore) == original else { throw CocoaError(.fileWriteFileExists) }
        let previous = MarkStore.load(from: marksFile)
        try MarkStore.upsertChecked(mark, in: marksFile)
        var wroteIgnore = false
        do {
            if original != merged {
                try merged.write(to: ignore, options: original == nil ? .withoutOverwriting : .atomic)
                wroteIgnore = true
            }
            guard renamex_np(git.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            MarkStore.save(previous, to: marksFile)
            if wroteIgnore, (try? readIgnore(ignore)) == merged {
                if let original { try original.write(to: ignore, options: .atomic) } else { try FileTools.manager.removeItem(at: ignore) }
            }
            throw error
        }
    }
}
