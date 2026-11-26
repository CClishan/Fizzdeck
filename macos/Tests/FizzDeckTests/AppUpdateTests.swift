import XCTest
@testable import FizzDeck

final class AppUpdateTests: XCTestCase {
    func testNewerVersionComparison() {
        XCTAssertTrue(AppUpdateService.isNewer("v0.2.3", than: "0.2.2"))
        XCTAssertFalse(AppUpdateService.isNewer("v0.2.2", than: "0.2.2"))
    }

    func testVersionComparisonHandlesDifferentComponentCounts() {
        XCTAssertTrue(AppUpdateService.isNewer("0.3", than: "0.2.9"))
        XCTAssertFalse(AppUpdateService.isNewer("0.2", than: "0.2.0"))
    }

    func testReleaseParsesArm64DMGAndChecksumAssets() throws {
        let release = try AppUpdateService.release(from: fixtureData())

        XCTAssertEqual(release.version, "0.5.1")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/CClishan/Fizzdeck/releases/tag/v0.5.1")
        XCTAssertEqual(release.dmgAsset?.name, "FizzDeck-0.5.1-arm64.dmg")
        XCTAssertEqual(release.dmgAsset?.size, 12_345_678)
        XCTAssertEqual(
            release.dmgAsset?.downloadURL.absoluteString,
            "https://example.com/FizzDeck-0.5.1-arm64.dmg"
        )
        XCTAssertEqual(release.checksumAsset?.name, "FizzDeck-0.5.1-arm64.dmg.sha256")
        XCTAssertEqual(release.checksumAsset?.size, 96)
    }

    func testReleaseIgnoresIntelAndNonDMGAssets() throws {
        let data = Data(
            """
            {
              "tag_name": "v1.0.0",
              "html_url": "https://example.com/release",
              "assets": [
                {
                  "name": "FizzDeck-1.0.0-x86_64.dmg",
                  "browser_download_url": "https://example.com/intel.dmg",
                  "size": 10
                },
                {
                  "name": "FizzDeck-1.0.0-arm64.zip",
                  "browser_download_url": "https://example.com/app.zip",
                  "size": 20
                }
              ]
            }
            """.utf8
        )

        let release = try AppUpdateService.release(from: data)
        XCTAssertNil(release.dmgAsset)
        XCTAssertNil(release.checksumAsset)
    }

    func testSHA256DigestAndChecksumFormat() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-sha-\(UUID().uuidString)")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try SHA256Verifier.digestHex(for: url),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertEqual(
            SHA256Verifier.expectedDigest(
                in: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824  FizzDeck.dmg\n"
            ),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertNil(SHA256Verifier.expectedDigest(in: "not-a-checksum"))
    }

    func testUpdateStateMachineProgressAndInstallFlow() throws {
        let release = try AppUpdateService.release(from: fixtureData())
        let staged = URL(fileURLWithPath: "/tmp/FizzDeck.app")
        let dmg = URL(fileURLWithPath: "/tmp/FizzDeck.dmg")
        var machine = AppUpdateStateMachine()

        machine.apply(.checkStarted)
        XCTAssertEqual(machine.state, .checking)

        machine.apply(.checkFinished(release: release, isNewer: true))
        XCTAssertEqual(machine.state, .available(release))

        machine.apply(.downloadStarted(totalBytes: 100))
        machine.apply(.downloadProgress(receivedBytes: 50, totalBytes: 100))
        XCTAssertEqual(
            machine.state,
            .downloading(progress: 0.5, receivedBytes: 50, totalBytes: 100)
        )

        machine.apply(.downloadProgress(receivedBytes: 20, totalBytes: 100))
        XCTAssertEqual(
            machine.state,
            .downloading(progress: 0.5, receivedBytes: 50, totalBytes: 100)
        )

        machine.apply(.downloadProgress(receivedBytes: 200, totalBytes: 100))
        XCTAssertEqual(
            machine.state,
            .downloading(progress: 1, receivedBytes: 200, totalBytes: 100)
        )

        machine.apply(.verifying)
        XCTAssertEqual(machine.state, .verifying)

        machine.apply(.readyToInstall(stagedAppURL: staged, dmgURL: dmg))
        XCTAssertEqual(
            machine.state,
            .readyToInstall(stagedAppURL: staged, dmgURL: dmg)
        )

        machine.apply(.installStarted)
        XCTAssertEqual(machine.state, .installing)
    }

    func testUpdateStateMachineCanCancelBackToAvailable() throws {
        let release = try AppUpdateService.release(from: fixtureData())
        var machine = AppUpdateStateMachine()

        machine.apply(.checkFinished(release: release, isNewer: true))
        machine.apply(.downloadStarted(totalBytes: 100))
        machine.apply(.downloadCancelled(release))

        XCTAssertEqual(machine.state, .available(release))
    }

    func testInstallPlanRequiresAppBundleAndWritableParent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("FizzDeck.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let writable = AppUpdateService.installPlan(bundleURL: app) { _ in true }
        XCTAssertTrue(writable.canInstallInPlace)
        XCTAssertNil(writable.reason)
        XCTAssertEqual(writable.parentURL.standardizedFileURL, root.standardizedFileURL)

        let readOnly = AppUpdateService.installPlan(bundleURL: app) { _ in false }
        XCTAssertFalse(readOnly.canInstallInPlace)
        XCTAssertNotNil(readOnly.reason)

        let development = AppUpdateService.installPlan(
            bundleURL: root.appendingPathComponent("FizzDeck")
        ) { _ in true }
        XCTAssertFalse(development.canInstallInPlace)
        XCTAssertNotNil(development.reason)
    }

    func testInstallScriptCleansEmptyStagingDirectoryAfterMove() {
        let script = AppUpdateService.installScriptBody()
        XCTAssertTrue(script.contains(#"staging_dir="$(/usr/bin/dirname "$staged")""#))
        XCTAssertTrue(script.contains(#"/bin/rmdir "$staging_dir""#))
        XCTAssertTrue(script.contains(#"/bin/rm -rf "$staging_dir""#))
    }

    private func fixtureData() -> Data {
        Data(
            """
            {
              "tag_name": "v0.5.1",
              "html_url": "https://github.com/CClishan/Fizzdeck/releases/tag/v0.5.1",
              "assets": [
                {
                  "name": "FizzDeck-0.5.1-x86_64.dmg",
                  "browser_download_url": "https://example.com/intel.dmg",
                  "size": 111
                },
                {
                  "name": "FizzDeck-0.5.1-arm64.dmg",
                  "browser_download_url": "https://example.com/FizzDeck-0.5.1-arm64.dmg",
                  "size": 12345678
                },
                {
                  "name": "FizzDeck-0.5.1-arm64.dmg.sha256",
                  "browser_download_url": "https://example.com/FizzDeck-0.5.1-arm64.dmg.sha256",
                  "size": 96
                }
              ]
            }
            """.utf8
        )
    }
}
