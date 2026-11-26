import AppKit
import CryptoKit
import Foundation
import Observation
import SwiftUI

struct AppReleaseAsset: Sendable, Equatable {
    let name: String
    let downloadURL: URL
    let size: Int64
}

struct AppRelease: Sendable, Equatable {
    let version: String
    let pageURL: URL
    let dmgAsset: AppReleaseAsset?
    let checksumAsset: AppReleaseAsset?
}

enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发版"
    }

    static var display: String {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              build != "0"
        else {
            return short
        }
        return "\(short) (\(build))"
    }
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case downloading(progress: Double, receivedBytes: Int64, totalBytes: Int64)
    case verifying
    case readyToInstall(stagedAppURL: URL, dmgURL: URL)
    case installing
    case failed(String)
}

enum AppUpdateEvent: Equatable {
    case checkStarted
    case checkFinished(release: AppRelease?, isNewer: Bool)
    case downloadStarted(totalBytes: Int64)
    case downloadProgress(receivedBytes: Int64, totalBytes: Int64)
    case verifying
    case readyToInstall(stagedAppURL: URL, dmgURL: URL)
    case installStarted
    case failed(String)
    case downloadCancelled(AppRelease)
    case reset
}

struct AppUpdateStateMachine: Equatable {
    private(set) var state: AppUpdateState = .idle

    mutating func apply(_ event: AppUpdateEvent) {
        switch (state, event) {
        case (_, .checkStarted):
            state = .checking

        case (_, .checkFinished(let release, let isNewer)):
            if isNewer, let release {
                state = .available(release)
            } else {
                state = .upToDate
            }

        case (.available, .downloadStarted(let totalBytes)):
            state = .downloading(
                progress: 0,
                receivedBytes: 0,
                totalBytes: max(0, totalBytes)
            )

        case (.downloading(_, let received, let existingTotal), .downloadProgress(let nextReceived, let nextTotal)):
            let total = nextTotal > 0 ? nextTotal : existingTotal
            let received = max(received, max(0, nextReceived))
            let progress = total > 0
                ? min(1, max(0, Double(received) / Double(total)))
                : 0
            state = .downloading(
                progress: progress,
                receivedBytes: received,
                totalBytes: total
            )

        case (.downloading, .verifying):
            state = .verifying

        case (.verifying, .readyToInstall(let stagedAppURL, let dmgURL)):
            state = .readyToInstall(stagedAppURL: stagedAppURL, dmgURL: dmgURL)

        case (.readyToInstall, .installStarted):
            state = .installing

        case (_, .failed(let message)):
            state = .failed(message)

        case (.downloading, .downloadCancelled(let release)):
            state = .available(release)

        case (_, .reset):
            state = .idle

        default:
            break
        }
    }
}

