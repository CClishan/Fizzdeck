import Foundation

struct LibraryQuery: Equatable, Hashable, Sendable {
    var group: String? = nil
    var color: TagColor? = nil
    var tool: String? = nil
    var framework: String? = nil
    var starredOnly = false
    var dirtyOnly = false
    var runningOnly = false
    var hasSessionsOnly = false
    var unpushedOnly = false
    var commitDayKey: String? = nil
    var searchText = ""

    var hasActiveFilters: Bool {
        group != nil
            || color != nil
            || tool != nil
            || framework != nil
            || starredOnly
            || dirtyOnly
            || runningOnly
            || hasSessionsOnly
            || unpushedOnly
            || commitDayKey != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func clearFilters() {
        group = nil
        color = nil
        tool = nil
        framework = nil
        starredOnly = false
        dirtyOnly = false
        runningOnly = false
        hasSessionsOnly = false
        unpushedOnly = false
        commitDayKey = nil
        searchText = ""
    }
}

enum AppDestination: Equatable, Hashable, Sendable {
    case dashboard
    case library(LibraryQuery = LibraryQuery())
    case cleanup
    case project(String)

    var isDashboard: Bool {
        if case .dashboard = self { return true }
        return false
    }

    var isLibrary: Bool {
        if case .library = self { return true }
        return false
    }

    var isCleanup: Bool {
        if case .cleanup = self { return true }
        return false
    }

    var libraryQuery: LibraryQuery? {
        if case let .library(query) = self { return query }
        return nil
    }

    var projectPath: String? {
        if case let .project(path) = self { return path }
        return nil
    }
}
