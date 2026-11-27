import Foundation

enum ProtectionFiles {
    static let marker = ".git/info/fizzdeck-protection"

    private static let secretNames = [".npmrc", ".pypirc", ".netrc", ".git-credentials", ".envrc", "credentials.json", "service-account.json", "secrets.json", "secrets.yaml", "secrets.yml", "secrets.toml", "id_rsa", "id_dsa", "id_ed25519", "id_ecdsa"]
    private static let secretExtensions = ["pem", "key", "p8", "p12", "pfx", "keystore", "jks", "kdbx", "mobileprovision"]
    private static let secretDirectories = [".ssh", ".aws", ".gnupg", ".kube"]
    // A custom Git negation may keep an artifact visible to the user; it still does not belong in a baseline.
    static let generatedDirectories = ["node_modules", "__pycache__", ".venv", ".build", "DerivedData", ".next", ".turbo", ".pytest_cache"]
    private static let envTemplates = [".env.example", ".env.sample", ".env.template"]

    static func ignoreRules(rootEntries names: [String]) -> [String] {
        let entries = Set(names)
        func has(_ markers: [String], suffix: String? = nil) -> Bool {
            !entries.isDisjoint(with: markers) || (suffix.map { ext in entries.contains { $0.hasSuffix(ext) } } ?? false)
        }
        var rules = [".DS_Store", ".env", ".env.*"] + envTemplates.map { "!" + $0 }
        rules += secretNames + secretExtensions.map { "*." + $0 } + secretDirectories.map { $0 + "/" }
        if has(["package.json", "pnpm-workspace.yaml", "package-lock.json", "yarn.lock", "bun.lock"]) {
            rules += ["node_modules/", ".next/", ".nuxt/", ".svelte-kit/", ".turbo/", ".vite/", "dist/", "build/", "coverage/"]
        }
        if has(["pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile", "uv.lock"], suffix: ".py") {
            rules += ["__pycache__/", "*.py[cod]", ".venv/", "venv/", ".pytest_cache/", ".mypy_cache/", ".ruff_cache/", "*.egg-info/", "dist/", "build/"]
        }
        if has(["Package.swift"], suffix: ".xcodeproj") || has([], suffix: ".xcworkspace") || has([], suffix: ".swift") {
            rules += [".build/", "DerivedData/", "xcuserdata/", "*.xcuserstate", "*.xcarchive/", "*.dSYM/"]
        }
        if has(["Cargo.toml"], suffix: ".rs") { rules += ["target/"] }
        if has(["go.mod", "go.work"], suffix: ".go") { rules += ["/bin/", "*.test", "coverage.out", "*.prof"] }
        var seen = Set<String>()
        return rules.filter { seen.insert($0).inserted }
    }

    static func excludedName(_ path: String) -> Bool {
        let parts = path.lowercased().split(separator: "/").map(String.init)
        guard let name = parts.last else { return true }
        let ext = (name as NSString).pathExtension
        return parts.contains { secretDirectories.contains($0) || $0 == ".git" }
            || ((name == ".env" || name.hasPrefix(".env.")) && !envTemplates.contains(name))
            || secretNames.contains(name) || secretExtensions.contains(ext)
            || ["zip", "tgz", "gz", "7z", "dmg", "pkg", "ipa", "exe", "o", "dylib", "sqlite", "db"].contains(ext)
    }

    /// Use the same checked bytes for the first snapshot. Never follow a symlink to read its target.
    static func snapshotData(at url: URL) throws -> Data? {
        let attrs = try FileTools.manager.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.int64Value <= SessionMarkService.maxFileBytes else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Int(SessionMarkService.maxFileBytes) + 1) ?? Data()
        guard data.count <= SessionMarkService.maxFileBytes else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard !text.contains("PRIVATE KEY-----"), !SecretRedactor.containsSecret(text) else { return nil }
        return data
    }

    // Stage only the bytes we inspected. A concurrent edit cannot slip a different file into Git.
    static func withIndex<T>(in directory: URL, gitDir: URL, tmpDir: URL, gitignore: Data?,
                             _ body: (String?) async -> T) async -> T {
        let staging = tmpDir.appendingPathComponent(UUID().uuidString)
        let mirror = staging.appendingPathComponent("files")
        let index = staging.appendingPathComponent("index").path
        defer { try? FileTools.manager.removeItem(at: staging) }
        let git = ["--git-dir", gitDir.path, "--work-tree", directory.path]
        let exclusions = gitDir.appendingPathComponent("info/fizzdeck-protection").path
        guard let result = await Shell.run("git", git + ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--exclude-from=\(exclusions)"], cwd: directory),
              result.succeeded else { return await body(nil) }
        let paths = Set(result.text.split(separator: "\0").map(String.init).filter { path in
            !excludedName(path) && !path.split(separator: "/").dropLast().contains { generatedDirectories.contains(String($0)) }
        })
        guard paths.count <= SessionMarkService.maxTrackedCount else { return await body(nil) }
        do {
            try FileTools.manager.createDirectory(at: mirror, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let rootPrefix = PathTools.canonical(directory.path) + "/"
            var bytes = 0
            for path in paths {
                try Task.checkCancellation()
                if path == ".gitignore", gitignore != nil { continue }
                let source = directory.appendingPathComponent(path)
                // Tracked paths may have been deleted or replaced by a symlinked directory.
                guard FileTools.exists(source), PathTools.canonical(source.path) == rootPrefix + path else { continue }
                let size = FileTools.fileSize(source)
                guard size <= SessionMarkService.maxFileBytes else { continue }
                bytes += Int(size)
                guard bytes <= 256 * 1024 * 1024 else { return await body(nil) }
                guard let data = try snapshotData(at: source) else { continue }
                let target = mirror.appendingPathComponent(path)
                try FileTools.manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
                if FileTools.manager.isExecutableFile(atPath: source.path) {
                    try FileTools.manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
                }
            }
            if let gitignore, !SecretRedactor.containsSecret(String(decoding: gitignore, as: UTF8.self)) {
                try gitignore.write(to: mirror.appendingPathComponent(".gitignore"))
            }
        } catch { return await body(nil) }
        let add = ["--git-dir", gitDir.path, "--work-tree", mirror.path, "-c", "core.hooksPath=/dev/null", "add", "-f", "-A", "--", "."]
        guard await Shell.run("git", add, cwd: mirror, timeout: 30, extraEnvironment: ["GIT_INDEX_FILE": index])?.succeeded == true else { return await body(nil) }
        return await body(index)
    }
}
