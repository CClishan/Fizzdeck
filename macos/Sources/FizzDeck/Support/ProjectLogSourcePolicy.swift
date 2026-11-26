import Foundation

enum ProjectLogSource: String, CaseIterable, Identifiable {
    case dev
    case test

    var id: String { rawValue }
    var title: String { rawValue }
}

struct ProjectLogContext: Equatable {
    var projectPath: String
    var testStartedAt: Date?
    var devAvailable: Bool
    var testAvailable: Bool
    var testActive: Bool
}

enum ProjectLogSourcePolicy {
    static func resolve(
        current: ProjectLogContext,
        previous: ProjectLogContext?,
        selected: ProjectLogSource
    ) -> ProjectLogSource {
        guard let previous, previous.projectPath == current.projectPath else {
            return initialSource(for: current)
        }

        if let startedAt = current.testStartedAt,
           startedAt != previous.testStartedAt,
           current.testAvailable || current.testActive {
            return .test
        }

        return normalized(selected, for: current)
    }

    static func initialSource(for context: ProjectLogContext) -> ProjectLogSource {
        if context.testActive { return .test }
        if context.devAvailable { return .dev }
        if context.testAvailable { return .test }
        return .dev
    }

    static func normalized(
        _ source: ProjectLogSource,
        for context: ProjectLogContext
    ) -> ProjectLogSource {
        switch source {
        case .dev where !context.devAvailable && (context.testAvailable || context.testActive):
            return .test
        case .test where !(context.testAvailable || context.testActive) && context.devAvailable:
            return .dev
        default:
            return source
        }
    }
}
