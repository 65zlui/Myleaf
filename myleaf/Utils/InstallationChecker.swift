import Foundation
import CoreServices

struct InstalledCopy: Identifiable {
    let url: URL
    let version: String
    let build: String

    var id: String { url.path }

    var displayVersion: String {
        build == "1" ? version : "\(version) (\(build))"
    }
}

/// Finds all registered copies of myleaf so the app can warn when an older
/// build is still installed next to the current one.
enum InstallationChecker {

    static let bundleIdentifier = "com.65zlui.myleaf"

    static func copies() -> [InstalledCopy] {
        var urls: [URL] = []

        var error: Unmanaged<CFError>?
        if let cfURLs = LSCopyApplicationURLsForBundleIdentifier(
            bundleIdentifier as CFString,
            &error
        ) {
            let array = cfURLs.takeRetainedValue() as NSArray
            urls = array.compactMap { $0 as? URL }
        }

        // The running bundle must always be included, even if LaunchServices
        // has not registered it yet (fresh build / test host).
        urls.append(Bundle.main.bundleURL)

        // Also cover user-level installs that may not be registered.
        let fm = FileManager.default
        let userApplications = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        for directory in [URL(fileURLWithPath: "/Applications"), userApplications] {
            guard let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            urls.append(contentsOf: entries.filter {
                $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("myleaf")
            })
        }

        var seen = Set<String>()
        var result: [InstalledCopy] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            guard standardized.pathExtension == "app" else { continue }

            let infoPath = standardized.appendingPathComponent("Contents/Info.plist")
            guard let info = NSDictionary(contentsOf: infoPath) as? [String: Any] else {
                continue
            }
            guard (info["CFBundleIdentifier"] as? String) == bundleIdentifier else {
                continue
            }

            result.append(InstalledCopy(
                url: standardized,
                version: info["CFBundleShortVersionString"] as? String ?? "?",
                build: info["CFBundleVersion"] as? String ?? "?"
            ))
        }

        return result.sorted { $0.url.path < $1.url.path }
    }
}
