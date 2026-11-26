import AppKit
import CoreServices
import Foundation

enum WorkspaceChange: String, Sendable {
    case sessions
    case git
}

private func workspaceEventCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let pointer = Unmanaged<WorkspaceEventSink>.fromOpaque(info)
    let sink = pointer.takeUnretainedValue()
    let change = sink.change
    let watcher = sink.watcher
    let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray)
        .compactMap { $0 as? String }
    Task { @MainActor [watcher] in
        guard let watcher else { return }
        watcher.handleEventPaths(paths, change: change)
    }
}

private final class WorkspaceEventSink: @unchecked Sendable {
    let change: WorkspaceChange
    weak var watcher: WorkspaceWatcher?

    init(change: WorkspaceChange, watcher: WorkspaceWatcher) {
        self.change = change
        self.watcher = watcher
    }
}

enum WorkspaceWatchPaths {
    static let sessionRoots = [
        ".codex/sessions",
        ".claude/projects",
        ".grok/sessions",
        ".gemini/tmp",
    ]

    static func touchesGit(path: String, gitPath: String?) -> Bool {
        guard let gitPath else { return false }
        let prefix = PathTools.canonical(gitPath) + "/.git/"
        let canonical = PathTools.canonical(path)
        guard canonical.hasPrefix(prefix) else { return false }
        let name = String(canonical.dropFirst(prefix.count))
        return name == "HEAD" || name == "index"
    }
}

@MainActor
final class WorkspaceDebouncer {
    private(set) var scheduledCount = 0
    private let interval: TimeInterval
    private let action: (WorkspaceChange) -> Void
    private var pending: Set<WorkspaceChange> = []
    private var timer: Timer?

    init(interval: TimeInterval, action: @escaping (WorkspaceChange) -> Void) {
        self.interval = interval
        self.action = action
    }

    func schedule(_ change: WorkspaceChange) {
        scheduledCount += 1
        pending.insert(change)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }

    func flush() {
        timer?.invalidate()
        timer = nil
        let changes = pending
        pending.removeAll()
        if changes.contains(.sessions) {
            action(.sessions)
        }
        if changes.contains(.git) {
            action(.git)
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pending.removeAll()
    }
}

@MainActor
final class WorkspaceWatcher {
    private final class WatcherStream {
        let stream: FSEventStreamRef
        private let retainedSink: Unmanaged<WorkspaceEventSink>

        init(stream: FSEventStreamRef, sink: Unmanaged<WorkspaceEventSink>) {
            self.stream = stream
            retainedSink = sink
        }

        deinit {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            retainedSink.release()
        }
    }

    private(set) var isStarted = false
    private(set) var isPaused = false
    private(set) var gitPath: String?

    private let homeDirectory: URL
    private let sessionRootNames: [String]
    private let debouncer: WorkspaceDebouncer
    private var sessionStream: WatcherStream?
    private var gitStream: WatcherStream?
    private var watchedSessionRoots: [String] = []
    private var missingRootTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var wasActive = false

    init(
        homeDirectory: URL = AppPaths.home,
        sessionRoots: [String] = WorkspaceWatchPaths.sessionRoots,
        debounceInterval: TimeInterval = 2,
        onChange: @escaping (WorkspaceChange) -> Void
    ) {
        self.homeDirectory = homeDirectory
        sessionRootNames = sessionRoots
        debouncer = WorkspaceDebouncer(interval: debounceInterval, action: onChange)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isPaused = false
        startSessionWatch()
        startGitWatch()
        startLifecycleObservers()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        isPaused = false
        debouncer.cancel()
        missingRootTimer?.invalidate()
        missingRootTimer = nil
        stopStream(&sessionStream)
        stopStream(&gitStream)
        watchedSessionRoots = []
        gitPath = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func setGitPath(_ path: String?) {
        let normalized = path.map(PathTools.normalize)
        guard normalized != gitPath else { return }
        gitPath = normalized
        startGitWatch()
    }

    func pause() {
        guard isStarted, !isPaused else { return }
        isPaused = true
        debouncer.cancel()
        missingRootTimer?.invalidate()
        missingRootTimer = nil
        stopStream(&sessionStream)
        stopStream(&gitStream)
    }

    func resume() {
        guard isStarted, isPaused else { return }
        isPaused = false
        startSessionWatch()
        startGitWatch()
        debouncer.schedule(.sessions)
        debouncer.schedule(.git)
    }

    private func startSessionWatch() {
        guard !isPaused, sessionStream == nil else { return }
        let existing = sessionRootNames
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true).path }
            .filter { FileTools.isDirectory(URL(fileURLWithPath: $0)) }
        watchedSessionRoots = existing
        if !existing.isEmpty {
            sessionStream = makeStream(paths: existing, change: .sessions)
        }
        if existing.count < sessionRootNames.count {
            scheduleMissingRootCheck()
        }
    }

    private func startGitWatch() {
        stopStream(&gitStream)
        guard isStarted, !isPaused, let gitPath else { return }
        let gitDirectory = URL(fileURLWithPath: gitPath).appendingPathComponent(".git", isDirectory: true)
        guard FileTools.isDirectory(gitDirectory) else { return }
        gitStream = makeStream(paths: [gitDirectory.path], change: .git)
    }

    private func scheduleMissingRootCheck() {
        missingRootTimer?.invalidate()
        missingRootTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recheckMissingRoots()
            }
        }
    }

    private func recheckMissingRoots() {
        guard isStarted, !isPaused else { return }
        let existing = sessionRootNames
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true).path }
            .filter { FileTools.isDirectory(URL(fileURLWithPath: $0)) }
        guard existing.count > watchedSessionRoots.count else { return }
        missingRootTimer?.invalidate()
        missingRootTimer = nil
        stopStream(&sessionStream)
        startSessionWatch()
    }

    private func startLifecycleObservers() {
        wasActive = NSApplication.shared.isActive
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.wasActive = true
                self.resume()
            }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // A process launched in the background never had a foreground
                // session to pause; keep watching until the first real resign.
                guard self.wasActive else { return }
                self.wasActive = false
                self.pause()
            }
        })
    }

    private func makeStream(paths: [String], change: WorkspaceChange) -> WatcherStream? {
        let retained = Unmanaged.passRetained(WorkspaceEventSink(change: change, watcher: self))
        let context = retained.toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: { info in
                guard let info else { return nil }
                let pointer = Unmanaged<WorkspaceEventSink>.fromOpaque(info)
                _ = pointer.retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<WorkspaceEventSink>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = workspaceEventCallback
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &streamContext,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            retained.release()
            return nil
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            retained.release()
            return nil
        }
        return WatcherStream(stream: stream, sink: retained)
    }

    fileprivate func handleEventPaths(_ paths: [String], change: WorkspaceChange) {
        switch change {
        case .sessions:
            debouncer.schedule(.sessions)
        case .git:
            guard paths.contains(where: { WorkspaceWatchPaths.touchesGit(path: $0, gitPath: gitPath) }) else {
                return
            }
            debouncer.schedule(.git)
        }
    }

    private func stopStream(_ stream: inout WatcherStream?) {
        stream = nil
    }
}
