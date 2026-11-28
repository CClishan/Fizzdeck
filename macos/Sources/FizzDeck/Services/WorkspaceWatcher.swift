import AppKit
import CoreServices
import Foundation

enum WorkspaceChange: Hashable, Sendable {
    case sessions
    case git
    case manifest(String)
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
        ".dsh/storages/session_projcache/sessions",
        ".gemini/antigravity/brain",
        CursorSessionReader.projectsPath,
        CursorSessionReader.workspacesPath,
        OpenCodeSessionReader.storagePath,
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
    private let extendWindow: Bool
    private let action: (WorkspaceChange) -> Void
    private var pending: Set<WorkspaceChange> = []
    private var timer: Timer?

    init(interval: TimeInterval, extendWindow: Bool = true, action: @escaping (WorkspaceChange) -> Void) {
        self.interval = interval
        self.extendWindow = extendWindow
        self.action = action
    }

    func schedule(_ change: WorkspaceChange) {
        scheduledCount += 1
        pending.insert(change)
        if !extendWindow, timer != nil { return }
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
        for case let .manifest(path) in changes { action(.manifest(path)) }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pending.removeAll()
    }

    func discard(_ change: WorkspaceChange) { pending.remove(change) }
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
    private let inputDebouncer: WorkspaceDebouncer
    private var sessionStream: WatcherStream?
    private var gitStream: WatcherStream?
    private(set) var focusedPaths: Set<String> = []
    private var inputStreams: [String: WatcherStream] = [:]
    private struct FileStamp: Equatable, Sendable {
        let inode: ino_t, seconds: Int, nanos: Int, size: off_t
        init?(_ file: String) {
            var info = stat()
            guard lstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
            inode = info.st_ino; seconds = info.st_mtimespec.tv_sec; nanos = info.st_mtimespec.tv_nsec; size = info.st_size
        }
    }
    private var gitFileStamps: [FileStamp?] = []

    private func gitStamps(in gitDirectory: URL) -> [FileStamp?] {
        ["HEAD", "index"].map { FileStamp(gitDirectory.appendingPathComponent($0).path) }
    }
    private var inputFiles: [String: [String: FileStamp]] = [:]
    private var directorySources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingDirectoryChecks: [String: Task<Void, Never>] = [:]
    private var inputReads: [String: Task<Void, Never>] = [:]
    private var watchedSessionRoots: [String] = []
    private var missingRootTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var wasActive = false
    private let onActivation: () -> Void

    init(
        homeDirectory: URL = AppPaths.home,
        sessionRoots: [String] = WorkspaceWatchPaths.sessionRoots,
        debounceInterval: TimeInterval = 2,
        onActivation: @escaping () -> Void = {},
        onChange: @escaping (WorkspaceChange) -> Void
    ) {
        self.homeDirectory = homeDirectory
        self.onActivation = onActivation
        sessionRootNames = sessionRoots
        debouncer = WorkspaceDebouncer(interval: debounceInterval, action: onChange)
        inputDebouncer = WorkspaceDebouncer(interval: debounceInterval, extendWindow: false, action: onChange)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isPaused = false
        startSessionWatch()
        startGitWatch()
        for path in focusedPaths { startInputWatch(path) }
        startLifecycleObservers()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        isPaused = false
        debouncer.cancel()
        inputDebouncer.cancel()
        missingRootTimer?.invalidate()
        missingRootTimer = nil
        stopStream(&sessionStream)
        stopStream(&gitStream)
        stopInputWatches()
        focusedPaths.removeAll()
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
        debouncer.discard(.git)
        gitPath = normalized
        startGitWatch()
    }

    // One shallow vnode source discovers top-level creates/deletes; FSEvents subscribes only to named files.
    func setFocusedPaths(_ orderedPaths: [String]) {
        let next = Set(orderedPaths.prefix(ProjectFocusPolicy.defaultMaxFocused))
        let added = next.subtracting(focusedPaths)
        for path in focusedPaths.subtracting(next) { stopInputWatch(path) }
        focusedPaths = next
        guard isStarted, !isPaused else { return }
        for path in added { startInputWatch(path) }
    }