enum AppUpdateService {
    static let bundleIdentifier = "com.a003.fizzdeck"

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/CClishan/Fizzdeck/releases/latest"
    )!

    static func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FizzDeck/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode
        else {
            throw AppUpdateError.invalidResponse
        }
        return try release(from: data)
    }

    static func release(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> AppRelease {
        let release: GitHubRelease
        do {
            release = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw AppUpdateError.invalidResponse
        }

        guard let pageURL = URL(string: release.htmlURL) else {
            throw AppUpdateError.invalidResponse
        }

        let assets = release.assets.compactMap { asset -> AppReleaseAsset? in
            guard let url = URL(string: asset.browserDownloadURL) else { return nil }
            return AppReleaseAsset(
                name: asset.name,
                downloadURL: url,
                size: max(0, asset.size)
            )
        }
        let dmgAsset = assets.first { isArm64DMG($0.name) }
        let checksumAsset = dmgAsset.flatMap { dmg in
            assets.first {
                $0.name.lowercased() == "\(dmg.name).sha256".lowercased()
            } ?? assets.first {
                looksLikeSHA256Asset($0.name)
            }
        }

        return AppRelease(
            version: normalizedVersion(release.tagName),
            pageURL: pageURL,
            dmgAsset: dmgAsset,
            checksumAsset: checksumAsset
        )
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(candidate)
        let currentParts = numericParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    static func updatesDirectory(fileManager: FileManager = .default) throws -> URL {
        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cacheRoot
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func download(
        _ release: AppRelease,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        guard let asset = release.dmgAsset else {
            throw AppUpdateError.missingDMG
        }

        let directory = try updatesDirectory()
        let destination = directory.appendingPathComponent(
            URL(fileURLWithPath: asset.name).lastPathComponent
        )
        let partial = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.removeItem(at: partial)

        let coordinator = DownloadCoordinator(
            request: downloadRequest(for: asset),
            destination: partial,
            expectedBytes: asset.size,
            progress: progress
        )
        let downloaded = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.start(continuation: continuation)
            }
        } onCancel: {
            coordinator.cancel()
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: downloaded, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: downloaded)
            throw AppUpdateError.downloadFailed(error.localizedDescription)
        }
    }

    static func verifyChecksum(
        for fileURL: URL,
        checksumAsset: AppReleaseAsset?
    ) async throws {
        guard let checksumAsset else { return }
        var request = URLRequest(url: checksumAsset.downloadURL)
        request.timeoutInterval = 15
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue("FizzDeck/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let text = String(data: data, encoding: .utf8),
              let expected = SHA256Verifier.expectedDigest(in: text)
        else {
            try? FileManager.default.removeItem(at: fileURL)
            throw AppUpdateError.invalidChecksum
        }

        let actual: String
        do {
            actual = try SHA256Verifier.digestHex(for: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw AppUpdateError.checksumReadFailed(error.localizedDescription)
        }

        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            try? FileManager.default.removeItem(at: fileURL)
            throw AppUpdateError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    static func stageVerifiedApp(from dmgURL: URL) async throws -> URL {
        let directory = try updatesDirectory()
        let stagingRoot = directory.appendingPathComponent(
            "staging-\(UUID().uuidString)",
            isDirectory: true
        )
        return try await Task.detached(priority: .userInitiated) {
            try stageVerifiedAppSync(from: dmgURL, stagingRoot: stagingRoot)
        }.value
    }

    static func installPlan(
        bundleURL: URL,
        isWritable: (URL) -> Bool
    ) -> AppInstallPlan {
        let target = bundleURL.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension.lowercased() == "app" else {
            return AppInstallPlan(
                appURL: target,
                parentURL: parent,
                canInstallInPlace: false,
                reason: "当前是开发运行，无法原地替换应用。"
            )
        }
        guard isWritable(parent) else {
            return AppInstallPlan(
                appURL: target,
                parentURL: parent,
                canInstallInPlace: false,
                reason: "应用所在目录不可写，无法自动安装。"
            )
        }
        return AppInstallPlan(
            appURL: target,
            parentURL: parent,
            canInstallInPlace: true,
            reason: nil
        )
    }

    static func launchInstallerHelper(
        stagedAppURL: URL,
        targetAppURL: URL,
        waitingForPID pid: pid_t
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try launchInstallerHelperSync(
                stagedAppURL: stagedAppURL,
                targetAppURL: targetAppURL,
                waitingForPID: pid
            )
        }.value
    }

    private static func downloadRequest(for asset: AppReleaseAsset) -> URLRequest {
        var request = URLRequest(url: asset.downloadURL)
        request.timeoutInterval = 60
        request.setValue("FizzDeck/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func isArm64DMG(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasSuffix(".dmg")
            && value.contains("arm64")
            && !value.hasSuffix(".dmg.sha256")
    }

    private static func looksLikeSHA256Asset(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasSuffix(".dmg.sha256") && value.contains("arm64")
    }

    private static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.drop(while: { $0 == "v" || $0 == "V" }))
    }

    private static func numericParts(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { part in
                Int(part.prefix(while: \.isNumber)) ?? 0
            }
    }

    private static func stageVerifiedAppSync(
        from dmgURL: URL,
        stagingRoot: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: stagingRoot)
        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )

        let mount = try attachDMG(dmgURL)
        var mounted = true
        defer {
            if mounted {
                _ = try? detachDMG(mount)
            }
        }

        let mountedApp = mount.appendingPathComponent("FizzDeck.app", isDirectory: true)
        guard fileManager.fileExists(atPath: mountedApp.path) else {
            throw AppUpdateError.appNotFoundInDMG
        }
        guard let bundle = Bundle(url: mountedApp),
              bundle.bundleIdentifier == bundleIdentifier
        else {
            throw AppUpdateError.bundleIdentifierMismatch
        }

        let signature = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", mountedApp.path]
        )
        guard signature.status == 0 else {
            throw AppUpdateError.signatureInvalid(signature.combinedOutput)
        }

        let stagedApp = stagingRoot.appendingPathComponent("FizzDeck.app", isDirectory: true)
        do {
            try fileManager.copyItem(at: mountedApp, to: stagedApp)
        } catch {
            throw AppUpdateError.stagingFailed(error.localizedDescription)
        }

        let detachResult = try detachDMG(mount)
        mounted = false
        guard detachResult.status == 0 else {
            try? fileManager.removeItem(at: stagingRoot)
            throw AppUpdateError.unmountFailed(detachResult.combinedOutput)
        }

        let stagedSignature = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", stagedApp.path]
        )
        guard stagedSignature.status == 0 else {
            try? fileManager.removeItem(at: stagingRoot)
            throw AppUpdateError.signatureInvalid(stagedSignature.combinedOutput)
        }
        return stagedApp
    }

    private static func attachDMG(_ dmgURL: URL) throws -> URL {
        let result = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: [
                "attach",
                "-readonly",
                "-nobrowse",
                "-noverify",
                "-plist",
                dmgURL.path,
            ]
        )
        guard result.status == 0,
              let plist = try? PropertyListSerialization.propertyList(
                from: result.stdout,
                options: [],
                format: nil
              ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw AppUpdateError.mountFailed(result.combinedOutput)
        }
        return URL(fileURLWithPath: mountPath, isDirectory: true)
    }

    private static func detachDMG(_ mountURL: URL) throws -> ProcessResult {
        let result = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountURL.path]
        )
        guard result.status != 0 else { return result }

        return try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["detach", "-force", mountURL.path]
        )
    }

    private static func launchInstallerHelperSync(
        stagedAppURL: URL,
        targetAppURL: URL,
        waitingForPID pid: pid_t
    ) throws -> URL {
        let fileManager = FileManager.default
        let parent = targetAppURL.deletingLastPathComponent()
        let updates = try updatesDirectory()
        let staging = parent.appendingPathComponent(
            ".FizzDeck-update-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )

        let stagedInPlace = staging.appendingPathComponent("FizzDeck.app", isDirectory: true)
        do {
            try fileManager.copyItem(at: stagedAppURL, to: stagedInPlace)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw AppUpdateError.stagingFailed(error.localizedDescription)
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let backup = parent.appendingPathComponent(
            ".FizzDeck-backup-\(timestamp)-\(UUID().uuidString.prefix(6)).app",
            isDirectory: true
        )
        let script = updates.appendingPathComponent("install-\(UUID().uuidString).sh")
        let log = updates.appendingPathComponent("install.log")
        let scriptBody = #"""
#!/bin/sh
set -u

pid="$1"
staged="$2"
target="$3"
backup="$4"
log="$5"

exec >>"$log" 2>&1
printf '\n[%s] waiting for pid %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$pid"

while kill -0 "$pid" 2>/dev/null; do
  /bin/sleep 0.2
done

if [ -e "$target" ]; then
  /bin/mv "$target" "$backup" || exit 10
fi

if /bin/mv "$staged" "$target"; then
  /bin/rm -rf "$backup"
  /usr/bin/open -n "$target"
  exit 0
fi

if [ -e "$backup" ] && [ ! -e "$target" ]; then
  /bin/mv "$backup" "$target"
fi
/usr/bin/open -n "$target" 2>/dev/null || true
exit 11
"""#

        do {
            try scriptBody.write(to: script, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: script.path
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                script.path,
                String(pid),
                stagedInPlace.path,
                targetAppURL.path,
                backup.path,
                log.path,
            ]
            process.standardInput = FileHandle.nullDevice
            try process.run()
            return log
        } catch {
            try? fileManager.removeItem(at: staging)
            throw AppUpdateError.installerLaunchFailed(error.localizedDescription)
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: String
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}

struct AppInstallPlan: Equatable, Sendable {
    let appURL: URL
    let parentURL: URL
    let canInstallInPlace: Bool
    let reason: String?
}

enum SHA256Verifier {
    static func digestHex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func expectedDigest(in text: String) -> String? {
        let token = text
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased()
        guard let token, token.count == 64 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return token
    }
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case missingDMG
    case downloadFailed(String)
    case invalidChecksum
    case checksumReadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case mountFailed(String)
    case appNotFoundInDMG
    case bundleIdentifierMismatch
    case signatureInvalid(String)
    case stagingFailed(String)
    case unmountFailed(String)
    case installerLaunchFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "暂时无法获取最新版本"
        case .missingDMG:
            "这个版本没有可用的 arm64 DMG"
        case .downloadFailed(let detail):
            "下载失败：\(detail)"
        case .invalidChecksum:
            "校验文件格式不正确"
        case .checksumReadFailed(let detail):
            "读取更新文件失败：\(detail)"
        case .checksumMismatch:
            "SHA-256 不匹配，已删除下载文件"
        case .mountFailed:
            "无法挂载下载的 DMG"
        case .appNotFoundInDMG:
            "DMG 中没有 FizzDeck.app"
        case .bundleIdentifierMismatch:
            "DMG 中的应用标识不匹配"
        case .signatureInvalid:
            "应用签名校验失败"
        case .stagingFailed(let detail):
            "准备安装文件失败：\(detail)"
        case .unmountFailed:
            "无法安全卸载 DMG"
        case .installerLaunchFailed(let detail):
            "无法启动安装助手：\(detail)"
        case .cancelled:
            "下载已取消"
        }
    }
}

@MainActor
@Observable
final class AppUpdateController {
    private(set) var state: AppUpdateState = .idle
    private(set) var notice: String?

    private var machine = AppUpdateStateMachine()
    private var downloadTask: Task<Void, Never>?
    private var pendingRelease: AppRelease?
    private var updateToastID: UUID?

    init() {}

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .verifying, .installing:
            true
        case .idle, .upToDate, .available, .readyToInstall, .failed:
            false
        }
    }

    func check() async {
        guard downloadTask == nil else { return }
        apply(.checkStarted)
        do {
            let release = try await AppUpdateService.latestRelease()
            pendingRelease = release
            apply(.checkFinished(
                release: release,
                isNewer: AppUpdateService.isNewer(release.version, than: AppVersion.short)
            ))
        } catch {
            apply(.failed(error.localizedDescription))
        }
    }

    func startDownload() {
        guard case .available(let release) = state, downloadTask == nil else { return }
        pendingRelease = release
        apply(.downloadStarted(totalBytes: release.dmgAsset?.size ?? 0))
        guard case .downloading = state else { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            let controller = self
            do {
                let dmgURL = try await AppUpdateService.download(release) { [controller] received, total in
                    Task { @MainActor in
                        controller.apply(.downloadProgress(
                            receivedBytes: received,
                            totalBytes: total
                        ))
                    }
                }
                try Task.checkCancellation()

                apply(.verifying)
                try await AppUpdateService.verifyChecksum(
                    for: dmgURL,
                    checksumAsset: release.checksumAsset
                )
                try Task.checkCancellation()

                let stagedApp = try await AppUpdateService.stageVerifiedApp(from: dmgURL)
                try Task.checkCancellation()
                apply(.readyToInstall(stagedAppURL: stagedApp, dmgURL: dmgURL))
            } catch is CancellationError {
                try? await Task.sleep(for: .milliseconds(60))
                apply(.downloadCancelled(release))
            } catch {
                if Task.isCancelled {
                    apply(.downloadCancelled(release))
                } else {
                    apply(.failed(error.localizedDescription))
                }
            }
            downloadTask = nil
        }
    }

    func cancelDownload() {
        guard case .downloading = state else { return }
        downloadTask?.cancel()
        if let pendingRelease {
            apply(.downloadCancelled(pendingRelease))
        }
    }

    func installAndRestart() async {
        guard case .readyToInstall(let stagedApp, let dmgURL) = state else { return }
        notice = nil
        let plan = AppUpdateService.installPlan(
            bundleURL: Bundle.main.bundleURL,
            isWritable: { FileManager.default.isWritableFile(atPath: $0.path) }
        )

        guard plan.canInstallInPlace else {
            openFallbackDMG(dmgURL, reason: plan.reason ?? "当前环境无法自动安装。")
            return
        }

        apply(.installStarted)
        do {
            _ = try await AppUpdateService.launchInstallerHelper(
                stagedAppURL: stagedApp,
                targetAppURL: plan.appURL,
                waitingForPID: getpid()
            )
            try await Task.sleep(for: .milliseconds(160))
            NSApplication.shared.terminate(nil)
        } catch {
            apply(.failed(error.localizedDescription))
            openFallbackDMG(dmgURL, reason: error.localizedDescription)
        }
    }

    func clearNotice() {
        notice = nil
    }

    private func openFallbackDMG(_ dmgURL: URL, reason: String) {
        NSWorkspace.shared.open(dmgURL)
        notice = "\(reason) 已打开校验后的 DMG，请手动拖入“应用程序”。"
    }

    private func apply(_ event: AppUpdateEvent) {
        let previous = state
        machine.apply(event)
        state = machine.state
        if previous != state {
            syncToast()
        }
    }

    private func syncToast() {
        switch state {
        case .idle, .checking, .upToDate:
            dismissUpdateToast()

        case .available(let release):
            upsertUpdateToast(
                title: "发现 FizzDeck v\(release.version)",
                subtitle: "可下载 arm64 DMG",
                microViz: .pipeline(step: 0, state: .live),
                tint: FizzTheme.accent,
                action: ToastAction(
                    title: "下载更新",
                    symbol: "arrow.down.circle"
                ) { [weak self] in
                    self?.startDownload()
                }
            )

        case .downloading(let progress, let received, let total):
            let version = pendingRelease.map { " v\($0.version)" } ?? ""
            let percent = Int((progress * 100).rounded())
            upsertUpdateToast(
                title: "正在下载更新\(version)",
                subtitle: "\(percent)% · \(Format.bytes(received)) / \(Format.bytes(total))",
                microViz: .pipeline(step: 0, state: .running),
                tint: FizzTheme.accent,
                action: nil
            )

        case .verifying:
            upsertUpdateToast(
                title: "正在校验更新",
                subtitle: "SHA-256 · Bundle ID · codesign",
                microViz: .pipeline(step: 1, state: .running),
                tint: FizzTheme.accent,
                action: nil
            )

        case .readyToInstall:
            upsertUpdateToast(
                title: "更新已就绪",
                subtitle: "校验通过，可安装并重启",
                microViz: .pipeline(step: 2, state: .live),
                tint: .green,
                action: ToastAction(
                    title: "安装并重启",
                    symbol: "arrow.triangle.2.circlepath"
                ) { [weak self] in
                    guard let self else { return }
                    Task { await self.installAndRestart() }
                }
            )

        case .installing:
            upsertUpdateToast(
                title: "正在安装更新",
                subtitle: "应用将自动重启",
                microViz: .pipeline(step: 3, state: .running),
                tint: FizzTheme.accent,
                action: nil
            )

        case .failed(let message):
            upsertUpdateToast(
                title: "更新失败",
                subtitle: message,
                microViz: .pipeline(step: 1, state: .failed),
                tint: .orange,
                action: ToastAction(
                    title: "重新检查",
                    symbol: "arrow.clockwise"
                ) { [weak self] in
                    guard let self else { return }
                    Task { await self.check() }
                }
            )
        }
    }

    private func upsertUpdateToast(
        title: String,
        subtitle: String?,
        microViz: ToastMicroViz,
        tint: Color,
        action: ToastAction?
    ) {
        if let updateToastID,
           ToastCenter.shared.update(updateToastID, mutate: { message in
               message.title = title
               message.subtitle = subtitle
               message.tint = tint
               message.microViz = microViz
               message.action = action
               message.duration = nil
           }) {
            return
        }

        updateToastID = ToastCenter.shared.show(
            title,
            symbol: "arrow.triangle.2.circlepath",
            tint: tint,
            duration: nil,
            subtitle: subtitle,
            microViz: microViz,
            action: action
        )
    }

    private func dismissUpdateToast() {
        guard let updateToastID else { return }
        ToastCenter.shared.dismiss(id: updateToastID)
        self.updateToastID = nil
    }
}

private struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var combinedOutput: String {
        let output = [
            String(data: stderr, encoding: .utf8),
            String(data: stdout, encoding: .utf8),
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return output.isEmpty ? "没有更多信息" : output
    }
}

private enum ProcessRunner {
    static func run(executable: URL, arguments: [String]) throws -> ProcessResult {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FizzDeckProcess-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let stdoutURL = root.appendingPathComponent("stdout")
        let stderrURL = root.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try? stdout.synchronize()
        try? stderr.synchronize()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: (try? Data(contentsOf: stdoutURL)) ?? Data(),
            stderr: (try? Data(contentsOf: stderrURL)) ?? Data()
        )
    }
}

private final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let destination: URL
    private let expectedBytes: Int64
    private let progress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()

    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var downloadedURL: URL?
    private var failure: Error?
    private var cancelled = false
    private var completed = false
    private var lastProgressBytes: Int64 = 0

    init(
        request: URLRequest,
        destination: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.request = request
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    func start(continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
        let task = session.downloadTask(with: request)
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        task?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : expectedBytes
        lock.lock()
        let shouldReport = totalBytesWritten - lastProgressBytes >= 256 * 1024
            || (total > 0 && totalBytesWritten >= total)
        if shouldReport {
            lastProgressBytes = totalBytesWritten
        }
        lock.unlock()
        if shouldReport {
            progress(totalBytesWritten, total)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            lock.lock()
            downloadedURL = destination
            lock.unlock()
        } catch {
            lock.lock()
            failure = AppUpdateError.downloadFailed(error.localizedDescription)
            lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let downloadedURL = downloadedURL
        let failure = failure
        let wasCancelled = cancelled
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()

        session?.invalidateAndCancel()

        if wasCancelled || (error as? URLError)?.code == .cancelled {
            try? FileManager.default.removeItem(at: destination)
            continuation?.resume(throwing: CancellationError())
        } else if let error {
            try? FileManager.default.removeItem(at: destination)
            continuation?.resume(throwing: AppUpdateError.downloadFailed(error.localizedDescription))
        } else if let failure {
            try? FileManager.default.removeItem(at: destination)
            continuation?.resume(throwing: failure)
        } else if let downloadedURL {
            continuation?.resume(returning: downloadedURL)
        } else {
            continuation?.resume(throwing: AppUpdateError.downloadFailed("下载未生成文件"))
        }
    }
}
