import Foundation

@main
struct AppUpdateChecks {
    static func main() async throws {
        precondition(AppUpdateService.isNewer("1.10", than: "1.9"))
        precondition(AppUpdateService.isNewer("2.0", than: "1.99.99"))
        precondition(AppUpdateService.isNewer("1.1.1", than: "1.1"))
        precondition(!AppUpdateService.isNewer("1.1.0", than: "1.1"))
        precondition(!AppUpdateService.isNewer("1.0", than: "1.1"))
        precondition(!AppUpdateService.isNewer("", than: "1"))
        precondition(!AppUpdateService.isNewer("1..2", than: "1"))
        precondition(!AppUpdateService.isNewer("2-beta", than: "1"))
        let valid = Data(#"{"results":[{"bundleId":"com.yftech.comsigan","version":"1.2.0","trackViewUrl":"https://apps.apple.com/app/id6801513810"}]}"#.utf8)
        let release = try AppUpdateService.release(from: valid, bundleID: "com.yftech.comsigan")
        precondition(release.version == "1.2.0")
        for invalid in [
            #"{"results":[]}"#,
            #"{"results":[{"bundleId":"other.app","version":"1.2.0","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#,
            #"{"results":[{"bundleId":"com.yftech.comsigan","version":"bad","trackViewUrl":"https://apps.apple.com/app/id1"}]}"#,
            #"{"results":[{"bundleId":"com.yftech.comsigan","version":"1.2.0","trackViewUrl":"https://example.com/app"}]}"#,
        ] {
            do {
                _ = try AppUpdateService.release(from: Data(invalid.utf8), bundleID: "com.yftech.comsigan")
                fatalError("Invalid store release accepted")
            } catch {}
        }
        print("Update comparison and store-response regression checks passed")
        if CommandLine.arguments.contains("--live") {
            let live = try await AppUpdateService.latestRelease(bundleID: "com.yftech.comsigan")
            print("App Store lookup passed: \(live.version), \(live.trackViewUrl)")
        }
    }
}
