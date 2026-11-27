import Foundation

enum ProjectScriptSource: String, Codable, Sendable, CaseIterable {
    case npm
    case make
    case just

    var label: String {
        switch self {
        case .npm: "package.json"
        case .make: "Makefile"
        case .just: "justfile"
        }
    }
}

struct ProjectScript: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let command: String
    let source: ProjectScriptSource
}

struct ProjectScriptPreferences: Codable, Sendable, Equatable {
    static let currentVersion = 1
    static let defaultFile = AppPaths.stateDir.appendingPathComponent("script-preferences.json")

    var version = currentVersion
    var pinned: [String: [String]] = [:]

    func pinnedIDs(for projectPath: String) -> [String] {
        pinned[PathTools.normalize(projectPath)] ?? []
    }

    static func load(file: URL = defaultFile) -> ProjectScriptPreferences {
        guard let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(ProjectScriptPreferences.self, from: data),
              value.version <= currentVersion
        else {
            return ProjectScriptPreferences()
        }
        return value.sanitized()
    }

    static func save(_ value: ProjectScriptPreferences, file: URL = defaultFile) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value.sanitized())
        try data.write(to: file, options: .atomic)
    }

    static func setPinned(
        _ ids: [String],
        for projectPath: String,
        file: URL = defaultFile
    ) -> ProjectScriptPreferences {
        var value = load(file: file)
        let path = PathTools.normalize(projectPath)
        let sanitized = sanitize(ids)
        if sanitized.isEmpty {
            value.pinned.removeValue(forKey: path)
        } else {
            value.pinned[path] = sanitized
        }
        try? save(value, file: file)
        return value
    }

    private func sanitized() -> ProjectScriptPreferences {
        var copy = self
        copy.version = Self.currentVersion
        copy.pinned = copy.pinned.reduce(into: [:]) { result, entry in
            let ids = Self.sanitize(entry.value)
            if !ids.isEmpty {
                result[PathTools.normalize(entry.key)] = ids
            }
        }
        return copy
    }

    private static func sanitize(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

enum RunDetector {
    static func runConfig(_ directory: URL) -> RunConfig? {
        let packageURL = directory.appendingPathComponent("package.json")
        if FileTools.exists(packageURL), let package = FileTools.json(packageURL) {
            guard let scripts = package["scripts"] as? [String: Any] else { return nil }
            let name: String
            if scripts["dev"] != nil {
                name = "dev"
            } else if scripts["dev:pages"] != nil {
                name = "dev:pages"
            } else {
                return nil
            }
            let manager = manager(for: directory)
            let envText = FileTools.readFileIfExists(directory.appendingPathComponent(".env"))
                + FileTools.readFileIfExists(directory.appendingPathComponent(".dev.vars"))
            let envPort = firstPort(in: envText)
            let port = envPort ?? defaultPort(for: directory, package: package)
            return RunConfig(
                command: "\(manager) run \(name)",
                port: port,
                previewURL: "http://127.0.0.1:\(port)"
            )
        }
        if FileTools.exists(directory.appendingPathComponent("pom.xml")) {
            let hasRuoyiAdmin = FileTools.isDirectory(directory.appendingPathComponent("ruoyi-admin"))
            return RunConfig(
                command: hasRuoyiAdmin ? "mvn spring-boot:run -pl ruoyi-admin" : "mvn spring-boot:run",
                port: hasRuoyiAdmin ? 8988 : 8080,
                previewURL: hasRuoyiAdmin ? "http://127.0.0.1:8988" : "http://127.0.0.1:8080"
            )
        }
        if FileTools.exists(directory.appendingPathComponent("build.gradle")) {
            return RunConfig(command: "gradle assembleDebug", port: 0, previewURL: nil)
        }
        return nil
    }

    private static func defaultPort(for directory: URL, package: [String: Any]) -> Int {
        var deps = Set<String>()
        for key in ["dependencies", "devDependencies"] {
            if let values = package[key] as? [String: Any] {
                deps.formUnion(values.keys)
            }
        }
        if deps.contains("next") || deps.contains("nuxt") || deps.contains("react-scripts") {
            return 3000
        }
        if deps.contains("astro") {
            return 4321
        }
        if FileTools.exists(directory.appendingPathComponent("next.config.mjs"))
            || FileTools.exists(directory.appendingPathComponent("next.config.ts"))
            || FileTools.exists(directory.appendingPathComponent("next.config.js")) {
            return 3000
        }
        return 5173
    }

    static func testCommand(_ directory: URL) -> TestCommand? {
        if FileTools.exists(directory.appendingPathComponent("package.json")),
           let package = FileTools.json(directory.appendingPathComponent("package.json")),
           let scripts = package["scripts"] as? [String: Any] {
            let manager = manager(for: directory)
            for key in ["test", "test:unit", "vitest", "check", "typecheck", "lint"] {
                guard let value = scripts[key] as? String else { continue }
                if value.range(of: #"no test specified|exit 1"#, options: .regularExpression) != nil {
                    continue
                }
                return TestCommand(label: key, command: "\(manager) run \(key)")
            }
        }
        if FileTools.exists(directory.appendingPathComponent("pom.xml")) {
            return TestCommand(label: "mvn test", command: "mvn -q test")
        }
        if FileTools.exists(directory.appendingPathComponent("build.gradle")) {
            return TestCommand(label: "gradle test", command: "gradle test")
        }
        if FileTools.exists(directory.appendingPathComponent("go.mod")) {
            return TestCommand(label: "go test", command: "go test ./...")
        }
        return nil
    }

    static func scripts(_ directory: URL) -> [ProjectScript] {
        var result: [ProjectScript] = []
        var seen = Set<String>()

        func append(_ script: ProjectScript) {
            guard !script.name.isEmpty,
                  !script.name.hasPrefix("-"),
                  seen.insert(script.id).inserted
            else { return }
            result.append(script)
        }

        let packageURL = directory.appendingPathComponent("package.json")
        if FileTools.exists(packageURL),
           let package = FileTools.json(packageURL),
           let scripts = package["scripts"] as? [String: Any] {
            let manager = manager(for: directory)
            for name in scripts.keys.sorted() where name != "dev" && name != "dev:pages" {
                append(
                    ProjectScript(
                        id: "npm:\(name)",
                        name: name,
                        command: "\(manager) run \(shellQuote(name))",
                        source: .npm
                    )
                )
            }
        }

        if let makefileURL = ["Makefile", "makefile", "GNUmakefile"]
            .map({ directory.appendingPathComponent($0) })
            .first(where: FileTools.exists) {
            let text = FileTools.readText(makefileURL, maxBytes: 256 * 1_024)
            for name in makeTargets(in: text) {
                append(
                    ProjectScript(
                        id: "make:\(name)",
                        name: name,
                        command: "make \(shellQuote(name))",
                        source: .make
                    )
                )
            }
        }

        if let justfileURL = ["justfile", "Justfile", ".justfile"]
            .map({ directory.appendingPathComponent($0) })
            .first(where: FileTools.exists) {
            let text = FileTools.readText(justfileURL, maxBytes: 256 * 1_024)
            for name in justRecipes(in: text) {
                append(
                    ProjectScript(
                        id: "just:\(name)",
                        name: name,
                        command: "just \(shellQuote(name))",
                        source: .just
                    )
                )
            }
        }

        return result.sorted { left, right in
            if left.source != right.source {
                return sourceOrder(left.source) < sourceOrder(right.source)
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    static func makeTargets(in text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^([A-Za-z0-9_.-]+)(?:\s+[A-Za-z0-9_.-]+)*\s*:(?!\s*=)"#
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[valueRange])
            guard !name.hasPrefix("."),
                  !name.hasPrefix("_"),
                  !name.isEmpty,
                  seen.insert(name).inserted
            else { continue }
            result.append(name)
        }
        return result
    }

    static func justRecipes(in text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^@?([A-Za-z0-9_-]+)(?:\s+[^:\n]*)?:(?!\s*=)"#
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[valueRange])
            let reserved: Set<String> = [
                "alias", "export", "import", "set", "mod", "unexport",
            ]
            guard !reserved.contains(name),
                  !name.hasPrefix("_"),
                  seen.insert(name).inserted
            else { continue }
            result.append(name)
        }
        return result
    }

    static func manager(for directory: URL) -> String {
        if FileTools.exists(directory.appendingPathComponent("pnpm-lock.yaml")) { return "pnpm" }
        if FileTools.exists(directory.appendingPathComponent("yarn.lock")) { return "yarn" }
        if FileTools.exists(directory.appendingPathComponent("bun.lock"))
            || FileTools.exists(directory.appendingPathComponent("bun.lockb")) { return "bun" }
        return "npm"
    }

    private static func firstPort(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^PORT=(\d{3,5})"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[valueRange])
    }

    private static func sourceOrder(_ source: ProjectScriptSource) -> Int {
        switch source {
        case .npm: 0
        case .make: 1
        case .just: 2
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
