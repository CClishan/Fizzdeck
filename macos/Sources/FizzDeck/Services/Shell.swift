import Foundation

struct ShellOutput: Sendable {
    let status: Int32
    let text: String

    var succeeded: Bool { status == 0 }
}

enum Shell {
    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
        env["PATH"] = path
        return env
    }

    static func run(
        _ command: String,
        _ arguments: [String] = [],
        cwd: URL? = nil,
        timeout: TimeInterval = 20,
        extraEnvironment: [String: String] = [:]
    ) async -> ShellOutput? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [command] + arguments
                process.currentDirectoryURL = cwd

                var env = environment
                extraEnvironment.forEach { env[$0.key] = $0.value }
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()

                let text = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ShellOutput(status: process.terminationStatus, text: text))
            }
        }
    }

    static func output(
        _ command: String,
        _ arguments: [String] = [],
        cwd: URL? = nil,
        timeout: TimeInterval = 20
    ) async -> String? {
        guard let result = await run(command, arguments, cwd: cwd, timeout: timeout), result.succeeded else {
            return nil
        }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
