import CoreFoundation
import Foundation

enum SessionLogMetrics {
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let result = Int(exactly: number.doubleValue) else { return nil }
        return result
    }

    struct Coverage {
        private var bytes = 0
        private var valid = true

        mutating func consume(_ line: String) -> [String: Any]? {
            bytes += line.utf8.count + 1
            let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
            if object == nil { valid = false }
            return object
        }

        func covers(fileSize: Int64) -> Bool {
            // scanLines can omit the middle of large files and skips malformed UTF-8 lines.
            valid && bytes > 0 && (bytes == fileSize || bytes - 1 == fileSize)
        }
    }

    struct AgentTime {
        private var duration: Double = 0
        private var spans: [Range<Int>] = []

        mutating func add(milliseconds: Int) {
            if milliseconds > 0 { duration += Double(milliseconds) }
        }

        mutating func add(start: Int, end: Int) {
            if start > 0, end > start { spans.append(start..<end) }
        }

        var seconds: Int? {
            var total = duration
            var end = 0
            for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                let start = max(end, span.lowerBound)
                if span.upperBound > start { total += Double(span.upperBound - start) }
                end = max(end, span.upperBound)
            }
            guard let seconds = Int(exactly: (total / 1_000).rounded(.down)), seconds > 0 else { return nil }
            return seconds
        }
    }

    struct Tests {
        private var ordinal = 0
        private var outcome: SessionTestResult?

        struct Attempt {
            fileprivate let ordinal: Int
            fileprivate let shape: Command.Shape
        }

        mutating func start(_ rawCommand: Any?) -> Attempt? {
            guard let shape = Command.shape(rawCommand) else { return nil }
            ordinal += 1
            outcome = nil
            return Attempt(ordinal: ordinal, shape: shape)
        }

        mutating func finish(_ attempt: Attempt, exitCode: Int?) {
            // 126/127 and signal statuses report a launch failure or interruption, not a test outcome.
            guard attempt.ordinal == ordinal, let exitCode, (0..<126).contains(exitCode) else { return }
            switch attempt.shape {
            case .direct: outcome = exitCode == 0 ? .passed : .failed
            case .afterCD: if exitCode == 0 { outcome = .passed }
            case .uncertain: break
            }
        }

        func result(complete: Bool) -> SessionTestResult? {
            ordinal == 0 && complete ? .notRun : outcome
        }
    }

    fileprivate enum Command {
        enum Shape { case direct, afterCD, uncertain }

        static func shape(_ command: Any?, depth: Int = 0) -> Shape? {
            guard depth < 3 else { return .uncertain }
            if let argv = command as? [String] { return invocation(argv, depth: depth) }
            guard let raw = command as? String, !raw.isEmpty, raw.utf8.count <= 16_384,
                  let script = split(raw) else { return .uncertain }
            let calls = script.commands.map { invocation($0, depth: depth) }
            guard calls.contains(where: { $0 != nil }) else { return script.hiddenCalls ? .uncertain : nil }
            // shortcut: the final exit status cannot identify a test in a pipeline or arbitrary shell chain.
            if script.opaque { return .uncertain }
            if script.commands.count == 1 { return calls[0] }
            if script.commands.count == 2, script.separators == ["&&"],
               script.commands[0].first == "cd", calls[1] == .direct { return .afterCD }
            return .uncertain
        }

        private static func invocation(_ words: [String], depth: Int) -> Shape? {
            var args = words[...]
            if args.first == "env" { args = args.dropFirst() }
            while let first = args.first, first.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil {
                args = args.dropFirst()
            }
            if let first = args.first, ["command", "--"].contains(first) { args = args.dropFirst() }
            guard let word = args.popFirst(), let name = word.split(separator: "/").last.map(String.init) else { return nil }
            let command = args.first
            if ["sh", "bash", "zsh", "dash"].contains(name) {
                guard args.count == 2, let flag = command, ["-c", "-lc", "-cl"].contains(flag) else { return .uncertain }
                return shape(args.last, depth: depth + 1)
            }
            let nonRunning: Set<String> = ["--help", "-h", "--version", "--dry-run", "--no-run", "--collect-only", "--co",
                                           "--listTests", "--list-tests", "--showConfig", "-list", "--just-print", "--recon"]
            if args.contains(where: { nonRunning.contains($0) || $0.hasPrefix("-list=") }) { return nil }
            switch name {
            case "swift", "go", "cargo", "make", "gmake":
                if ["go", "make", "gmake"].contains(name) { args = droppingOptions(args, withValue: ["-C"]) }
                if name == "cargo", args.first?.hasPrefix("+") == true { args = args.dropFirst() }
                if ["make", "gmake"].contains(name), args.contains("-n") { return nil }
                return args.first == "test" && !(name == "swift" && args.dropFirst().first == "list") ? .direct : nil
            case "pytest", "jest", "vitest":
                return name == "vitest" && command == "list" ? nil : .direct
            case "npm", "pnpm", "yarn":
                args = droppingOptions(args, withValue: ["--prefix", "--cwd", "--dir"])
                if args.first == "test" { return .direct }
                guard let subcommand = args.popFirst() else { return nil }
                if subcommand == "run", args.first == "test" { return .direct }
                if subcommand == "exec" || (name == "yarn" && subcommand == "run") {
                    if args.first == "--" { args = args.dropFirst() }
                    return args.first.map { ["jest", "vitest"].contains($0) } == true ? invocation(Array(args), depth: depth) : nil
                }
                return name == "yarn" && ["jest", "vitest"].contains(subcommand) ? .direct : nil
            case "npx", "bunx":
                while let option = args.first, ["-y", "--yes", "--no", "--offline", "--quiet", "--"].contains(option) { args = args.dropFirst() }
                return args.first.map { ["jest", "vitest"].contains($0) } == true ? invocation(Array(args), depth: depth) : nil
            case "uv", "poetry":
                return args.prefix(2).elementsEqual(["run", "pytest"]) ? .direct : nil
            case "python", "python3":
                return args.prefix(2).elementsEqual(["-m", "pytest"]) ? .direct : nil
            default: return nil
            }
        }

        private static func droppingOptions(_ input: ArraySlice<String>, withValue: Set<String>) -> ArraySlice<String> {
            var args = input
            while let first = args.first, withValue.contains(first), args.count >= 2 { args = args.dropFirst(2) }
            return args
        }

        private static func split(_ script: String) -> (commands: [[String]], separators: [String], opaque: Bool, hiddenCalls: Bool)? {
            var commands: [[String]] = []
            var separators: [String] = []
            var words: [String] = []
            var word = ""
            var hasWord = false
            var quote: Character?
            var escaped = false
            var comment = false
            var opaque = false
        var hiddenCalls = false
            func flush() {
                if hasWord { words.append(word); word = ""; hasWord = false }
            }
            var iterator = script.makeIterator()
            var next = iterator.next()
            while let ch = next {
                next = iterator.next()
                if comment, !ch.isNewline { continue }
                comment = false
                if escaped { if !ch.isNewline { word.append(ch); hasWord = true }; escaped = false; continue }
                if ch == "\\", quote != "'" { escaped = true; continue }
                if let current = quote {
                    if ch == current { quote = nil }
                    else {
                        if current == "\"", ch == "`" || (ch == "$" && next == "(") { hiddenCalls = true }
                        word.append(ch)
                    }
                    continue
                }
                if ch == "#", !hasWord { comment = true; continue }
                if ch == "\"" || ch == "'" { quote = ch; hasWord = true; continue }
                if ch.isNewline || ";&|".contains(ch) {
                    flush()
                    if !words.isEmpty { commands.append(words); words = [] }
                    var separator = String(ch)
                    if (ch == "&" || ch == "|"), next == ch { separator.append(ch); next = iterator.next() }
                    separators.append(separator)
                } else if ch.isWhitespace {
                    flush()
                } else {
                    if "()`{}".contains(ch) { hiddenCalls = true }
                    if "<>".contains(ch) { opaque = true }
                    word.append(ch)
                    hasWord = true
                }
            }
            guard quote == nil, !escaped else { return nil }
            flush()
            if !words.isEmpty { commands.append(words) }
            if commands.count == 1, separators.contains(where: { $0 == "&" || $0 == "|" || $0 == "||" || $0 == "&&" }) {
                opaque = true
            }
            return (commands, separators, opaque || hiddenCalls, hiddenCalls)
        }
    }
}
