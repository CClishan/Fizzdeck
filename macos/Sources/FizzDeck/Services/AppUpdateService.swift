import Foundation

struct AppRelease: Sendable, Equatable {
    let version: String
    let pageURL: URL
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

enum AppUpdateService {
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

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let pageURL = URL(string: release.htmlURL) else {
            throw AppUpdateError.invalidResponse
        }

        return AppRelease(
            version: normalizedVersion(release.tagName),
            pageURL: pageURL
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

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}

private enum AppUpdateError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "暂时无法获取最新版本"
    }
}