    private func startInputWatch(_ path: String) {
        let fd = open(path, O_EVTONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { inputDebouncer.schedule(.manifest(path)); return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in self?.scheduleDirectoryCheck(path) }
        directorySources[path] = source
        source.resume()
        updateInputFiles(path)
    }

    private func scheduleDirectoryCheck(_ path: String) {
        guard focusedPaths.contains(path), !isPaused, pendingDirectoryChecks[path] == nil else { return }
        pendingDirectoryChecks[path] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            pendingDirectoryChecks[path] = nil
            updateInputFiles(path)
        }
    }

    private func updateInputFiles(_ path: String) {
        inputReads[path]?.cancel()
        inputReads[path] = Task { [weak self] in
            let files = await Task.detached(priority: .utility) { Self.readInputFiles(path) }.value
            guard let self, !Task.isCancelled else { return }
            inputReads[path] = nil
            guard files != inputFiles[path] else { return }
            inputFiles[path] = files
            inputStreams[path] = files.isEmpty ? nil : makeStream(paths: files.keys.sorted(), change: .manifest(path))
            inputDebouncer.schedule(.manifest(path))
        }
    }

    private nonisolated static func readInputFiles(_ path: String) -> [String: FileStamp] {
        let root = URL(fileURLWithPath: PathTools.canonical(path))
        var files: [String: FileStamp] = [:]
        for name in DoctorInputs.manifests.union(DoctorInputs.envNames(in: root)) {
            let file = root.appendingPathComponent(name).path
            files[file] = FileStamp(file)
        }
        return files
    }

    private func stopInputWatch(_ path: String) {
        inputDebouncer.discard(.manifest(path))
        pendingDirectoryChecks.removeValue(forKey: path)?.cancel()
        inputReads.removeValue(forKey: path)?.cancel()
        directorySources.removeValue(forKey: path)?.cancel()
        inputStreams[path] = nil
        inputFiles[path] = nil
    }

    private func stopInputWatches() {
        for path in focusedPaths { stopInputWatch(path) }
    }

    func pause() {
        guard isStarted, !isPaused else { return }
        isPaused = true
        debouncer.cancel()
        inputDebouncer.cancel()
        missingRootTimer?.invalidate()
        missingRootTimer = nil
        stopStream(&sessionStream)
        stopStream(&gitStream)
        stopInputWatches()
    }

    func resume() {
        guard isStarted, isPaused else { return }
        isPaused = false
        startSessionWatch()
        startGitWatch()
        debouncer.schedule(.sessions)
        debouncer.schedule(.git)
        for path in focusedPaths {
            startInputWatch(path)
        }
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
        gitFileStamps = gitStamps(in: gitDirectory)
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
        debouncer.schedule(.sessions)
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
                guard let self, self.isStarted else { return }
                self.wasActive = true
                self.resume()
                self.onActivation()
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

    func handleEventPaths(_ paths: [String], change: WorkspaceChange) {
        guard isStarted, !isPaused else { return }
        switch change {
        case .sessions:
            guard paths.isEmpty || paths.contains(where: { !$0.hasSuffix("/opencode.db-shm") }) else { return }
            debouncer.schedule(.sessions)
        case .git:
            guard let gitPath, paths.contains(where: { WorkspaceWatchPaths.touchesGit(path: $0, gitPath: gitPath) }) else {
                return
            }
            // A newly attached stream can still deliver a coalesced HEAD/index event from before attachment.
            let stamps = gitStamps(in: URL(fileURLWithPath: gitPath).appendingPathComponent(".git"))
            guard stamps != gitFileStamps else { return }
            gitFileStamps = stamps
            debouncer.schedule(.git)
        case .manifest(let path):
            // FSEvents may deliver an older coalesced event just after a stream is attached.
            // Compare file identity/mtime so subscribing or touching a sibling cannot schedule a diagnosis.
            for raw in paths {
                let file = PathTools.canonical(raw)
                guard let old = inputFiles[path]?[file], let new = FileStamp(file), old != new else { continue }
                if old.inode != new.inode { scheduleDirectoryCheck(path) }
                else {
                    inputFiles[path]?[file] = new
                    inputDebouncer.schedule(.manifest(path))
                }
            }
        }
    }

    private func stopStream(_ stream: inout WatcherStream?) {
        stream = nil
    }
}
