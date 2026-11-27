import Darwin
import Foundation

enum DoctorInputs {
    static let manifests: Set<String> = [
        "package.json", "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb",
        "pyproject.toml", "requirements.txt", "poetry.lock", "uv.lock", "Pipfile", "Pipfile.lock", ".nvmrc", ".node-version", ".python-version",
        ".go-version", "go.mod", "go.sum", "Cargo.toml", "Cargo.lock", "rust-toolchain", "rust-toolchain.toml", "Gemfile", "Gemfile.lock",
        ".ruby-version", "Package.swift", "Package.resolved", ".swift-version", ".gitignore",
    ]

    // Inspect the directory entries only, never descend into a dependency or source tree.
    static func envNames(in root: URL) -> Set<String> {
        var names: Set<String> = [".env", ".env.local", ".env.example"]
        guard let entries = opendir(root.path) else { return names }
        defer { closedir(entries) }
        for _ in 0..<2048 {
            guard let entry = readdir(entries) else { break }
            let name = withUnsafeBytes(of: &entry.pointee.d_name) {
                String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name.hasPrefix(".env") { names.insert(name) }
            if names.count >= 32 { break }
        }
        return names
    }

    static func isPrivateEnv(_ name: String) -> Bool {
        (name == ".env" || name.hasPrefix(".env.")) && ![".example", ".sample", ".template", ".dist"].contains { name.hasSuffix($0) }
    }

    // Declarations are untrusted. Refuse symlinks, FIFOs and oversized reads, including replacement races.
    static func text(_ file: URL, limit: Int, prefixOnly: Bool = false) -> String {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return "" }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              prefixOnly || info.st_size <= limit, let data = try? handle.read(upToCount: limit)
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
