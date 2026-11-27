import Foundation

enum RuntimeKind: String, Sendable, Equatable, Hashable {
    case node
    case python
    case go, rust, ruby, swift

    var title: String {
        switch self {
        case .node: "Node"
        case .python: "Python"
        case .go: "Go"
        case .rust: "Rust"
        case .ruby: "Ruby"
        case .swift: "Swift"
        }
    }
}

struct RuntimeVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let components: [Int]

    fileprivate init(components: [Int]) { self.components = components }

    init?<S: StringProtocol>(_ raw: S) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstDigit = trimmed.firstIndex(where: \.isNumber) else { return nil }
        let numeric = trimmed[firstDigit...].prefix { $0.isNumber || $0 == "." }
        let pieces = numeric.split(separator: ".", omittingEmptySubsequences: false)
        let values = pieces.compactMap { $0.count <= 6 ? Int($0) : nil }
        guard !values.isEmpty, values.count == pieces.count, values.count <= 4 else { return nil }
        components = values
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    var shortDescription: String {
        if components.count >= 2 {
            return "\(components[0]).\(components[1])"
        }
        return components.first.map(String.init) ?? ""
    }

    static func < (lhs: RuntimeVersion, rhs: RuntimeVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

private enum RuntimeVersionComparator: Sendable {
    case equal(RuntimeVersion)
    case greaterThan(RuntimeVersion)
    case greaterThanOrEqual(RuntimeVersion)
    case lessThan(RuntimeVersion)
    case lessThanOrEqual(RuntimeVersion)
    case prefix([Int])

    func matches(_ version: RuntimeVersion) -> Bool {
        switch self {
        case .equal(let target):
            return version == target
        case .greaterThan(let target):
            return version > target
        case .greaterThanOrEqual(let target):
            return version >= target
        case .lessThan(let target):
            return version < target
        case .lessThanOrEqual(let target):
            return version <= target
        case .prefix(let components):
            guard version.components.count >= components.count else { return false }
            return Array(version.components.prefix(components.count)) == components
        }
    }
}

private struct RuntimeVersionRequirement: Sendable {
    let alternatives: [[RuntimeVersionComparator]]

    func matches(_ version: RuntimeVersion) -> Bool {
        alternatives.contains { constraints in
            constraints.allSatisfy { $0.matches(version) }
        }
    }
}

struct RuntimeVersionSpec: Equatable, Sendable {
    let runtime: RuntimeKind
    let source: String
    let rawRequirement: String
    let fixCommand: String
}

struct RuntimeVersionMismatch: Identifiable, Equatable, Sendable {
    let runtime: RuntimeKind
    let requiredText: String
    let currentText: String?
    let source: String
    let fixCommand: String

    var id: String { "\(runtime.rawValue)::\(source)::\(requiredText)" }

    var title: String {
        if let currentText {
            return "这个项目需要 \(runtime.title) \(requiredText)，本机当前是 \(runtime.title) \(currentText)"
        }
        return "这个项目需要 \(runtime.title) \(requiredText)，但本机还没找到 \(runtime.title)"
    }

    var detail: String {
        "来自 \(source)。可复制切换命令，切到匹配版本后再运行一次体检。"
    }
}

struct RuntimeVersionEnvironment: Equatable, Sendable {
    var node: String? = nil, python: String? = nil, go: String? = nil, rust: String? = nil, ruby: String? = nil, swift: String? = nil

    subscript(kind: RuntimeKind) -> String? {
        switch kind {
        case .node: node
        case .python: python
        case .go: go
        case .rust: rust
        case .ruby: ruby
        case .swift: swift
        }
    }
}

// Positive and missing versions share a short TTL. Concurrent projects probe each declared tool once.
private actor RuntimeProbeCache {
    static let shared = RuntimeProbeCache()
    var entries: [RuntimeKind: (Date, Task<String?, Never>)] = [:]

    func value(for kind: RuntimeKind) async -> String? {
        if let (expiry, task) = entries[kind], expiry > Date() { return await task.value }
        let task = Task { await RuntimeVersionChecker.probe(kind) }
        entries[kind] = (Date().addingTimeInterval(300), task)
        return await task.value
    }
}

enum RuntimeVersionChecker {
    static func inspectProject(
        in directory: URL,
        environment: RuntimeVersionEnvironment? = nil
    ) async -> [RuntimeVersionMismatch] {
        let specs = requirements(in: directory)
        guard !specs.isEmpty else { return [] }

        let resolvedEnvironment = if let environment {
            environment
        } else {
            await detectEnvironment(for: Set(specs.map(\.runtime)))
        }
        return check(
            specs: specs,
            environment: resolvedEnvironment
        )
    }

    static func detectEnvironment(
        for runtimes: Set<RuntimeKind> = [.node, .python]
    ) async -> RuntimeVersionEnvironment {
        await withTaskGroup(of: (RuntimeKind, String?).self) { group in
            for runtime in runtimes {
                group.addTask {
                    (runtime, await RuntimeProbeCache.shared.value(for: runtime))
                }
            }

            var env = RuntimeVersionEnvironment()
            for await (runtime, value) in group {
                switch runtime {
                case .node:
                    env.node = value
                case .python:
                    env.python = value
                case .go: env.go = value
                case .rust: env.rust = value
                case .ruby: env.ruby = value
                case .swift: env.swift = value
                }
            }
            return env
        }
    }

    fileprivate static func probe(_ kind: RuntimeKind) async -> String? {
        let systemBins = ["/opt/homebrew/bin", "/usr/local/bin"]
        let tool: (String, [String], [String])
        switch kind {
        case .node: tool = ("node", ["--version"], systemBins)
        case .python: tool = ("python3", ["-I", "--version"], systemBins + DoctorCommand.developerBins)
        case .go: tool = ("go", ["version"], systemBins + ["/usr/local/go/bin"])
        case .rust: tool = ("rustc", ["--version"], systemBins + [AppPaths.home.appendingPathComponent(".cargo/bin").path])
        case .ruby: tool = ("ruby", ["--disable-gems", "--version"], systemBins + ["/usr/bin"])
        case .swift: tool = ("swift", ["--version"], ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"] + DoctorCommand.developerBins)
        }
        guard let binary = DoctorCommand.executable(tool.0, in: tool.2) else { return nil }
        let environment = ["GOTOOLCHAIN": "local", "GOENV": "off", "GOWORK": "off", "RUSTUP_AUTO_INSTALL": "0",
                           "RUSTUP_NO_UPDATE_CHECK": "1", "RUSTUP_HOME": AppPaths.home.appendingPathComponent(".rustup").path]
        guard let output = await DoctorCommand.run(binary, tool.1, cwd: URL(fileURLWithPath: "/"), environment: environment) else { return nil }
        let line = kind == .swift ? output.components(separatedBy: .newlines).first { $0.contains("Swift version ") } : output
        return line.flatMap(RuntimeVersion.init)?.description
    }

    static func requirements(in directory: URL) -> [RuntimeVersionSpec] {
        let nvmrc = declaration(
            in: DoctorInputs.text(directory.appendingPathComponent(".nvmrc"), limit: 8192)
        )
        let nodeVersionFile = declaration(
            in: DoctorInputs.text(directory.appendingPathComponent(".node-version"), limit: 8192)
        )
        let pythonVersionFile = declaration(
            in: DoctorInputs.text(directory.appendingPathComponent(".python-version"), limit: 8192)
        )
        let engineNode = packageEngineNode(in: directory)

        var result: [RuntimeVersionSpec] = []
        if let nvmrc, let spec = makeSpec(
            runtime: .node,
            source: ".nvmrc",
            raw: nvmrc,
            fixCommand: "nvm use"
        ) {
            result.append(spec)
        } else if let nodeVersionFile, let spec = makeSpec(
            runtime: .node,
            source: ".node-version",
            raw: nodeVersionFile,
            fixCommand: "fnm use"
        ) {
            result.append(spec)
        } else if let engineNode, let spec = makeSpec(
            runtime: .node,
            source: "package.json engines.node",
            raw: engineNode,
            fixCommand: engineInstallCommand(engineNode)
        ) {
            result.append(spec)
        }

        if let pythonVersionFile, let spec = makeSpec(
            runtime: .python,
            source: ".python-version",
            raw: pythonVersionFile,
            fixCommand: pythonInstallCommand(pythonVersionFile)
        ) {
            result.append(spec)
        }
        func add(_ kind: RuntimeKind, _ file: String, _ pattern: String, minimum: Bool = false, command: (String) -> String) {
            guard !result.contains(where: { $0.runtime == kind }) else { return }
            let text = DoctorInputs.text(directory.appendingPathComponent(file), limit: 32 * 1024, prefixOnly: true)
            guard let match = text.range(of: pattern, options: .regularExpression),
                  let number = RuntimeVersion(text[match])?.description else { return }
            if let spec = makeSpec(runtime: kind, source: file, raw: (minimum ? ">=" : "") + number, fixCommand: command(number)) { result.append(spec) }
        }
        let n = #"[0-9]{1,6}(?:\.[0-9]{1,6}){0,2}"#
        let pin = #"(?m)\A\s*"# + n + #"[ \t]*(?:\r?$)"#
        add(.go, ".go-version", pin) { "go install golang.org/dl/go\($0)@latest" }
        add(.go, "go.mod", #"(?m)^\s*go[ \t]+"# + n + #"[ \t]*(?://[^\n]*)?$"#, minimum: true) { "go install golang.org/dl/go\($0)@latest" }
        add(.rust, "rust-toolchain.toml", #"(?m)^\s*channel\s*=\s*[\"']"# + n + #"[\"'][ \t]*(?:#[^\n]*)?$"#) { "rustup override set \($0)" }
        add(.rust, "rust-toolchain", pin) { "rustup override set \($0)" }
        add(.rust, "Cargo.toml", #"(?m)^\s*rust-version\s*=\s*[\"']"# + n + #"[\"'][ \t]*(?:#[^\n]*)?$"#, minimum: true) { "rustup override set \($0)" }
        add(.ruby, ".ruby-version", #"(?m)\A\s*(?:ruby-)?"# + n + #"[ \t]*$"#) { "rbenv install -s \($0) && rbenv local \($0)" }
        add(.ruby, "Gemfile", #"(?m)^\s*ruby[ \t]+[\"']"# + n + #"[\"'][ \t]*(?:#[^\n]*)?$"#) { "rbenv install -s \($0) && rbenv local \($0)" }
        add(.swift, ".swift-version", pin) { "swiftly use \($0)" }
        add(.swift, "Package.swift", #"(?m)\A\s*//\s*swift-tools-version:\s*"# + n + #"[ \t]*$"#, minimum: true) { "swiftly install \($0)" }
        return result
    }

    static func check(
        specs: [RuntimeVersionSpec],
        environment: RuntimeVersionEnvironment
    ) -> [RuntimeVersionMismatch] {
        specs.compactMap { spec in
            guard let requirement = parseRequirement(spec.rawRequirement) else { return nil }
            let installed = environment[spec.runtime]
            if let installed,
               let version = RuntimeVersion(installed),
               requirement.matches(version) {
                return nil
            }
            let current = installed.flatMap(RuntimeVersion.init)?.shortDescription
            return RuntimeVersionMismatch(
                runtime: spec.runtime,
                requiredText: spec.rawRequirement,
                currentText: current,
                source: spec.source,
                fixCommand: spec.fixCommand
            )
        }
    }

    static func requirementMatches(_ raw: String, version: String) -> Bool {
        guard let requirement = parseRequirement(raw),
              let parsedVersion = RuntimeVersion(version)
        else { return false }
        return requirement.matches(parsedVersion)
    }

    static func installedVersion(from raw: String) -> String? {
        RuntimeVersion(raw)?.description
    }

    private static func declaration(in text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func packageEngineNode(in directory: URL) -> String? {
        let url = directory.appendingPathComponent("package.json")
        let data = Data(DoctorInputs.text(url, limit: 256 * 1024).utf8)
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let engines = object["engines"] as? [String: Any],
              let node = engines["node"] as? String
        else { return nil }
        let trimmed = node.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func makeSpec(
        runtime: RuntimeKind,
        source: String,
        raw: String,
        fixCommand: String
    ) -> RuntimeVersionSpec? {
        guard raw.utf8.count <= 96, raw.range(of: #"\A[0-9vVxX*.,<>=~^| \t-]+\z"#, options: .regularExpression) != nil,
              parseRequirement(raw) != nil, leadingVersion(in: raw) != nil else { return nil }
        return RuntimeVersionSpec(
            runtime: runtime,
            source: source,
            rawRequirement: raw,
            fixCommand: fixCommand
        )
    }

    private static func engineInstallCommand(_ raw: String) -> String {
        let version = leadingVersion(in: raw) ?? raw
        return "nvm install \(version) && nvm use \(version)"
    }

    private static func pythonInstallCommand(_ raw: String) -> String {
        let version = leadingVersion(in: raw) ?? raw
        return "pyenv install \(version) && pyenv local \(version)"
    }

    private static func leadingVersion(in raw: String) -> String? {
        let pieces = raw.split(whereSeparator: { !($0.isNumber || $0 == ".") })
        return pieces.compactMap { RuntimeVersion(String($0))?.description }.first
    }

    private static func parseRequirement(_ raw: String) -> RuntimeVersionRequirement? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.lowercased().contains("lts")
        else { return nil }

        let alternatives = trimmed
            .components(separatedBy: "||")
            .compactMap { parseAlternative($0) }
        guard !alternatives.isEmpty else { return nil }
        return RuntimeVersionRequirement(alternatives: alternatives)
    }

    private static func parseAlternative(_ raw: String) -> [RuntimeVersionComparator]? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let hyphenParts = normalized.components(separatedBy: " - ")
        if hyphenParts.count == 2,
           let lower = RuntimeVersion(hyphenParts[0]),
           let upper = RuntimeVersion(hyphenParts[1]) {
            var constraints: [RuntimeVersionComparator] = [.greaterThanOrEqual(lower)]
            if upper.components.count >= 3 {
                constraints.append(.lessThanOrEqual(upper))
            } else if upper.components.count == 2 {
                let upperExclusive = RuntimeVersion(components: [upper.components[0], upper.components[1] + 1])
                constraints.append(.lessThan(upperExclusive))
            } else {
                let upperExclusive = RuntimeVersion(components: [upper.components[0] + 1])
                constraints.append(.lessThan(upperExclusive))
            }
            return constraints
        }

        let tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var comparisons: [RuntimeVersionComparator] = []
        for token in tokens {
            guard let parsed = parseToken(token) else { return nil }
            comparisons.append(contentsOf: parsed)
        }
        return comparisons.isEmpty ? nil : comparisons
    }

    private static func parseToken(_ rawToken: String) -> [RuntimeVersionComparator]? {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let lowered = token.lowercased()
        if lowered == "*" || lowered == "x" || lowered == "latest" {
            return []
        }

        if token.hasPrefix(">=") {
            return RuntimeVersion(token.dropFirst(2)).map { [.greaterThanOrEqual($0)] }
        }
        if token.hasPrefix("<=") {
            return RuntimeVersion(token.dropFirst(2)).map { [.lessThanOrEqual($0)] }
        }
        if token.hasPrefix(">") {
            return RuntimeVersion(token.dropFirst()).map { [.greaterThan($0)] }
        }
        if token.hasPrefix("<") {
            return RuntimeVersion(token.dropFirst()).map { [.lessThan($0)] }
        }
        if token.hasPrefix("=") {
            guard let version = RuntimeVersion(token.dropFirst()) else { return nil }
            return [.equal(version)]
        }
        if token.hasPrefix("^") {
            guard let version = RuntimeVersion(token.dropFirst()) else { return nil }
            return [.greaterThanOrEqual(version), .lessThan(caretUpperBound(for: version))]
        }
        if token.hasPrefix("~") {
            guard let version = RuntimeVersion(token.dropFirst()) else { return nil }
            return [.greaterThanOrEqual(version), .lessThan(tildeUpperBound(for: version))]
        }
        if lowered.contains("x") || lowered.contains("*") {
            let numeric = token
                .lowercased()
                .split(separator: ".")
                .prefix { $0 != "x" && $0 != "*" }
                .compactMap { Int($0) }
            return numeric.isEmpty ? [] : [.prefix(numeric)]
        }

        guard let version = RuntimeVersion(token) else { return nil }
        switch version.components.count {
        case 1:
            return [.prefix([version.components[0]])]
        case 2:
            return [.prefix(Array(version.components.prefix(2)))]
        default:
            return [.equal(version)]
        }
    }

    private static func caretUpperBound(for version: RuntimeVersion) -> RuntimeVersion {
        if version.components[0] > 0 {
            return RuntimeVersion(components: [version.components[0] + 1])
        }
        if version.components.count >= 2, version.components[1] > 0 {
            return RuntimeVersion(components: [0, version.components[1] + 1])
        }
        let patch = version.components.count >= 3 ? version.components[2] + 1 : 1
        return RuntimeVersion(components: [0, 0, patch])
    }

    private static func tildeUpperBound(for version: RuntimeVersion) -> RuntimeVersion {
        if version.components.count == 1 {
            return RuntimeVersion(components: [version.components[0] + 1])
        }
        return RuntimeVersion(components: [version.components[0], version.components[1] + 1])
    }
}
