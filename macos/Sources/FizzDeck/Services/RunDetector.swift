import Foundation

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
            let port = envPort ?? AppPaths.knownPorts[directory.lastPathComponent] ?? 5173
            return RunConfig(
                command: "\(manager) run \(name)",
                port: port,
                previewURL: "http://127.0.0.1:\(port)"
            )
        }
        if FileTools.exists(directory.appendingPathComponent("pom.xml")) {
            return RunConfig(
                command: "mvn spring-boot:run -pl ruoyi-admin",
                port: 8988,
                previewURL: "http://127.0.0.1:8988"
            )
        }
        if FileTools.exists(directory.appendingPathComponent("build.gradle")) {
            return RunConfig(command: "gradle assembleDebug", port: 0, previewURL: nil)
        }
        return nil
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

    private static func manager(for directory: URL) -> String {
        if FileTools.exists(directory.appendingPathComponent("pnpm-lock.yaml")) { return "pnpm" }
        if FileTools.exists(directory.appendingPathComponent("bun.lock")) { return "bun" }
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
}
