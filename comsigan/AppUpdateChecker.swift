import Foundation
import Observation

nonisolated struct StoreRelease: Decodable, Sendable {
    let bundleId: String
    let version: String
    let trackViewUrl: URL
}

nonisolated enum AppUpdateService {
    static let storeURL = URL(string: "https://apps.apple.com/app/id6801513810")!

    /// 1.10 > 1.9, 1.1 == 1.1.0. 스토어의 정식 숫자 버전만 비교한다.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let next = components(candidate), let current = components(installed) else { return false }
        for index in 0..<max(next.count, current.count) {
            let a = index < next.count ? next[index] : 0
            let b = index < current.count ? current[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }

    static func release(from data: Data, bundleID: String) throws -> StoreRelease {
        struct Response: Decodable { let results: [StoreRelease] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let release = response.results.first(where: { $0.bundleId == bundleID }),
              components(release.version) != nil,
              release.trackViewUrl.scheme == "https", release.trackViewUrl.host == "apps.apple.com" else {
            throw URLError(.cannotParseResponse)
        }
        return release
    }

    static func latestRelease(bundleID: String) async throws -> StoreRelease {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID),
                                 URLQueryItem(name: "country", value: "kr")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try release(from: data, bundleID: bundleID)
    }
}

@MainActor @Observable
final class AppUpdateChecker {
    private(set) var isChecking = false
    private(set) var message: String?
    private(set) var availableRelease: StoreRelease?
    var showsUpdate = false
    private var promptedVersion: String?
    private let checkedKey = "lastSuccessfulUpdateCheck"

    var destination: URL { availableRelease?.trackViewUrl ?? AppUpdateService.storeURL }

    func check(automatically: Bool = false) async {
        guard !isChecking else { return }
        if automatically, let checked = UserDefaults.standard.object(forKey: checkedKey) as? Date,
           Date().timeIntervalSince(checked) < 24 * 60 * 60 { return }
        isChecking = true
        message = nil
        defer { isChecking = false }
        do {
            guard let bundleID = Bundle.main.bundleIdentifier,
                  let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                throw URLError(.cannotParseResponse)
            }
            let release = try await AppUpdateService.latestRelease(bundleID: bundleID)
            try Task.checkCancellation()
            UserDefaults.standard.set(Date(), forKey: checkedKey)
            if AppUpdateService.isNewer(release.version, than: installed) {
                availableRelease = release
                message = "새 버전 \(release.version)이 있습니다."
                if !automatically || promptedVersion != release.version {
                    promptedVersion = release.version
                    showsUpdate = true
                }
            } else {
                availableRelease = nil
                message = "최신 버전입니다."
            }
        } catch is CancellationError {
            return
        } catch {
            if !automatically { message = "업데이트를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요." }
        }
    }
}
